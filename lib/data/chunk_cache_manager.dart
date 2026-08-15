import 'dart:typed_data';
import 'dart:ui' as ui;
import '../models/app_settings.dart';

/// GPU Region 区域大单面瓦片对象 (1 Region = 16×16 区块 = 256×256 像素)
class GpuRegionTile {
  final int regionX;
  final int regionZ;
  final int dimension;
  final MapLayerMode layerMode;
  final ui.Image gpuImage;
  final int lastAccessed;
  final int loadedTimestamp;

  GpuRegionTile({
    required this.regionX,
    required this.regionZ,
    required this.dimension,
    required this.layerMode,
    required this.gpuImage,
    required this.lastAccessed,
    required this.loadedTimestamp,
  });

  void dispose() {
    gpuImage.dispose();
  }
}

/// 瓦片与数据多级缓存管理器 (Region 大单面与 GPU 显存管理)
class ChunkCacheManager {
  static final ChunkCacheManager _instance = ChunkCacheManager._internal();
  factory ChunkCacheManager() => _instance;
  ChunkCacheManager._internal();

  // 1. GPU Region 大单面纹理缓存 (Key: "dim:layer:rx,rz" -> GpuRegionTile)
  final Map<String, GpuRegionTile> _gpuRegionCache = {};

  // 2. 解析后的子区块方块 ID 缓存 ("cx,cz,subY" -> 4096 / 256 list)
  final Map<String, List<String>> _subChunkBlockCache = {};

  // 3. 高度图与表面缓存 ("dim:cx,cz" -> 256 heights)
  final Map<String, Uint16List> _heightCache = {};

  // 4. 生态群系缓存 ("dim:cx,cz" -> 256 biomes)
  final Map<String, Uint8List> _biomeCache = {};

  void clearAll() {
    for (final tile in _gpuRegionCache.values) {
      tile.dispose();
    }
    _gpuRegionCache.clear();
    _subChunkBlockCache.clear();
    _heightCache.clear();
    _biomeCache.clear();
  }

  void clearChunk(int cx, int cz, [int? dim]) {
    final rx = (cx / 16.0).floor();
    final rz = (cz / 16.0).floor();
    if (dim != null) {
      invalidateRegionTile(rx, rz, dim);
    } else {
      invalidateRegionTile(rx, rz, 0);
      invalidateRegionTile(rx, rz, 1);
      invalidateRegionTile(rx, rz, 2);
    }
    _subChunkBlockCache.removeWhere((k, _) => k.startsWith('$cx,$cz,'));
  }

  void invalidateRegionTile(int rx, int rz, int dim) {
    final prefix = '$dim:';
    final suffix = ':$rx,$rz';
    final keysToRemove = <String>[];
    for (final k in _gpuRegionCache.keys) {
      if (k.startsWith(prefix) && k.endsWith(suffix)) {
        keysToRemove.add(k);
      }
    }
    for (final k in keysToRemove) {
      _gpuRegionCache[k]?.dispose();
      _gpuRegionCache.remove(k);
    }
  }

  void invalidateRegion(int minCx, int maxCx, int minCz, int maxCz, int dim) {
    final minRx = (minCx / 16.0).floor();
    final maxRx = (maxCx / 16.0).floor();
    final minRz = (minCz / 16.0).floor();
    final maxRz = (maxCz / 16.0).floor();

    for (int rx = minRx; rx <= maxRx; rx++) {
      for (int rz = minRz; rz <= maxRz; rz++) {
        invalidateRegionTile(rx, rz, dim);
      }
    }
  }

  GpuRegionTile? getGpuRegionTile(int rx, int rz, int dim, MapLayerMode layer) {
    final key = '$dim:${layer.name}:$rx,$rz';
    return _gpuRegionCache[key];
  }

  void putGpuRegionTile(int rx, int rz, int dim, MapLayerMode layer, ui.Image image) {
    final key = '$dim:${layer.name}:$rx,$rz';

    // 检查容量并执行 LRU 淘汰 (每个 Region 覆盖 256 区块，保留 300 个 Region 可覆盖 76,800 个区块)
    const maxCapacity = 300;
    if (_gpuRegionCache.length >= maxCapacity) {
      final sorted = _gpuRegionCache.entries.toList()
        ..sort((a, b) => a.value.lastAccessed.compareTo(b.value.lastAccessed));
      final evictCount = (maxCapacity * 0.2).ceil();
      for (int i = 0; i < evictCount && i < sorted.length; i++) {
        final evictKey = sorted[i].key;
        _gpuRegionCache[evictKey]?.dispose();
        _gpuRegionCache.remove(evictKey);
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    _gpuRegionCache[key]?.dispose();
    _gpuRegionCache[key] = GpuRegionTile(
      regionX: rx,
      regionZ: rz,
      dimension: dim,
      layerMode: layer,
      gpuImage: image,
      lastAccessed: now,
      loadedTimestamp: now,
    );
  }

  List<String>? getSubChunkBlocks(int cx, int cz, int subY) {
    return _subChunkBlockCache['$cx,$cz,$subY'];
  }

  void putSubChunkBlocks(int cx, int cz, int subY, List<String> blocks) {
    _subChunkBlockCache['$cx,$cz,$subY'] = blocks;
  }
}
