import 'dart:io';
import 'dart:typed_data';

/// 纯 Dart 实现的 LevelDB SSTable (.ldb) 读取器
/// 支持 Mojang 特有的 ZLIB_RAW 压缩格式
class BELevelDBReader {
  final Uint8List _data;

  BELevelDBReader(this._data);

  /// 读取变长整数 (Varint)
  MapEntry<int, int> _readVarint(Uint8List buf, int offset) {
    int x = 0;
    int s = 0;
    int off = offset;
    while (true) {
      int b = buf[off++];
      x |= (b & 0x7F) << s;
      if ((b & 0x80) == 0) {
        return MapEntry(x, off);
      }
      s += 7;
    }
  }

  /// 解析 Block 记录 (BlockIterator)
  List<MapEntry<Uint8List, Uint8List>> _parseBlock(Uint8List block) {
    if (block.length < 4) return [];

    // block 末尾：restart_count (4字节小端)
    final bd = ByteData.sublistView(block);
    final restartCount = bd.getUint32(block.length - 4, Endian.little);
    final restartsOffset = block.length - 4 - restartCount * 4;

    int off = 0;
    Uint8List prevKey = Uint8List(0);
    final List<MapEntry<Uint8List, Uint8List>> entries = [];

    while (off < restartsOffset) {
      final sharedRes = _readVarint(block, off);
      final shared = sharedRes.key;
      off = sharedRes.value;

      final nonSharedRes = _readVarint(block, off);
      final nonShared = nonSharedRes.key;
      off = nonSharedRes.value;

      final valueLenRes = _readVarint(block, off);
      final valueLen = valueLenRes.key;
      off = valueLenRes.value;

      // 拼接 Key
      final key = Uint8List(shared + nonShared);
      if (shared > 0) {
        key.setRange(0, shared, prevKey);
      }
      key.setRange(
        shared,
        shared + nonShared,
        block.sublist(off, off + nonShared),
      );
      off += nonShared;

      final val = block.sublist(off, off + valueLen);
      off += valueLen;

      entries.add(MapEntry(key, val));
      prevKey = key;
    }
    return entries;
  }

  /// 读取并解压 Block
  Uint8List _readBlock(int offset, int size) {
    final raw = _data.sublist(offset, offset + size);
    final trailer = _data.sublist(offset + size, offset + size + 5);
    final ctype = trailer[0];

    if (ctype == 0) {
      // NONE — 无需解压
      return raw;
    } else if (ctype == 2) {
      // ZLIB — 标准 ZLIB 格式（带 2 字节头）
      final codec = ZLibCodec(raw: false);
      return Uint8List.fromList(codec.decode(raw.toList()));
    } else if (ctype == 4) {
      // ZLIB_RAW — Mojang 特有，使用 raw inflate（无 ZLIB 头，等效 windowBits=-15）
      // Java 原版: Inflater(true) → nowrap 模式
      final codec = ZLibCodec(raw: true);
      return Uint8List.fromList(codec.decode(raw.toList()));
    } else {
      throw FormatException('不支持的压缩类型: ctype=$ctype');
    }
  }

  /// 读取并解析所有用户键值对
  Map<Uint8List, Uint8List> readAllEntries() {
    if (_data.length < 48) {
      throw FormatException('文件长度不足，无法读取 Footer');
    }

    final footer = _data.sublist(_data.length - 48);

    // 验证 Magic Number (最后 8 字节)
    final footerBd = ByteData.sublistView(footer);
    final magicLow = footerBd.getUint32(40, Endian.little);
    final magicHigh = footerBd.getUint32(44, Endian.little);
    // Magic: 0xdb4775248b80fb57
    if (magicLow != 0x8b80fb57 || magicHigh != 0xdb477524) {
      throw FormatException('无效的 LevelDB Magic Number');
    }

    // Footer 包含 meta_index_handle 和 index_handle
    var p = 0;
    var res = _readVarint(footer, p); // skip meta_index_offset
    p = res.value;
    res = _readVarint(footer, p); // skip meta_index_size
    p = res.value;

    res = _readVarint(footer, p);
    final indexOffset = res.key;
    p = res.value;

    res = _readVarint(footer, p);
    final indexSize = res.key;

    // 1. 读取并解析 Index Block
    final indexBlock = _readBlock(indexOffset, indexSize);
    final indexEntries = _parseBlock(indexBlock);

    final Map<Uint8List, Uint8List> userMap = {};

    // 2. 遍历 Index Entries，读取实际数据块
    for (final entry in indexEntries) {
      final handle = entry.value;
      var hp = 0;
      final offRes = _readVarint(handle, hp);
      final blockOffset = offRes.key;
      hp = offRes.value;

      final sizeRes = _readVarint(handle, hp);
      final blockSize = sizeRes.key;

      final dataBlock = _readBlock(blockOffset, blockSize);
      final dataEntries = _parseBlock(dataBlock);

      for (final dataEntry in dataEntries) {
        final fullKey = dataEntry.key;
        final value = dataEntry.value;

        // 去掉 LevelDB 内部的 8 字节 Trailer (Sequence Number + Value Type)
        if (fullKey.length >= 8) {
          final userKey = fullKey.sublist(0, fullKey.length - 8);
          userMap[userKey] = value;
        }
      }
    }

    return userMap;
  }
}
