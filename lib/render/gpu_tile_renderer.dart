import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../data/chunk_cache_manager.dart';
import '../data/data_manager.dart';
import '../models/app_settings.dart';
import '../models/chunk_key.dart';
import '../nbt/nbt_parser.dart';
import '../nbt/nbt_tags.dart';
import '../services/legacy_chunk_decoder.dart';
import '../utils/game_data_service.dart';
import 'map_layer_types.dart';

/// GPU 纹理瓦片渲染引擎 (真实原版地貌 + 史莱姆区块半透明叠加 + 精准生态群系 + 消除矿石透视)
class GpuTileRenderer {
  static final GpuTileRenderer _instance = GpuTileRenderer._internal();
  factory GpuTileRenderer() => _instance;
  GpuTileRenderer._internal();

  final Set<String> _pendingGenerations = {};
  int _inFlightCount = 0;
  static const int _maxInFlight = 16;
  Timer? _batchNotifyTimer;
  final Set<VoidCallback> _pendingCallbacks = {};

  void _dispatchTileReady(VoidCallback? callback) {
    if (callback == null) return;
    _pendingCallbacks.add(callback);
    if (_batchNotifyTimer == null || !_batchNotifyTimer!.isActive) {
      _batchNotifyTimer = Timer(const Duration(milliseconds: 32), () {
        final callbacks = List<VoidCallback>.from(_pendingCallbacks);
        _pendingCallbacks.clear();
        for (final cb in callbacks) {
          try {
            cb();
          } catch (_) {}
        }
      });
    }
  }

  /// 绘制单个区块的 GPU 纹理瓦片 (含 LOD 极速宏观降级)
  void drawChunkTile({
    required Canvas canvas,
    required int chunkX,
    required int chunkZ,
    required int dimension,
    required MapLayerMode layerMode,
    required Rect destRect,
    required DataManager dataManager,
    required Paint paint,
    VoidCallback? onTileReady,
  }) {
    // 关键：未在数据库中生成的区块，坚决不进行渲染或占位
    if (!dataManager.hasChunk(chunkX, chunkZ, dimension)) {
      return;
    }

    final cache = ChunkCacheManager();
    final tile = cache.getGpuTile(chunkX, chunkZ, dimension, layerMode);

    if (tile != null) {
      // GPU 纹理硬件直绘
      const srcRect = Rect.fromLTWH(0, 0, 16, 16);
      canvas.drawImageRect(tile.gpuImage, srcRect, destRect, paint);
    } else {
      // LOD 宏观远景 (单区块屏幕尺寸 < 4px): 直接使用维度基础地形色直绘，杜绝远景瞬间并发创建数万个微型纹理卡死
      final isMacroView = destRect.width < 4.0;
      final fallbackColor = dimension == 1
          ? const Color(0xFF6B1D1D)
          : (dimension == 2 ? const Color(0xFFD6C896) : const Color(0xFF3B7A38));
      canvas.drawRect(destRect, Paint()..color = fallbackColor);

      if (!isMacroView && _inFlightCount < _maxInFlight && _pendingGenerations.length < 256) {
        _scheduleTileGeneration(
          chunkX: chunkX,
          chunkZ: chunkZ,
          dimension: dimension,
          layerMode: layerMode,
          dataManager: dataManager,
          onTileReady: onTileReady,
        );
      }
    }
  }

