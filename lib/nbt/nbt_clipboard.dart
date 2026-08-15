import 'nbt_tags.dart';

/// 全局 NBT 剪贴板服务 (单例模式)
class NbtClipboard {
  static final NbtClipboard _instance = NbtClipboard._internal();
  factory NbtClipboard() => _instance;
  NbtClipboard._internal();

  String? _name;
  NbtTag? _tag;
  String? _sourceKey;
  List<String>? _sourcePath;

  bool get hasItem => _tag != null;
  String? get name => _name;
  NbtTag? get tag => _tag?.clone();
  int? get type => _tag?.type;
  String? get sourceKey => _sourceKey;
  List<String>? get sourcePath => _sourcePath;

  /// 复制标签到剪贴板
  void copy(String name, NbtTag tag, {String? sourceKey, List<String>? sourcePath}) {
    _name = name;
    _tag = tag.clone();
    _sourceKey = sourceKey;
    _sourcePath = sourcePath != null ? List<String>.from(sourcePath) : null;
  }

  /// 清空剪贴板
  void clear() {
    _name = null;
    _tag = null;
    _sourceKey = null;
    _sourcePath = null;
  }
}
