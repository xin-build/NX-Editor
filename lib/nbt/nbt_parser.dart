import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'nbt_tags.dart';

/// 纯 Dart 实现的 Minecraft 基岩版小端 NBT 解析器
class LittleEndianNbtParser {
  ByteData _data = ByteData(0);
  int _offset = 0;
  int _bytesRead = 0;

  LittleEndianNbtParser([Uint8List? bytes]) {
    if (bytes != null) {
      _data = ByteData.sublistView(bytes);
    }
  }

  int get offset => _offset;
  int get bytesRead => _bytesRead;

  int _readByte() => _data.getInt8(_offset++);
  int _readUnsignedByte() => _data.getUint8(_offset++);

  int _readShort() {
    int val = _data.getInt16(_offset, Endian.little);
    _offset += 2;
    return val;
  }

  int _readInt() {
    int val = _data.getInt32(_offset, Endian.little);
    _offset += 4;
    return val;
  }

  int _readLong() {
    int val = _data.getInt64(_offset, Endian.little);
    _offset += 8;
    return val;
  }

  double _readFloat() {
    double val = _data.getFloat32(_offset, Endian.little);
    _offset += 4;
    return val;
  }

  double _readDouble() {
    double val = _data.getFloat64(_offset, Endian.little);
    _offset += 8;
    return val;
  }

  String _readString() {
    int len = _data.getUint16(_offset, Endian.little);
    _offset += 2;
    if (len == 0) return '';
    Uint8List bytes = Uint8List.view(
      _data.buffer,
      _data.offsetInBytes + _offset,
      len,
    );
    _offset += len;
    return utf8.decode(bytes, allowMalformed: true);
  }

  NbtTag parseTag(int type) {
    switch (type) {
      case NbtTagType.end:
        return NbtEnd();
      case NbtTagType.byte:
        return NbtByte(_readByte());
      case NbtTagType.short:
        return NbtShort(_readShort());
      case NbtTagType.intValue:
        return NbtInt(_readInt());
      case NbtTagType.long:
        return NbtLong(_readLong());
      case NbtTagType.float:
        return NbtFloat(_readFloat());
      case NbtTagType.double:
        return NbtDouble(_readDouble());
      case NbtTagType.byteArray:
        int len = _readInt();
        Uint8List bytes = Uint8List.view(
          _data.buffer,
          _data.offsetInBytes + _offset,
          len,
        );
        _offset += len;
        return NbtByteArray(Uint8List.fromList(bytes));
      case NbtTagType.string:
        return NbtString(_readString());
      case NbtTagType.list:
        int elemType = _readByte();
        int len = _readInt();
        List<NbtTag> list = [];
        for (int i = 0; i < len; i++) {
          list.add(parseTag(elemType));
        }
        return NbtList(elemType, list);
      case NbtTagType.compound:
        Map<String, NbtTag> map = {};
        while (_offset < _data.lengthInBytes) {
          int subType = _readUnsignedByte();
          if (subType == NbtTagType.end) break;
          String name = _readString();
          map[name] = parseTag(subType);
        }
        return NbtCompound(map);
      case NbtTagType.intArray:
        int len = _readInt();
        Int32List list = Int32List(len);
        for (int i = 0; i < len; i++) {
          list[i] = _readInt();
        }
        return NbtIntArray(list);
      case NbtTagType.longArray:
        int len = _readInt();
        Int64List list = Int64List(len);
        for (int i = 0; i < len; i++) {
          list[i] = _readLong();
        }
        return NbtLongArray(list);
      case NbtTagType.shortArray:
        int len = _readInt();
        List<int> shorts = [];
        for (int i = 0; i < len; i++) {
          shorts.add(_readShort());
        }
        return NbtShortArray(shorts);
      default:
        throw FormatException('未知的 NBT 标签类型: $type');
    }
  }

