import 'dart:typed_data';

/// 基岩版区块键 Tag 定义
class ChunkTag {
  static const int data3D = 43; // 0x2b (3D 生物群系与高度图 1.18+)
  static const int versionLegacy = 44; // 0x2c
  static const int data2D = 45; // 0x2d (旧版 2D 生物群系与高度图 0.14 - 1.17)
  static const int data2DLegacy = 46; // 0x2e (旧版方块实体/群系)
  static const int subChunk = 47; // 0x2f (子区块方块数据 1.2+)
  static const int legacySubChunk = 48; // 0x30 (旧版子区块方块)
  static const int blockEntity = 49; // 0x31 (方块实体 NBT)
  static const int entity = 50; // 0x32 (旧版区块内实体 NBT 列表)
  static const int pendingTicks = 51; // 0x33
  static const int legacyBlockExtraData = 52; // 0x34
  static const int biomeState = 53; // 0x35
  static const int finalizedState = 54; // 0x36 (区块生成状态)
  static const int conversionData = 55; // 0x37
  static const int borderBlocks = 56; // 0x38
  static const int hardcodedSpawners = 57; // 0x39
  static const int randomTicks = 58; // 0x3a
  static const int checksums = 59; // 0x3b
  static const int version = 118; // 0x76 (区块存储版本)

  static bool isValidTag(int tag) {
    return (tag >= 43 && tag <= 59) || tag == 118;
  }
}

/// 区块键解析结果模型
class ParsedChunkKey {
  final int chunkX;
  final int chunkZ;
  final int dimension; // 0: 主世界, 1: 下界, 2: 末地
  final int tag;
  final int? subChunkY; // 仅子区块键 (Tag 47) 存在，有符号整数 (-4 到 19 等)
  final Uint8List rawKey;

  const ParsedChunkKey({
    required this.chunkX,
    required this.chunkZ,
    required this.dimension,
    required this.tag,
    this.subChunkY,
    required this.rawKey,
  });

  bool get isSubChunk => tag == ChunkTag.subChunk || tag == ChunkTag.legacySubChunk;
  bool get isTerrainOrHeight => tag == ChunkTag.data3D || tag == ChunkTag.data2D;
  bool get isBlockEntity => tag == ChunkTag.blockEntity;
  bool get isEntity => tag == ChunkTag.entity;

  /// 解析二进制 Key (包含严格的 Tag 与坐标有效性验证，避免元数据字符串误判)
  static ParsedChunkKey? parse(Uint8List key) {
    if (key.length < 8) return null;

    final bd = ByteData.sublistView(key);

    // 1. 检查 digp 开头 (digp[cx][cz] 或 digp[cx][cz][dim])
    if (key.length >= 12 && key[0] == 0x64 && key[1] == 0x69 && key[2] == 0x67 && key[3] == 0x70) {
      final cx = bd.getInt32(4, Endian.little);
      final cz = bd.getInt32(8, Endian.little);
      int dim = 0;
      if (key.length >= 16) {
        dim = bd.getInt32(12, Endian.little);
      }
      if (_isValidCoord(cx, cz) && (dim >= 0 && dim <= 2)) {
        return ParsedChunkKey(
          chunkX: cx,
          chunkZ: cz,
          dimension: dim,
          tag: ChunkTag.entity,
          rawKey: key,
        );
      }
      return null;
    }

    final cx = bd.getInt32(0, Endian.little);
    final cz = bd.getInt32(4, Endian.little);

    // 过滤掉非合理区块坐标 (避免 scoreboard 等 ASCII 字符串误判)
    if (!_isValidCoord(cx, cz)) return null;

    if (key.length == 8) {
      // 远古 8 字节键
      return ParsedChunkKey(
        chunkX: cx,
        chunkZ: cz,
        dimension: 0,
        tag: ChunkTag.data2D,
        rawKey: key,
      );
    } else if (key.length == 9) {
      // 主世界 9 字节键: [cx (4B)][cz (4B)][tag (1B)]
      final tag = key[8];
      if (!ChunkTag.isValidTag(tag)) return null;
      return ParsedChunkKey(
        chunkX: cx,
        chunkZ: cz,
        dimension: 0,
        tag: tag,
        rawKey: key,
      );
    } else if (key.length == 10) {
      // 主世界 10 字节子区块键: [cx (4B)][cz (4B)][tag (1B)][subY (1B 有符号补码)]
      final tag = key[8];
      if (tag != ChunkTag.subChunk && tag != ChunkTag.legacySubChunk) return null;
      final subY = bd.getInt8(9);
      if (subY < -16 || subY > 32) return null;
      return ParsedChunkKey(
        chunkX: cx,
        chunkZ: cz,
        dimension: 0,
        tag: tag,
        subChunkY: subY,
        rawKey: key,
      );
    } else if (key.length == 13) {
      // 其他维度 13 字节键: [cx (4B)][cz (4B)][dim (4B)][tag (1B)]
      final dim = bd.getInt32(8, Endian.little);
      final tag = key[12];
      if (dim < 0 || dim > 2 || !ChunkTag.isValidTag(tag)) return null;
      return ParsedChunkKey(
        chunkX: cx,
        chunkZ: cz,
        dimension: dim,
        tag: tag,
        rawKey: key,
      );
    } else if (key.length == 14) {
      // 其他维度 14 字节子区块键: [cx (4B)][cz (4B)][dim (4B)][tag (1B)][subY (1B)]
      final dim = bd.getInt32(8, Endian.little);
      final tag = key[12];
      final subY = bd.getInt8(13);
      if (dim < 1 || dim > 2 || (tag != ChunkTag.subChunk && tag != ChunkTag.legacySubChunk)) return null;
      if (subY < -16 || subY > 32) return null;
      return ParsedChunkKey(
        chunkX: cx,
        chunkZ: cz,
        dimension: dim,
        tag: tag,
        subChunkY: subY,
        rawKey: key,
      );
    }

    return null;
  }

  static bool _isValidCoord(int cx, int cz) {
    // Minecraft 有效区块范围在 ±1,875,000 以内 (±30,000,000 方块)
    return cx >= -1875000 && cx <= 1875000 && cz >= -1875000 && cz <= 1875000;
  }

  /// 构建区块键
  static Uint8List buildKey(int cx, int cz, int dimension, int tag, {int? subChunkY}) {
    if (dimension == 0) {
      if (subChunkY != null) {
        final data = Uint8List(10);
        final bd = ByteData.sublistView(data);
        bd.setInt32(0, cx, Endian.little);
        bd.setInt32(4, cz, Endian.little);
        data[8] = tag;
        bd.setInt8(9, subChunkY);
        return data;
      } else {
        final data = Uint8List(9);
        final bd = ByteData.sublistView(data);
        bd.setInt32(0, cx, Endian.little);
        bd.setInt32(4, cz, Endian.little);
        data[8] = tag;
        return data;
      }
    } else {
      if (subChunkY != null) {
        final data = Uint8List(14);
        final bd = ByteData.sublistView(data);
        bd.setInt32(0, cx, Endian.little);
        bd.setInt32(4, cz, Endian.little);
        bd.setInt32(8, dimension, Endian.little);
        data[12] = tag;
        bd.setInt8(13, subChunkY);
        return data;
      } else {
        final data = Uint8List(13);
        final bd = ByteData.sublistView(data);
        bd.setInt32(0, cx, Endian.little);
        bd.setInt32(4, cz, Endian.little);
        bd.setInt32(8, dimension, Endian.little);
        data[12] = tag;
        return data;
      }
    }
  }
}
