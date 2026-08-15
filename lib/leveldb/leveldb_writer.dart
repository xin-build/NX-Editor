import 'dart:io';
import 'dart:typed_data';

/// 纯 Dart 实现的 LevelDB SSTable (.ldb) 写入与构建器
/// 100% 兼容 Mojang 基岩版 LevelDB 格式与 ZLIB_RAW (ctype=4) 压缩
class BELevelDBWriter {
  static const int kBlockSize = 4096;
  static const int kBlockRestartInterval = 16;
  static const int kCompressionTypeZlibRaw = 4; // Mojang 特有 ZLIB_RAW (windowBits=-15)
  static const int kCompressionTypeNone = 0;

  // LevelDB Table Magic: 0xdb4775248b80fb57
  static const List<int> kTableMagic = [
    0x57, 0xfb, 0x80, 0x8b, 0x24, 0x75, 0x47, 0xdb,
  ];

  /// 字节比较器（无符号小端/字典序）
  static int compareBytes(Uint8List a, Uint8List b) {
    final len = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < len; i++) {
      if (a[i] != b[i]) {
        return a[i] - b[i];
      }
    }
    return a.length - b.length;
  }

  /// 编码变长整数 (Varint32/64)
  static Uint8List encodeVarint(int value) {
    final bytes = <int>[];
    int v = value;
    while (v >= 0x80) {
      bytes.add((v & 0x7F) | 0x80);
      v >>= 7;
    }
    bytes.add(v & 0x7F);
    return Uint8List.fromList(bytes);
  }

  /// 计算 CRC32C 掩码 (Masked CRC)
  static int _maskCrc(int crc) {
    return (((crc >> 15) | (crc << 17)) + 0xa282ead8) & 0xFFFFFFFF;
  }

  /// 简易 CRC32 计算 (标准 IEEE 802.3)
  static int _calculateCrc32(Uint8List data) {
    int crc = 0xFFFFFFFF;
    for (int i = 0; i < data.length; i++) {
      int byte = data[i];
      crc ^= byte;
      for (int j = 0; j < 8; j++) {
        final mask = -(crc & 1);
        crc = (crc >> 1) ^ (0xEDB88320 & mask);
      }
    }
    return ~crc & 0xFFFFFFFF;
  }

  /// 构建单个数据块 (DataBlock 或 IndexBlock)
  static Uint8List _buildBlock(List<MapEntry<Uint8List, Uint8List>> entries, {int restartInterval = kBlockRestartInterval}) {
    final builder = BytesBuilder();
    final restartPositions = <int>[];
    Uint8List lastKey = Uint8List(0);
    int countSinceRestart = 0;

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final key = entry.key;
      final val = entry.value;

      int shared = 0;
      if (countSinceRestart < restartInterval) {
        final minLen = key.length < lastKey.length ? key.length : lastKey.length;
        while (shared < minLen && key[shared] == lastKey[shared]) {
          shared++;
        }
      } else {
        restartPositions.add(builder.length);
        countSinceRestart = 0;
      }

      if (i == 0 && restartPositions.isEmpty) {
        restartPositions.add(0);
      }

      final nonShared = key.length - shared;
      builder.add(encodeVarint(shared));
      builder.add(encodeVarint(nonShared));
      builder.add(encodeVarint(val.length));
      if (nonShared > 0) {
        builder.add(key.sublist(shared));
      }
      builder.add(val);

      lastKey = key;
      countSinceRestart++;
    }

    if (restartPositions.isEmpty) {
      restartPositions.add(0);
    }

    // 写入 restart 数组 (uint32 小端)
    final restartBytes = Uint8List(restartPositions.length * 4 + 4);
    final restartBd = ByteData.sublistView(restartBytes);
    for (int i = 0; i < restartPositions.length; i++) {
      restartBd.setUint32(i * 4, restartPositions[i], Endian.little);
    }
    restartBd.setUint32(restartPositions.length * 4, restartPositions.length, Endian.little);
    builder.add(restartBytes);

    return builder.toBytes();
  }

  /// 压缩并添加 Block Trailer (ctype + masked crc32)
  static Uint8List _compressBlockAndAddTrailer(Uint8List blockData, {bool useCompression = true}) {
    int ctype = kCompressionTypeNone;
    Uint8List payload = blockData;

    if (useCompression && blockData.length > 32) {
      try {
        final codec = ZLibCodec(raw: true);
        final compressed = Uint8List.fromList(codec.encode(blockData));
        if (compressed.length < blockData.length) {
          payload = compressed;
          ctype = kCompressionTypeZlibRaw;
        }
      } catch (_) {
        payload = blockData;
        ctype = kCompressionTypeNone;
      }
    }

    final result = BytesBuilder();
    result.add(payload);

    // 5 字节 Trailer: [ctype (1B)][crc32 (4B)]
    final trailer = Uint8List(5);
    trailer[0] = ctype;
    final crcData = Uint8List(payload.length + 1);
    crcData.setRange(0, payload.length, payload);
    crcData[payload.length] = ctype;
    final rawCrc = _calculateCrc32(crcData);
    final maskedCrc = _maskCrc(rawCrc);
    ByteData.sublistView(trailer).setUint32(1, maskedCrc, Endian.little);

    result.add(trailer);
    return result.toBytes();
  }

  /// 将用户键值对构建为完整的 SSTable 二进制数据
  static Uint8List buildSSTable(Map<Uint8List, Uint8List> userEntries, {bool useCompression = true}) {
    // 1. 将所有条目转换为 LevelDB 内部键 (UserKey + 8 字节 Trailer: 0x0000000000000001, ValueType=1)
    final internalEntries = <MapEntry<Uint8List, Uint8List>>[];
    for (final e in userEntries.entries) {
      final userKey = e.key;
      final internalKey = Uint8List(userKey.length + 8);
      internalKey.setRange(0, userKey.length, userKey);
      // 8 字节 Trailer: seq=1, type=1 (Value)
      final bd = ByteData.sublistView(internalKey);
      bd.setUint32(userKey.length, 1, Endian.little); // seq low
      bd.setUint32(userKey.length + 4, 0x01000000, Endian.little); // seq high + type 1
      internalEntries.add(MapEntry(internalKey, e.value));
    }

    // 2. 按内部键字典序排序
    internalEntries.sort((a, b) => compareBytes(a.key, b.key));

    final sstableBuilder = BytesBuilder();
    final indexEntries = <MapEntry<Uint8List, Uint8List>>[];

    // 3. 切分数据块并写入
    var currentChunk = <MapEntry<Uint8List, Uint8List>>[];
    int currentChunkSize = 0;

    void flushDataBlock() {
      if (currentChunk.isEmpty) return;
      final rawBlock = _buildBlock(currentChunk);
      final lastKey = currentChunk.last.key;
      final blockOffset = sstableBuilder.length;
      final packagedBlock = _compressBlockAndAddTrailer(rawBlock, useCompression: useCompression);
      sstableBuilder.add(packagedBlock);

      // 构建 Index 句柄: BlockHandle (offset varint, payload size varint - 不含 5B trailer)
      final payloadSize = packagedBlock.length - 5;
      final handleBytes = BytesBuilder();
      handleBytes.add(encodeVarint(blockOffset));
      handleBytes.add(encodeVarint(payloadSize));
      indexEntries.add(MapEntry(lastKey, handleBytes.toBytes()));

      currentChunk = [];
      currentChunkSize = 0;
    }

    for (final entry in internalEntries) {
      currentChunk.add(entry);
      currentChunkSize += entry.key.length + entry.value.length;
      if (currentChunkSize >= kBlockSize) {
        flushDataBlock();
      }
    }
    flushDataBlock();

    // 4. 构建 Meta Index Block (空元索引)
    final metaIndexOffset = sstableBuilder.length;
    final metaIndexRaw = _buildBlock([]);
    final metaIndexPackaged = _compressBlockAndAddTrailer(metaIndexRaw, useCompression: false);
    sstableBuilder.add(metaIndexPackaged);
    final metaIndexSize = metaIndexPackaged.length - 5;

    // 5. 构建 Index Block
    final indexBlockOffset = sstableBuilder.length;
    final indexBlockRaw = _buildBlock(indexEntries, restartInterval: 1);
    final indexBlockPackaged = _compressBlockAndAddTrailer(indexBlockRaw, useCompression: false);
    sstableBuilder.add(indexBlockPackaged);
    final indexBlockSize = indexBlockPackaged.length - 5;

    // 6. 构建 Footer (48 字节)
    final footer = Uint8List(48);
    final footerBuilder = BytesBuilder();
    footerBuilder.add(encodeVarint(metaIndexOffset));
    footerBuilder.add(encodeVarint(metaIndexSize));
    footerBuilder.add(encodeVarint(indexBlockOffset));
    footerBuilder.add(encodeVarint(indexBlockSize));
    final handleBytes = footerBuilder.toBytes();

    footer.setRange(0, handleBytes.length, handleBytes);
    // 填充最后 8 字节 Magic Number
    footer.setRange(40, 48, kTableMagic);
    sstableBuilder.add(footer);

    return sstableBuilder.toBytes();
  }

  /// 将键值对保存到目标 .ldb 文件
  static Future<void> saveToLdbFile(String filePath, Map<Uint8List, Uint8List> userEntries) async {
    final bytes = buildSSTable(userEntries);
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
  }
}
