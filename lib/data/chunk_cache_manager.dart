import 'dart:typed_data';
import 'dart:ui' as ui;
import '../models/app_settings.dart';

/// GPU 纹理瓦片对象
class GpuChunkTile {
  final int chunkX;
  final int chunkZ;
  final int dimension;
  final MapLayerMode layerMode;
  final ui.Image gpuImage;
  final int lastAccessed;

  GpuChunkTile({
    required this.chunkX,
    required this.chunkZ,
    required this.dimension,
    required this.layerMode,
    required this.gpuImage,
    required this.lastAccessed,
  });

  void dispose() {
    gpuImage.dispose();
  }
}

/// 瓦片与数据多级缓存管理器 (LRU 内存与 GPU 显存管理)
class ChunkCacheManager {
  static final ChunkCacheManager _instance = ChunkCacheManager._internal();
  factory ChunkCacheManager() => _instance;
  ChunkCacheManager._internal();

  // 1. GPU 纹理缓存 (Key: "dim:layer:cx,cz" -> GpuChunkTile)
  final Map<String, GpuChunkTile> _gpuTileCache = {};

  // 2. 解析后的子区块方块 ID 缓存 ("cx,cz,subY" -> 4096 / 256 list)
  final Map<String, List<String>> _subChunkBlockCache = {};

  // 3. 高度图与表面缓存 ("dim:cx,cz" -> 256 heights)
  final Map<String, Uint16List> _heightCache = {};

  // 4. 生态群系缓存 ("dim:cx,cz" -> 256 biomes)
  final Map<String, Uint8List> _biomeCache = {};

  void clearAll() {
    for (final tile in _gpuTileCache.values) {
      tile.dispose();
    }
    _gpuTileCache.clear();
    _subChunkBlockCache.clear();
    _heightCache.clear();
    _biomeCache.clear();
  }

  void clearChunk(int cx, int cz, [int? dim]) {
    if (dim != null) {
      invalidateRegion(cx, cx, cz, cz, dim);
    } else {
      invalidateRegion(cx, cx, cz, cz, 0);
      invalidateRegion(cx, cx, cz, cz, 1);
      invalidateRegion(cx, cx, cz, cz, 2);
    }
    _subChunkBlockCache.removeWhere((k, _) => k.startsWith('$cx,$cz,'));
  }

  void invalidateRegion(int minCx, int maxCx, int minCz, int maxCz, int dim) {
    final keysToRemove = <String>[];
    for (final k in _gpuTileCache.keys) {
      if (k.startsWith('$dim:')) {
        final parts = k.split(':');
        if (parts.length >= 3) {
          final coords = parts[2].split(',');
          if (coords.length == 2) {
            final cx = int.tryParse(coords[0]) ?? 0;
            final cz = int.tryParse(coords[1]) ?? 0;
            if (cx >= minCx && cx <= maxCx && cz >= minCz && cz <= maxCz) {
              keysToRemove.add(k);
            }
          }
        }
      }
    }
    for (final k in keysToRemove) {
      _gpuTileCache[k]?.dispose();
      _gpuTileCache.remove(k);
    }
  }

  GpuChunkTile? getGpuTile(int cx, int cz, int dim, MapLayerMode layer) {
    final key = '$dim:${layer.name}:$cx,$cz';
    return _gpuTileCache[key];
  }

  void putGpuTile(int cx, int cz, int dim, MapLayerMode layer, ui.Image image) {
    final key = '$dim:${layer.name}:$cx,$cz';

    // 检查容量并执行 LRU 淘汰
    final maxCapacity = AppSettings().maxCachedTiles;
    if (_gpuTileCache.length >= maxCapacity) {
      final sorted = _gpuTileCache.entries.toList()
        ..sort((a, b) => a.value.lastAccessed.compareTo(b.value.lastAccessed));
      // 淘汰最久未访问的 20%
      final evictCount = (maxCapacity * 0.2).ceil();
      for (int i = 0; i < evictCount && i < sorted.length; i++) {
        final evictKey = sorted[i].key;
        _gpuTileCache[evictKey]?.dispose();
        _gpuTileCache.remove(evictKey);
      }
    }

    _gpuTileCache[key]?.dispose();
    _gpuTileCache[key] = GpuChunkTile(
      chunkX: cx,
      chunkZ: cz,
      dimension: dim,
      layerMode: layer,
      gpuImage: image,
      lastAccessed: DateTime.now().millisecondsSinceEpoch,
    );
  }

  List<String>? getSubChunkBlocks(int cx, int cz, int subY) {
    return _subChunkBlockCache['$cx,$cz,$subY'];
  }

  void putSubChunkBlocks(int cx, int cz, int subY, List<String> blocks) {
    _subChunkBlockCache['$cx,$cz,$subY'] = blocks;
  }
}
