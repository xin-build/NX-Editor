import 'dart:convert';
import 'dart:typed_data';
import '../data/chunk_cache_manager.dart';
import '../data/data_manager.dart';
import '../models/chunk_key.dart';
import '../models/selection_model.dart';
import '../nbt/nbt_parser.dart';
import '../nbt/nbt_tags.dart';

/// 选区地形与区块批量编辑服务 (支持多维度、自动清除 GPU 瓦片缓存)
class TerrainEditService {
  static final TerrainEditService _instance = TerrainEditService._internal();
  factory TerrainEditService() => _instance;
  TerrainEditService._internal();

  /// 选区方块查找与替换 (Search & Replace)
  Future<int> searchAndReplace({
    required SelectionModel selection,
    required String fromBlockId,
    required String toBlockId,
    required DataManager dm,
  }) async {
    final cleanFrom = fromBlockId.startsWith('minecraft:') ? fromBlockId : 'minecraft:$fromBlockId';
    final cleanTo = toBlockId.startsWith('minecraft:') ? toBlockId : 'minecraft:$toBlockId';

    int modifiedChunks = 0;
    final minSubY = (selection.minY / 16).floor();
    final maxSubY = (selection.maxY / 16).floor();

    for (int cx = selection.minChunkX; cx <= selection.maxChunkX; cx++) {
      for (int cz = selection.minChunkZ; cz <= selection.maxChunkZ; cz++) {
        for (int subY = minSubY; subY <= maxSubY; subY++) {
          final keyBytes = ParsedChunkKey.buildKey(cx, cz, selection.dimension, ChunkTag.subChunk, subChunkY: subY);
          final base64Key = base64Encode(keyBytes);

          if (dm.rawEntries.containsKey(base64Key)) {
            final subChunkData = dm.rawEntries[base64Key]!;
            final modified = _replaceBlockInSubChunk(subChunkData, cleanFrom, cleanTo);
            if (modified != null) {
              dm.rawEntries[base64Key] = modified;
              modifiedChunks++;
            }
          }
        }
      }
    }

    // 清除已修改区块的 GPU 纹理与方块缓存
    for (int cx = selection.minChunkX; cx <= selection.maxChunkX; cx++) {
      for (int cz = selection.minChunkZ; cz <= selection.maxChunkZ; cz++) {
        ChunkCacheManager().clearChunk(cx, cz, selection.dimension);
      }
    }
    ChunkCacheManager().clearAll();
    dm.notifyDataChanged();

    return modifiedChunks;
  }

  /// 在单个 SubChunk 二进制中替换调色板方块名称
  Uint8List? _replaceBlockInSubChunk(Uint8List data, String from, String to) {
    if (data.isEmpty) return null;
    final version = data[0];
    if (version != 8 && version != 9) return null;

    int offset = version == 9 ? 3 : 2;
    if (offset >= data.length) return null;

    final header = data[offset++];
    final bitsPerBlock = header >> 1;
    if (bitsPerBlock == 0) return null;

    final blocksPerWord = 32 ~/ bitsPerBlock;
    final wordCount = (4096 + blocksPerWord - 1) ~/ blocksPerWord;
    offset += wordCount * 4;

    if (offset + 4 > data.length) return null;

    final bd = ByteData.sublistView(data);
    final paletteSize = bd.getUint32(offset, Endian.little);
    final paletteOffset = offset + 4;

    final parser = LittleEndianNbtParser();
    final writer = LittleEndianNbtWriter();
    final paletteCompounds = <NbtCompound>[];
    int curOffset = paletteOffset;
    bool found = false;

    for (int i = 0; i < paletteSize && curOffset < data.length; i++) {
      try {
        final tag = parser.parseFromBuffer(data.sublist(curOffset));
        if (tag is NbtCompound) {
          if (tag.value.containsKey('name')) {
            final nameTag = tag.value['name'];
            if (nameTag is NbtString && nameTag.value == from) {
              tag.value['name'] = NbtString(to);
              found = true;
            }
          }
          paletteCompounds.add(tag);
        }
        curOffset += parser.bytesRead;
      } catch (_) {
        break;
      }
    }

    if (!found) return null;

    final builder = BytesBuilder();
    builder.add(data.sublist(0, paletteOffset));
    for (final tag in paletteCompounds) {
      builder.add(writer.writeRoot('', tag));
    }

    if (curOffset < data.length) {
      builder.add(data.sublist(curOffset));
    }

    return builder.toBytes();
  }

  /// 批量删除/重置选区内的区块 (支持多维度，同步清除 GPU 纹理与 LevelDB 数据)
  int deleteChunks({
    required SelectionModel selection,
    required DataManager dm,
  }) {
    final keysToRemove = <String>[];
    final targetDim = selection.dimension;

    for (final entry in dm.rawKeyMap.entries) {
      final base64Key = entry.key;
      final rawKey = entry.value;

      final parsed = ParsedChunkKey.parse(rawKey);
      if (parsed != null && parsed.dimension == targetDim) {
        if (selection.containsChunk(parsed.chunkX, parsed.chunkZ)) {
          keysToRemove.add(base64Key);
        }
      }
    }

    // 从数据库条目中移除
    for (final k in keysToRemove) {
      dm.rawEntries.remove(k);
      dm.rawKeyMap.remove(k);
    }

    // 从已有区块集合与缓存中彻底清除
    for (int cx = selection.minChunkX; cx <= selection.maxChunkX; cx++) {
      for (int cz = selection.minChunkZ; cz <= selection.maxChunkZ; cz++) {
        dm.existingChunks.remove('$targetDim:$cx,$cz');
        ChunkCacheManager().clearChunk(cx, cz, targetDim);
      }
    }

    ChunkCacheManager().clearAll();
    dm.notifyDataChanged();

    return selection.totalChunks;
  }

  /// 批量修改选区生态群系 (Change Biome)
  int changeBiome({
    required SelectionModel selection,
    required int targetBiomeId,
    required DataManager dm,
  }) {
    int count = 0;
    final targetDim = selection.dimension;

    for (int cx = selection.minChunkX; cx <= selection.maxChunkX; cx++) {
      for (int cz = selection.minChunkZ; cz <= selection.maxChunkZ; cz++) {
        // 修改 3D 群系 (Tag 43)
        final key3D = ParsedChunkKey.buildKey(cx, cz, targetDim, ChunkTag.data3D);
        final b64_3D = base64Encode(key3D);
        if (dm.rawEntries.containsKey(b64_3D)) {
          final data = Uint8List.fromList(dm.rawEntries[b64_3D]!);
          if (data.length > 512) {
            for (int i = 512; i < data.length; i++) {
              data[i] = targetBiomeId;
            }
            dm.rawEntries[b64_3D] = data;
            count++;
          }
        }

        // 修改 2D 群系 (Tag 45)
        final key2D = ParsedChunkKey.buildKey(cx, cz, targetDim, ChunkTag.data2D);
        final b64_2D = base64Encode(key2D);
        if (dm.rawEntries.containsKey(b64_2D)) {
          final data = Uint8List.fromList(dm.rawEntries[b64_2D]!);
          if (data.length >= 512 + 256) {
            for (int i = 512; i < 512 + 256; i++) {
              data[i] = targetBiomeId;
            }
            dm.rawEntries[b64_2D] = data;
            count++;
          }
        }

        ChunkCacheManager().clearChunk(cx, cz, targetDim);
      }
    }

    ChunkCacheManager().clearAll();
    dm.notifyDataChanged();

    return count;
  }
}
