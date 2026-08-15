import 'dart:math';

/// 选区模型 (支持负数坐标、平移与区块追加)
class SelectionModel {
  int minX;
  int maxX;
  int minY;
  int maxY;
  int minZ;
  int maxZ;
  int dimension;

  SelectionModel({
    this.minX = 0,
    this.maxX = 15,
    this.minY = -64,
    this.maxY = 320,
    this.minZ = 0,
    this.maxZ = 15,
    this.dimension = 0,
  });

  int get normMinX => min(minX, maxX);
  int get normMaxX => max(minX, maxX);
  int get normMinY => min(minY, maxY);
  int get normMaxY => max(minY, maxY);
  int get normMinZ => min(minZ, maxZ);
  int get normMaxZ => max(minZ, maxZ);

  int get sizeX => (maxX - minX).abs() + 1;
  int get sizeY => (maxY - minY).abs() + 1;
  int get sizeZ => (maxZ - minZ).abs() + 1;
  int get totalBlocks => sizeX * sizeY * sizeZ;

  int get minChunkX => (normMinX / 16).floor();
  int get maxChunkX => (normMaxX / 16).floor();
  int get minChunkZ => (normMinZ / 16).floor();
  int get maxChunkZ => (normMaxZ / 16).floor();

  int get chunkCountX => (maxChunkX - minChunkX) + 1;
  int get chunkCountZ => (maxChunkZ - minChunkZ) + 1;
  int get totalChunks => chunkCountX * chunkCountZ;

  bool get isChunkAligned =>
      (minX & 0xF) == 0 && ((maxX + 1) & 0xF) == 0 &&
      (minZ & 0xF) == 0 && ((maxZ + 1) & 0xF) == 0;

  void alignToChunks() {
    final startX = (normMinX / 16).floor() * 16;
    final endX = ((normMaxX / 16).floor() + 1) * 16 - 1;
    final startZ = (normMinZ / 16).floor() * 16;
    final endZ = ((normMaxZ / 16).floor() + 1) * 16 - 1;
    minX = startX;
    maxX = endX;
    minZ = startZ;
    maxZ = endZ;
  }

  /// 平移选区 (Alt + Drag 移动选区)
  void translate(int dx, int dz) {
    minX += dx;
    maxX += dx;
    minZ += dz;
    maxZ += dz;
  }

  /// 追加区块到选区 (Ctrl 多选)
  void addChunk(int cx, int cz) {
    final cMinX = cx * 16;
    final cMaxX = cx * 16 + 15;
    final cMinZ = cz * 16;
    final cMaxZ = cz * 16 + 15;
    minX = min(minX, cMinX);
    maxX = max(maxX, cMaxX);
    minZ = min(minZ, cMinZ);
    maxZ = max(maxZ, cMaxZ);
  }

  bool containsBlock(int x, int y, int z) {
    final sMinX = normMinX;
    final sMaxX = normMaxX;
    final sMinY = normMinY;
    final sMaxY = normMaxY;
    final sMinZ = normMinZ;
    final sMaxZ = normMaxZ;
    return x >= sMinX && x <= sMaxX && y >= sMinY && y <= sMaxY && z >= sMinZ && z <= sMaxZ;
  }

  bool containsChunk(int cx, int cz) {
    return cx >= minChunkX && cx <= maxChunkX && cz >= minChunkZ && cz <= maxChunkZ;
  }

  SelectionModel clone() {
    return SelectionModel(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      minZ: minZ,
      maxZ: maxZ,
      dimension: dimension,
    );
  }
}