  /// 从指定 buffer 解析单个 Tag，并记录读取字节数
  NbtTag parseFromBuffer(Uint8List buffer) {
    _data = ByteData.sublistView(buffer);
    _offset = 0;
    if (buffer.isEmpty) return NbtEnd();

    int type = _readUnsignedByte();
    if (type == NbtTagType.end) {
      _bytesRead = 1;
      return NbtEnd();
    }
    // 读取名称
    _readString();
    final tag = parseTag(type);
    _bytesRead = _offset;
    return tag;
  }

  /// 解析完整的 NBT 树，返回根 Compound 及其名称
  MapEntry<String, NbtCompound> parse([Uint8List? bytes]) {
    if (bytes != null) {
      _data = ByteData.sublistView(bytes);
    }
    _offset = 0;
    if (_data.lengthInBytes == 0) {
      return MapEntry('', NbtCompound({}));
    }

    int rootType = _readUnsignedByte();
    if (rootType == NbtTagType.end) {
      return MapEntry('', NbtCompound({}));
    }
    if (rootType != NbtTagType.compound) {
      throw FormatException('NBT 根节点必须是 Compound 类型: type=$rootType');
    }
    String rootName = _readString();
    NbtCompound root = parseTag(rootType) as NbtCompound;
    _bytesRead = _offset;
    return MapEntry(rootName, root);
  }

  /// 解析 level.dat (自动处理 Bedrock 8 字节 Header 与 GZIP 兼容)
  NbtCompound parseLevelDat(Uint8List bytes) {
    Uint8List rawNbt = bytes;

    // 检查是否为 GZIP 压缩 (Java 或旧版)
    if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      try {
        final gzip = GZipCodec();
        rawNbt = Uint8List.fromList(gzip.decode(bytes));
      } catch (_) {}
    } else if (bytes.length >= 8) {
      // 检查 Bedrock 8 字节 Header: [version (4B)][payload_len (4B)]
      final bd = ByteData.sublistView(bytes);
      final headerVer = bd.getInt32(0, Endian.little);
      final payloadLen = bd.getInt32(4, Endian.little);

      if ((headerVer >= 1 && headerVer <= 20) && payloadLen == bytes.length - 8) {
        rawNbt = bytes.sublist(8);
      }
    }

    return parse(rawNbt).value;
  }

  /// 智能解析任意来源的 NBT 数据 (支持 GZIP/ZLIB 压缩、Bedrock 8字节 Header、以及标准未压缩小端 NBT)
  static MapEntry<String, NbtCompound> parseAnyNbt(Uint8List bytes) {
    Uint8List rawNbt = bytes;

    // 1. 检查 GZIP 魔法头 (0x1F, 0x8B)
    if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      try {
        final gzip = GZipCodec();
        rawNbt = Uint8List.fromList(gzip.decode(bytes));
      } catch (_) {}
    }
    // 2. 检查 ZLIB 魔法头 (0x78)
    else if (bytes.length >= 2 && bytes[0] == 0x78) {
      try {
        final zlibCodec = ZLibCodec();
        rawNbt = Uint8List.fromList(zlibCodec.decode(bytes));
      } catch (_) {}
    }
    // 3. 检查 Bedrock 8 字节 Header
    else if (bytes.length >= 8) {
      final bd = ByteData.sublistView(bytes);
      final headerVer = bd.getInt32(0, Endian.little);
      final payloadLen = bd.getInt32(4, Endian.little);
      if ((headerVer >= 1 && headerVer <= 20) && payloadLen == bytes.length - 8) {
        rawNbt = bytes.sublist(8);
      }
    }

    final parser = LittleEndianNbtParser();
    return parser.parse(rawNbt);
  }
}

/// 纯 Dart 实现的 Minecraft 基岩版小端 NBT 序列化器
class LittleEndianNbtWriter {
  final List<int> _bytes = [];

  Uint8List toBytes() => Uint8List.fromList(_bytes);

  void _writeByte(int val) => _bytes.add(val & 0xFF);

  void _writeShort(int val) {
    _bytes.add(val & 0xFF);
    _bytes.add((val >> 8) & 0xFF);
  }

