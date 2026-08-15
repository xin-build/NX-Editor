import 'dart:convert';
import 'dart:typed_data';

/// NBT 标签类型定义
class NbtTagType {
  static const int end = 0;
  static const int byte = 1;
  static const int short = 2;
  static const int intValue = 3; // 避免与 Dart 的 int 关键字冲突
  static const int long = 4;
  static const int float = 5;
  static const int double = 6;
  static const int byteArray = 7;
  static const int string = 8;
  static const int list = 9;
  static const int compound = 10;
  static const int intArray = 11;
  static const int longArray = 12;
  static const int shortArray = 100; // 原 APK 工具自定义扩展类型

  static String getTypeName(int type) {
    switch (type) {
      case end: return 'TAG_End';
      case byte: return 'TAG_Byte';
      case short: return 'TAG_Short';
      case intValue: return 'TAG_Int';
      case long: return 'TAG_Long';
      case float: return 'TAG_Float';
      case double: return 'TAG_Double';
      case byteArray: return 'TAG_Byte_Array';
      case string: return 'TAG_String';
      case list: return 'TAG_List';
      case compound: return 'TAG_Compound';
      case intArray: return 'TAG_Int_Array';
      case longArray: return 'TAG_Long_Array';
      case shortArray: return 'TAG_Short_Array';
      default: return 'TAG_Unknown($type)';
    }
  }

  static String getTypeChineseName(int type) {
    switch (type) {
      case byte: return 'Byte (1 字节整数 / 布尔)';
      case short: return 'Short (2 字节短整数)';
      case intValue: return 'Int (4 字节整数)';
      case long: return 'Long (8 字节长整数)';
      case float: return 'Float (单精度浮点数)';
      case double: return 'Double (双精度浮点数)';
      case byteArray: return 'Byte Array (字节数组)';
      case string: return 'String (文本字符串)';
      case list: return 'List (同类型标签列表)';
      case compound: return 'Compound (复合字典结构)';
      case intArray: return 'Int Array (整数数组)';
      case longArray: return 'Long Array (长整数数组)';
      case shortArray: return 'Short Array (短整数数组)';
      default: return '未知类型 ($type)';
    }
  }

  static String getTypeBadge(int type) {
    switch (type) {
      case byte: return 'B';
      case short: return 'S';
      case intValue: return 'I';
      case long: return 'L';
      case float: return 'F';
      case double: return 'D';
      case byteArray: return '[B]';
      case string: return 'STR';
      case list: return '[ ]';
      case compound: return '{ }';
      case intArray: return '[I]';
      case longArray: return '[L]';
      case shortArray: return '[S]';
      default: return '?';
    }
  }

  static String getTypeDescription(int type) {
    switch (type) {
      case byte: return '8 位有符号整数 (-128 ~ 127) 或布尔逻辑值 (0 为 false, 1 为 true)';
      case short: return '16 位有符号整数 (-32,768 ~ 32,767)，常用于物品 Damage、附魔 ID 等';
      case intValue: return '32 位有符号整数 (-2,147,483,648 ~ 2,147,483,647)，常用于实体坐标、计分板等';
      case long: return '64 位有符号大整数，常用于时间戳 (Time, DayTime)、UUID 等';
      case float: return '32 位 IEEE 754 单精度浮点数，常用于生物生命值 (Health)、移动速度等';
      case double: return '64 位 IEEE 754 双精度浮点数，常用于精准实体位置 Pos、Motion 等';
      case byteArray: return '8 位字节数组，常用于区块高度图、地图图像 Raw 像素等';
      case string: return 'UTF-8 编码文本字符串，用于名称、物品 ID、指令方块命令等';
      case list: return '包含若干相同类型子标签的有序列表 (如 Pos 列表、Enchantments 列表)';
      case compound: return '包含键值对子标签的复合字典树，是 Minecraft NBT 的最核心结构';
      case intArray: return '32 位整数数组，常用于实体 UUID (如 [I; 1, 2, 3, 4]) 等';
      case longArray: return '64 位长整数数组，常用于世界区块方块调色板压缩存储等';
      case shortArray: return '16 位短整数数组扩展类型';
      default: return '';
    }
  }
}

/// NBT 节点基类
abstract class NbtTag {
  int get type;
  dynamic get value;
  NbtTag clone();