  void _scheduleTileGeneration({
    required int chunkX,
    required int chunkZ,
    required int dimension,
    required MapLayerMode layerMode,
    required DataManager dataManager,
    VoidCallback? onTileReady,
  }) {
    if (!dataManager.hasChunk(chunkX, chunkZ, dimension)) return;

    final key = '$dimension:${layerMode.name}:$chunkX,$chunkZ';
    if (_pendingGenerations.contains(key)) return;
    _pendingGenerations.add(key);
    _inFlightCount++;

    Future(() async {
      try {
        final pixels = await _generateChunkPixels(chunkX, chunkZ, dimension, layerMode, dataManager);
        final completer = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          pixels,
          16,
          16,
          ui.PixelFormat.rgba8888,
          completer.complete,
        );
        final gpuImage = await completer.future;
        ChunkCacheManager().putGpuTile(chunkX, chunkZ, dimension, layerMode, gpuImage);
        _dispatchTileReady(onTileReady);
      } catch (_) {
      } finally {
        _pendingGenerations.remove(key);
        _inFlightCount = (_inFlightCount - 1).clamp(0, 999);
      }
    });
  }

  /// 生成 16×16 RGBA 像素数据 (1024 字节)
  Future<Uint8List> _generateChunkPixels(
    int cx,
    int cz,
    int dim,
    MapLayerMode layer,
    DataManager dm,
  ) async {
    final pixels = Uint8List(16 * 16 * 4);
    if (!dm.hasChunk(cx, cz, dim)) return pixels;

    final gds = GameDataService();
    final settings = AppSettings();

    // 1. 读取 Data3D (Tag 43) 或 Data2D (Tag 45) 获取高度与群系
    Uint16List heights = Uint16List(256);
    Uint8List biomes = Uint8List(256);

    final key3D = ParsedChunkKey.buildKey(cx, cz, dim, ChunkTag.data3D);
    final b64_3D = base64Encode(key3D);
    final key2D = ParsedChunkKey.buildKey(cx, cz, dim, ChunkTag.data2D);
    final b64_2D = base64Encode(key2D);

    if (dm.rawEntries.containsKey(b64_3D)) {
      final data = dm.rawEntries[b64_3D]!;
      if (data.length >= 512) {
        final bd = ByteData.sublistView(data, 0, 512);
        for (int i = 0; i < 256; i++) {
          heights[i] = bd.getUint16(i * 2, Endian.little);
        }
      }
      if (data.length > 512) {
        if (data.length >= 512 + 1024) {
          final bd = ByteData.sublistView(data);
          for (int i = 0; i < 256; i++) {
            biomes[i] = bd.getUint32(512 + i * 4, Endian.little) & 0xFF;
          }
        } else if (data.length >= 512 + 256) {
          for (int i = 0; i < 256; i++) {
            biomes[i] = data[512 + i];
          }
        }
      }
    } else if (dm.rawEntries.containsKey(b64_2D)) {
      final data = dm.rawEntries[b64_2D]!;
      final decoded = LegacyChunkDecoder.decodeData2D(data);
      biomes = decoded['biomes'] as Uint8List;
      heights = decoded['heights'] as Uint16List;
    }

    // 2. 高度图模式
    if (layer == MapLayerMode.heightmap) {
      for (int z = 0; z < 16; z++) {
        for (int x = 0; x < 16; x++) {
          final idx = z * 16 + x;
          final h = heights[idx];
          final color = MapLayerConfig.heightToColor(h);
          final off = idx * 4;
          pixels[off] = (color.r * 255).round();
          pixels[off + 1] = (color.g * 255).round();
          pixels[off + 2] = (color.b * 255).round();
          pixels[off + 3] = 255;
        }
      }
      return pixels;
    }

    // 3. 群系图模式
    if (layer == MapLayerMode.biome) {
      for (int z = 0; z < 16; z++) {
        for (int x = 0; x < 16; x++) {
          final idx = z * 16 + x;
          final bId = biomes[idx];
          final color = MapLayerConfig.biomeToColor(bId);
          final off = idx * 4;
          pixels[off] = (color.r * 255).round();
          pixels[off + 1] = (color.g * 255).round();
          pixels[off + 2] = (color.b * 255).round();
          pixels[off + 3] = 255;
        }
      }
      return pixels;
    }

    // 4. 卫星地图 / 史莱姆半透明叠加图 / 原版方块图
    final surfaceData = _getChunkSurfaceBlocks(cx, cz, dim, dm);
    final surfaceBlocks = surfaceData['blocks'] as List<String>;
    final surfaceHeights = surfaceData['heights'] as Uint16List;

    final intensity = settings.hillshadeIntensity;
    final isSlime = (layer == MapLayerMode.slimeChunk) && (dim == 0) && isSlimeChunk(cx, cz);
    final slimeColor = settings.slimeChunkColor;
    final slimeR = (slimeColor.r * 255).round();
    final slimeG = (slimeColor.g * 255).round();
    final slimeB = (slimeColor.b * 255).round();

    for (int z = 0; z < 16; z++) {
      for (int x = 0; x < 16; x++) {
        final idx = z * 16 + x;
        final blockId = surfaceBlocks[idx];
        final biomeId = biomes[idx];

        // 优先采用扫描得到的真实物理地表高度计算光影坡度
        final h = surfaceHeights[idx] > 0 ? surfaceHeights[idx] : heights[idx];
        final northH = z > 0 ? (surfaceHeights[(z - 1) * 16 + x] > 0 ? surfaceHeights[(z - 1) * 16 + x] : heights[(z - 1) * 16 + x]) : h;

        // 计算高度光影差
        double shade = 1.0;
        if (settings.smoothShading) {
          shade = 1.0 + (h - northH) * 0.08 * intensity;
          shade = shade.clamp(0.65, 1.35);
        }

        final baseColor = _resolveBlockColor(blockId, biomeId, dim, gds);
        int r = ((baseColor.r * 255) * shade).round().clamp(0, 255);
        int g = ((baseColor.g * 255) * shade).round().clamp(0, 255);
        int b = ((baseColor.b * 255) * shade).round().clamp(0, 255);
        int a = (baseColor.a * 255).round();

        // 史莱姆区块半透明绿色叠加 (Overlay on Satellite Map)
        if (isSlime) {
          final isBorder = (x == 0 || x == 15 || z == 0 || z == 15);
          final double alpha = isBorder ? 0.75 : 0.40;
          r = (r * (1.0 - alpha) + slimeR * alpha).round().clamp(0, 255);
          g = (g * (1.0 - alpha) + slimeG * alpha).round().clamp(0, 255);
          b = (b * (1.0 - alpha) + slimeB * alpha).round().clamp(0, 255);
        }

        final off = idx * 4;
        pixels[off] = r;
        pixels[off + 1] = g;
        pixels[off + 2] = b;
        pixels[off + 3] = a;
      }
    }

    return pixels;
  }

  /// 获取区块 16×16 表面方块名称与高度 (下界穿透基岩 + 主世界准确捕捉天空暴露地表)
  Map<String, dynamic> _getChunkSurfaceBlocks(int cx, int cz, int dim, DataManager dm) {
    final cached = ChunkCacheManager().getSubChunkBlocks(cx, cz, dim == 1 ? 998 : 999);
    if (cached != null) {
      return {'blocks': cached, 'heights': Uint16List(256)};
    }

    final defaultBlock = dim == 1 ? 'minecraft:netherrack' : (dim == 2 ? 'minecraft:end_stone' : 'minecraft:dirt');
    final resultBlocks = List.filled(256, defaultBlock);
    final resultHeights = Uint16List(256);

    if (dim == 1) {
      // ─── 下界维度穿透扫描算法 ───
      final subChunks = <int, List<String>>{};
      for (int subY = 7; subY >= 0; subY--) {
        final key = ParsedChunkKey.buildKey(cx, cz, dim, ChunkTag.subChunk, subChunkY: subY);
        final b64 = base64Encode(key);
        if (dm.rawEntries.containsKey(b64)) {
          final data = dm.rawEntries[b64]!;
          final decoded = _decodeSubChunkBlocks(data);
          if (decoded != null && decoded.length >= 4096) {
            subChunks[subY] = decoded;
          }
        }
      }

      for (int x = 0; x < 16; x++) {
        for (int z = 0; z < 16; z++) {
          final colIdx = z * 16 + x;
          bool passedCeiling = false;
          String foundBlock = 'minecraft:netherrack';
          int foundY = 64;

          for (int y = 127; y >= 0; y--) {
            final subY = y >> 4;
            final innerY = y & 0xF;
            final chunkData = subChunks[subY];
            if (chunkData == null) continue;

            final blockIdx = (x * 16 + z) * 16 + innerY;
            final name = blockIdx < chunkData.length ? chunkData[blockIdx] : 'minecraft:air';

            if (!passedCeiling) {
              if (name == 'minecraft:air' || name == 'minecraft:cave_air' || name == 'minecraft:void_air') {
                passedCeiling = true;
              }
            } else {
              if (name != 'minecraft:air' && name != 'minecraft:cave_air' && name != 'minecraft:void_air') {
                foundBlock = name;
                foundY = y;
                break;
              }
            }
          }

          resultBlocks[colIdx] = foundBlock;
          resultHeights[colIdx] = foundY;
        }
      }
    } else {
      // ─── 主世界 / 末地自顶向下地表扫描 ───
      final int startSubY = dim == 2 ? 15 : 19;
      final int endSubY = dim == 2 ? 0 : -4;
      final foundMask = List.filled(256, false);

      for (int subY = startSubY; subY >= endSubY; subY--) {
        final key = ParsedChunkKey.buildKey(cx, cz, dim, ChunkTag.subChunk, subChunkY: subY);
        final b64 = base64Encode(key);

        if (dm.rawEntries.containsKey(b64)) {
          final subChunkData = dm.rawEntries[b64]!;
          final blockNames = _decodeSubChunkBlocks(subChunkData);
          if (blockNames != null && blockNames.length >= 4096) {
            for (int x = 0; x < 16; x++) {
              for (int z = 0; z < 16; z++) {
                final colIdx = z * 16 + x;
                if (!foundMask[colIdx]) {
                  for (int y = 15; y >= 0; y--) {
                    final blockIdx = (x * 16 + z) * 16 + y;
                    if (blockIdx < blockNames.length) {
                      final name = blockNames[blockIdx];
                      // 忽略所有空气类型，捕捉地表第一个实体/流体/植物
                      if (name != 'minecraft:air' && name != 'minecraft:cave_air' && name != 'minecraft:void_air') {
                        resultBlocks[colIdx] = name;
                        resultHeights[colIdx] = (subY * 16) + y;
                        foundMask[colIdx] = true;
                        break;
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    ChunkCacheManager().putSubChunkBlocks(cx, cz, dim == 1 ? 998 : 999, resultBlocks);
    return {'blocks': resultBlocks, 'heights': resultHeights};
  }

  /// 解码 SubChunk 中的 4096 方块列表
  List<String>? _decodeSubChunkBlocks(Uint8List data) {
    if (data.isEmpty) return null;
    final version = data[0];

    // 兼容 Version 8 与 Version 9
    if (version == 8 || version == 9) {
      int offset = version == 9 ? 3 : 2;
      if (offset >= data.length) return null;

      final header = data[offset++];
      final bitsPerBlock = header >> 1;
      if (bitsPerBlock == 0) return null;

      final blocksPerWord = 32 ~/ bitsPerBlock;
      final wordCount = (4096 + blocksPerWord - 1) ~/ blocksPerWord;

      final indices = List.filled(4096, 0);
      final bd = ByteData.sublistView(data);
      int index = 0;

      for (int w = 0; w < wordCount && (offset + w * 4 + 4) <= data.length; w++) {
        final word = bd.getUint32(offset + w * 4, Endian.little);
        for (int b = 0; b < blocksPerWord && index < 4096; b++) {
          indices[index++] = (word >> (b * bitsPerBlock)) & ((1 << bitsPerBlock) - 1);
        }
      }
      offset += wordCount * 4;

      if (offset + 4 > data.length) return null;
      final paletteSize = bd.getUint32(offset, Endian.little);
      offset += 4;

      final paletteNames = <String>[];
      final parser = LittleEndianNbtParser();

      for (int p = 0; p < paletteSize && offset < data.length; p++) {
        try {
          final tag = parser.parseFromBuffer(data.sublist(offset));
          if (tag is NbtCompound && tag.value.containsKey('name')) {
            final nameTag = tag.value['name'];
            if (nameTag is NbtString) {
              paletteNames.add(nameTag.value);
            } else {
              paletteNames.add('minecraft:stone');
            }
          }
          offset += parser.bytesRead;
        } catch (_) {
          break;
        }
      }

      if (paletteNames.isNotEmpty) {
        return indices.map((idx) => idx < paletteNames.length ? paletteNames[idx] : 'minecraft:air').toList();
      }
    } else {
      return LegacyChunkDecoder.decodeLegacySubChunk(data);
    }

    return null;
  }

  /// 匹配方块真实色彩 (融入生态群系 Grass Tint，彻底剔除矿石透视与高亮)
  Color _resolveBlockColor(String blockId, int biomeId, int dim, GameDataService gds) {
    final cleanId = blockId.replaceAll('minecraft:', '').toLowerCase();

    // 1. 下界专属方块调色
    if (dim == 1 || cleanId.contains('nether') || cleanId.contains('crimson') || cleanId.contains('warped') || cleanId.contains('soul')) {
      if (cleanId == 'netherrack') return const Color(0xFF6F2828);
      if (cleanId == 'lava' || cleanId == 'flowing_lava') return const Color(0xFFFF5500);
      if (cleanId == 'soul_sand') return const Color(0xFF4D3B31);
      if (cleanId == 'soul_soil') return const Color(0xFF42332A);
      if (cleanId == 'basalt' || cleanId == 'polished_basalt') return const Color(0xFF48484E);
      if (cleanId == 'blackstone' || cleanId.contains('blackstone')) return const Color(0xFF27222A);
      if (cleanId == 'crimson_nylium') return const Color(0xFF992424);
      if (cleanId == 'warped_nylium') return const Color(0xFF2B6865);
      if (cleanId == 'crimson_stem' || cleanId == 'crimson_planks') return const Color(0xFF6E1838);
      if (cleanId == 'warped_stem' || cleanId == 'warped_planks') return const Color(0xFF356A69);
      if (cleanId == 'nether_bricks' || cleanId == 'red_nether_bricks') return const Color(0xFF30181C);
      if (cleanId == 'glowstone') return const Color(0xFFFFD54F);
      if (cleanId == 'shroomlight') return const Color(0xFFFF8A50);
      if (cleanId == 'magma_block' || cleanId == 'magma') return const Color(0xFF93361E);
      if (cleanId == 'ancient_debris') return const Color(0xFF58443B);
      if (cleanId == 'crying_obsidian') return const Color(0xFF3E136B);
      if (cleanId == 'bone_block') return const Color(0xFFDCD6BC);
      if (cleanId == 'quartz_ore') return const Color(0xFF8A4949);
      if (cleanId == 'nether_gold_ore') return const Color(0xFF8C3E2E);
    }

    // 2. 草方块与草类植物 -> 生态群系调色
    if (cleanId == 'grass_block' || cleanId == 'grass' || cleanId == 'short_grass' || cleanId == 'tallgrass' || cleanId == 'fern' || cleanId == 'large_fern') {
      return _getGrassColorForBiome(biomeId);
    }

    // 3. 树叶类
    if (cleanId == 'oak_leaves' || cleanId == 'leaves') return _getOakLeavesColorForBiome(biomeId);
    if (cleanId == 'birch_leaves') return const Color(0xFF80A755);
    if (cleanId == 'spruce_leaves') return const Color(0xFF619961);
    if (cleanId == 'jungle_leaves') return const Color(0xFF59C93C);
    if (cleanId == 'acacia_leaves') return const Color(0xFF82A93B);
    if (cleanId == 'dark_oak_leaves') return const Color(0xFF507A32);
    if (cleanId == 'mangrove_leaves') return const Color(0xFF77AB2F);
    if (cleanId == 'cherry_leaves') return const Color(0xFFE488AF);
    if (cleanId == 'azalea_leaves' || cleanId == 'flowering_azalea_leaves') return const Color(0xFF64A038);

    // 4. 水体与流体
    if (cleanId == 'water' || cleanId == 'flowing_water') return const Color(0xFF3F76E4);
    if (cleanId == 'lava' || cleanId == 'flowing_lava') return const Color(0xFFFF5500);

    // 5. 末地方块
    if (cleanId == 'end_stone' || cleanId == 'end_stone_bricks') return const Color(0xFFDCDC9D);
    if (cleanId == 'purpur_block' || cleanId == 'purpur_pillar') return const Color(0xFFA97DA9);
    if (cleanId == 'obsidian') return const Color(0xFF14101E);

    // 6. 主世界自然方块
    if (cleanId == 'dirt' || cleanId == 'coarse_dirt' || cleanId == 'rooted_dirt') return const Color(0xFF866043);
    if (cleanId == 'dirt_path' || cleanId == 'grass_path') return const Color(0xFF9E773D);
    if (cleanId == 'mycelium') return const Color(0xFF6F6265);
    if (cleanId == 'podzol') return const Color(0xFF5B3F1E);
    if (cleanId == 'stone' || cleanId == 'smooth_stone') return const Color(0xFF808080);
    if (cleanId == 'cobblestone' || cleanId == 'mossy_cobblestone') return const Color(0xFFA0A0A0);
    if (cleanId == 'granite' || cleanId == 'polished_granite') return const Color(0xFF8C7167);
    if (cleanId == 'diorite' || cleanId == 'polished_diorite') return const Color(0xFFC6C6C6);
    if (cleanId == 'andesite' || cleanId == 'polished_andesite') return const Color(0xFF797777);
    if (cleanId == 'deepslate' || cleanId == 'cobbled_deepslate') return const Color(0xFF333339);
    if (cleanId == 'tuff') return const Color(0xFF595853);
    if (cleanId == 'calcite') return const Color(0xFFDFDFD8);
    if (cleanId == 'sand' || cleanId == 'sandstone') return const Color(0xFFDBD3A0);
    if (cleanId == 'red_sand' || cleanId == 'red_sandstone') return const Color(0xFFA7531F);
    if (cleanId == 'gravel') return const Color(0xFF827E7B);
    if (cleanId == 'clay') return const Color(0xFFA0A6B5);
    if (cleanId == 'snow' || cleanId == 'snow_block') return const Color(0xFFF0F5F5);
    if (cleanId == 'ice' || cleanId == 'packed_ice' || cleanId == 'blue_ice') return const Color(0xFF90C0FF);
    if (cleanId == 'bedrock') return const Color(0xFF282828);

    // 7. 彻底移除矿石透视与高亮：所有自然矿石统一融入岩石基底色彩
    if (cleanId.contains('deepslate') && cleanId.contains('ore')) {
      return const Color(0xFF333339);
    }
    if (cleanId.contains('ore')) {
      return const Color(0xFF808080);
    }

    // 8. 木材
    if (cleanId.contains('planks') || cleanId.contains('log') || cleanId.contains('wood')) {
      if (cleanId.contains('oak')) return const Color(0xFF9C7F4E);
      if (cleanId.contains('spruce')) return const Color(0xFF5A3D0D);
      if (cleanId.contains('birch')) return const Color(0xFFDABD8D);
      if (cleanId.contains('jungle')) return const Color(0xFFBA7D5D);
      if (cleanId.contains('acacia')) return const Color(0xFF934F39);
      if (cleanId.contains('dark_oak')) return const Color(0xFF3B260F);
      if (cleanId.contains('mangrove')) return const Color(0xFF723028);
      if (cleanId.contains('cherry')) return const Color(0xFFDEB0A8);
      if (cleanId.contains('bamboo')) return const Color(0xFFC0B359);
      return const Color(0xFF9E7C53);
    }

    return const Color(0xFF757575);
  }

  /// 计算生态群系草方块真实色调 (严格对齐 assrts/data/biomes.json 官方 ID 表)
  Color _getGrassColorForBiome(int biomeId) {
    switch (biomeId) {
      case 1: // 平原
      case 129: // 向日葵平原
        return const Color(0xFF91BD59);
      case 4: // 森林
      case 18: // 繁茂的丘陵
      case 132: // 繁花森林
        return const Color(0xFF79C05A);
      case 27: // 桦木森林
      case 28: // 桦木森林丘陵
      case 155: // 原始桦木森林
      case 156: // 高大桦木丘陵
        return const Color(0xFF88BB67);
      case 5: // 针叶林
      case 12: // 雪原
      case 19: // 针叶林丘陵
      case 30: // 积雪针叶林
      case 31: // 积雪的针叶林丘陵
      case 32: // 原始松木针叶林
      case 33: // 巨型针叶林丘陵
      case 133: // 针叶林山地
      case 140: // 冰刺之地
      case 158: // 积雪的针叶林山地
      case 160: // 原始云杉针叶林
      case 161: // 巨型云杉针叶林丘陵
      case 184: // 积雪山坡
      case 185: // 雪林
        return const Color(0xFF86B783);
      case 21: // 丛林
      case 22: // 丛林丘陵
      case 23: // 稀疏丛林
      case 48: // 竹林
      case 49: // 竹林丘陵
      case 149: // 丛林变种
      case 151: // 丛林边缘变种
      case 187: // 繁茂洞穴
        return const Color(0xFF59C93C);
      case 2: // 沙漠
      case 17: // 沙漠丘陵
      case 35: // 热带草原
      case 36: // 热带高原
      case 130: // 沙漠湖泊
      case 163: // 风袭热带草原
      case 164: // 破碎的热带高原
        return const Color(0xFFBFB755);
      case 6: // 沼泽
      case 134: // 沼泽丘陵
        return const Color(0xFF6A7039);
      case 29: // 黑森林
      case 157: // 黑森林丘陵
        return const Color(0xFF507A32);
      case 14: // 蘑菇岛
      case 15: // 蘑菇岛岸
        return const Color(0xFF55C93F);
      case 37: // 恶地
      case 38: // 繁茂的恶地高原
      case 39: // 恶地高原
      case 165: // 风蚀恶地
      case 166: // 繁茂的恶地高原变种
      case 167: // 恶地高原变种
        return const Color(0xFF90814D);
      case 186: // 草甸 (meadow)
        return const Color(0xFF63C47D);
      case 191: // 红树林沼泽 (mangrove_swamp)
        return const Color(0xFF6DA339);
      case 192: // 樱花树林 (cherry_grove)
        return const Color(0xFFB5E285);
      case 193: // 苍白之园 (pale_garden)
        return const Color(0xFF8B8C89);
      default:
        return const Color(0xFF7CBD6B);
    }
  }

  Color _getOakLeavesColorForBiome(int biomeId) {
    switch (biomeId) {
      case 6: // Swamp
        return const Color(0xFF6A7039);
      case 29: // Dark Forest
        return const Color(0xFF507A32);
      default:
        return const Color(0xFF77AB2F);
    }
  }

  /// 基岩版史莱姆区块算法
  static bool isSlimeChunk(int cx, int cz) {
    int val = (cx * 0x1f1f1f1f) ^ cz;
    int hash = ((val * 0x27E1) + 0x3AD8025F) & 0xFFFFFFFF;
    return (hash % 10) == 0;
  }
}