  void _writeInt(int val) {
    _bytes.add(val & 0xFF);
    _bytes.add((val >> 8) & 0xFF);
    _bytes.add((val >> 16) & 0xFF);
    _bytes.add((val >> 24) & 0xFF);
  }

  void _writeLong(int val) {
    _bytes.add(val & 0xFF);
    _bytes.add((val >> 8) & 0xFF);
    _bytes.add((val >> 16) & 0xFF);
    _bytes.add((val >> 24) & 0xFF);
    _bytes.add((val >> 32) & 0xFF);
    _bytes.add((val >> 40) & 0xFF);
    _bytes.add((val >> 48) & 0xFF);
    _bytes.add((val >> 56) & 0xFF);
  }

  void _writeFloat(double val) {
    ByteData bd = ByteData(4);
    bd.setFloat32(0, val, Endian.little);
    _bytes.addAll(bd.buffer.asUint8List());
  }

  void _writeDouble(double val) {
    ByteData bd = ByteData(8);
    bd.setFloat64(0, val, Endian.little);
    _bytes.addAll(bd.buffer.asUint8List());
  }

  void _writeString(String val) {
    Uint8List utf8Bytes = utf8.encode(val);
    _writeShort(utf8Bytes.length);
    _bytes.addAll(utf8Bytes);
  }

  void writeTag(NbtTag tag) {
    switch (tag.type) {
      case NbtTagType.end:
        break;
      case NbtTagType.byte:
        _writeByte((tag as NbtByte).value);
        break;
      case NbtTagType.short:
        _writeShort((tag as NbtShort).value);
        break;
      case NbtTagType.intValue:
        _writeInt((tag as NbtInt).value);
        break;
      case NbtTagType.long:
        _writeLong((tag as NbtLong).value);
        break;
      case NbtTagType.float:
        _writeFloat((tag as NbtFloat).value);
        break;
      case NbtTagType.double:
        _writeDouble((tag as NbtDouble).value);
        break;
      case NbtTagType.byteArray:
        Uint8List arr = (tag as NbtByteArray).value;
        _writeInt(arr.length);
        _bytes.addAll(arr);
        break;
      case NbtTagType.string:
        _writeString((tag as NbtString).value);
        break;
      case NbtTagType.list:
        NbtList list = tag as NbtList;
        _writeByte(list.elementType);
        _writeInt(list.value.length);
        for (var item in list.value) {
          writeTag(item);
        }
        break;
      case NbtTagType.compound:
        NbtCompound comp = tag as NbtCompound;
        comp.value.forEach((name, subTag) {
          _writeByte(subTag.type);
          _writeString(name);
          writeTag(subTag);
        });
        _writeByte(NbtTagType.end);
        break;
      case NbtTagType.intArray:
        Int32List arr = (tag as NbtIntArray).value;
        _writeInt(arr.length);
        for (int val in arr) {
          _writeInt(val);
        }
        break;
      case NbtTagType.longArray:
        Int64List arr = (tag as NbtLongArray).value;
        _writeInt(arr.length);
        for (int val in arr) {
          _writeLong(val);
        }
        break;
      case NbtTagType.shortArray:
        final shorts = (tag as NbtShortArray).value;
        _writeInt(shorts.length);
        for (int val in shorts) {
          _writeShort(val);
        }
        break;
    }
  }

  /// 序列化 NBT 树
  Uint8List writeRoot(String rootName, NbtCompound root) {
    _bytes.clear();
    _writeByte(NbtTagType.compound);
    _writeString(rootName);
    writeTag(root);
    return toBytes();
  }

  /// 序列化 level.dat (包含 8 字节 Bedrock Header)
  Uint8List writeLevelDat(NbtCompound root, {int headerVersion = 8}) {
    final rawNbt = writeRoot('', root);
    final result = BytesBuilder();

    // 8 字节 Header
    final header = Uint8List(8);
    final bd = ByteData.sublistView(header);
    bd.setInt32(0, headerVersion, Endian.little);
    bd.setInt32(4, rawNbt.length, Endian.little);

    result.add(header);
    result.add(rawNbt);
    return result.toBytes();
  }
}