  dynamic toJson();

  String toJsonString() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }
}

class NbtEnd extends NbtTag {
  @override
  int get type => NbtTagType.end;
  @override
  Null get value => null;
  @override
  NbtEnd clone() => NbtEnd();
  @override
  dynamic toJson() => null;
}

class NbtByte extends NbtTag {
  @override
  int get type => NbtTagType.byte;
  @override
  int value;
  NbtByte(this.value);
  @override
  NbtByte clone() => NbtByte(value);
  @override
  dynamic toJson() => value;
}

class NbtShort extends NbtTag {
  @override
  int get type => NbtTagType.short;
  @override
  int value;
  NbtShort(this.value);
  @override
  NbtShort clone() => NbtShort(value);
  @override
  dynamic toJson() => value;
}

class NbtInt extends NbtTag {
  @override
  int get type => NbtTagType.intValue;
  @override
  int value;
  NbtInt(this.value);
  @override
  NbtInt clone() => NbtInt(value);
  @override
  dynamic toJson() => value;
}

class NbtLong extends NbtTag {
  @override
  int get type => NbtTagType.long;
  @override
  int value; // Dart int is 64-bit, sufficient for Long
  NbtLong(this.value);
  @override
  NbtLong clone() => NbtLong(value);
  @override
  dynamic toJson() => value;
}

class NbtFloat extends NbtTag {
  @override
  int get type => NbtTagType.float;
  @override
  double value;
  NbtFloat(this.value);
  @override
  NbtFloat clone() => NbtFloat(value);
  @override
  dynamic toJson() => value;
}

class NbtDouble extends NbtTag {
  @override
  int get type => NbtTagType.double;
  @override
  double value;
  NbtDouble(this.value);
  @override
  NbtDouble clone() => NbtDouble(value);
  @override
  dynamic toJson() => value;
}

class NbtByteArray extends NbtTag {
  @override
  int get type => NbtTagType.byteArray;
  @override
  Uint8List value;
  NbtByteArray(this.value);
  @override
  NbtByteArray clone() => NbtByteArray(Uint8List.fromList(value));
  @override
  dynamic toJson() => value.toList();
}

class NbtString extends NbtTag {
  @override
  int get type => NbtTagType.string;
  @override
  String value;
  NbtString(this.value);
  @override
  NbtString clone() => NbtString(value);
  @override
  dynamic toJson() => value;
}

class NbtList extends NbtTag {
  @override
  int get type => NbtTagType.list;
  int elementType;
  @override
  List<NbtTag> value;
  NbtList(this.elementType, this.value);
  @override
  NbtList clone() => NbtList(elementType, value.map((e) => e.clone()).toList());
  @override
  dynamic toJson() => value.map((e) => e.toJson()).toList();
}

class NbtCompound extends NbtTag {
  @override
  int get type => NbtTagType.compound;
  @override
  Map<String, NbtTag> value;
  NbtCompound(this.value);
  @override
  NbtCompound clone() =>
      NbtCompound(value.map((k, v) => MapEntry(k, v.clone())));
  @override
  dynamic toJson() => value.map((k, v) => MapEntry(k, v.toJson()));
}

class NbtIntArray extends NbtTag {
  @override
  int get type => NbtTagType.intArray;
  @override
  Int32List value;
  NbtIntArray(this.value);
  @override
  NbtIntArray clone() => NbtIntArray(Int32List.fromList(value));
  @override
  dynamic toJson() => value.toList();
}

class NbtLongArray extends NbtTag {
  @override
  int get type => NbtTagType.longArray;
  @override
  Int64List value;
  NbtLongArray(this.value);
  @override
  NbtLongArray clone() => NbtLongArray(Int64List.fromList(value));
  @override
  dynamic toJson() => value.toList();
}

/// ShortArray (type=100) — 原 APK 工具自定义扩展，存储 short[] 列表
class NbtShortArray extends NbtTag {
  @override
  int get type => NbtTagType.shortArray;
  @override
  List<int> value; // 存储 short 值（-32768 ~ 32767）
  NbtShortArray(this.value);
  @override
  NbtShortArray clone() => NbtShortArray(List<int>.from(value));
  static NbtShortArray fromShorts(List<int> shorts) => NbtShortArray(shorts);
  @override
  dynamic toJson() => value;
}
