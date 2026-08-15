import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// 游戏 ID 数据条目
class GameIdEntry {
  final String name; // 中文名
  final String id; // 字符串 ID (如 stone, chicken)
  final String numId; // 十进制数字 ID
  final String? hexId; // 十六进制 ID

  const GameIdEntry({
    required this.name,
    required this.id,
    required this.numId,
    this.hexId,
  });

  factory GameIdEntry.fromJson(Map<String, dynamic> json) {
    return GameIdEntry(
      name: json['name'] as String? ?? '',
      id: json['id'] as String? ?? '',
      numId: (json['numId'] ?? '').toString(),
      hexId: json['hexId']?.toString(),
    );
  }
}

/// 地图基色条目
class MapColorEntry {
  final String id;
  final String name;
  final int r, g, b;

  const MapColorEntry({
    required this.id,
    required this.name,
    required this.r,
    required this.g,
    required this.b,
  });

  factory MapColorEntry.fromJson(Map<String, dynamic> json) {
    final rgb = json['rgb'] as List<dynamic>? ?? [0, 0, 0];
    return MapColorEntry(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      r: (rgb.isNotEmpty ? rgb[0] : 0) as int,
      g: (rgb.length > 1 ? rgb[1] : 0) as int,
      b: (rgb.length > 2 ? rgb[2] : 0) as int,
    );
  }
}

/// 游戏数据服务：加载所有 ID 映射 + 地图基色
class GameDataService {
  static final GameDataService _instance = GameDataService._();
  factory GameDataService() => _instance;
  GameDataService._();

  bool _loaded = false;

  // 实体
  final List<GameIdEntry> entities = [];
  final Map<String, GameIdEntry> _entityByNumId = {};
  final Map<String, GameIdEntry> _entityById = {};

  // 方块
  final List<GameIdEntry> blocks = [];
  final Map<String, GameIdEntry> _blockByNumId = {};
  final Map<String, GameIdEntry> _blockById = {};

  // 物品 (新旧可切换)
  List<GameIdEntry> items = [];
  final Map<String, GameIdEntry> _itemByNumId = {};
  final Map<String, GameIdEntry> _itemById = {};
  List<GameIdEntry> itemsOld = [];
  final Map<String, GameIdEntry> _itemByNumIdOld = {};
  final Map<String, GameIdEntry> _itemByIdOld = {};
  bool _useOldItem = false;

  // 群系 (新旧可切换)
  List<GameIdEntry> biomes = [];
  final Map<String, GameIdEntry> _biomeByNumId = {};
  final Map<String, GameIdEntry> _biomeById = {};
  List<GameIdEntry> biomesOld = [];
  final Map<String, GameIdEntry> _biomeByNumIdOld = {};
  final Map<String, GameIdEntry> _biomeByIdOld = {};
  bool _useOldBiome = false;

  // 药水效果
  final List<GameIdEntry> effects = [];
  final Map<String, GameIdEntry> _effectByNumId = {};
  final Map<String, GameIdEntry> _effectById = {};

  // 附魔
  final List<GameIdEntry> enchantments = [];
  final Map<String, GameIdEntry> _enchantmentByNumId = {};
  final Map<String, GameIdEntry> _enchantmentById = {};

  // 地图基色
  final List<MapColorEntry> mapColors = [];
  final Map<String, MapColorEntry> _mapColorById = {};
  // 缓存模糊匹配和 fallback 的颜色结果，避免每像素重复计算
  final Map<String, int> _resolvedColorCache = {};

  // 弱引用或直接引用 DataManager 实例，用于跨组件共享缓存
  dynamic dataManager;

  bool get isLoaded => _loaded;
  bool get useOldItem => _useOldItem;
  bool get useOldBiome => _useOldBiome;

  void setUseOldItem(bool v) {
    _useOldItem = v;
  }

  void setUseOldBiome(bool v) {
    _useOldBiome = v;
  }

  /// 加载所有数据
  Future<void> loadAll() async {
    if (_loaded) return;
    await Future.wait([
      _loadEntity(),
      _loadItems(),
      _loadItemsOld(),
      _loadBiomes(),
      _loadBiomesOld(),
      _loadEffects(),
      _loadEnchantments(),
      _loadMapColors(),
    ]);
    _loaded = true;
  }

  // ─── 查询 ───
  GameIdEntry? entityByNumId(String numId) => _entityByNumId[numId];
  GameIdEntry? entityById(String id) => _entityById[id];

  GameIdEntry? blockByNumId(String numId) => _blockByNumId[numId];
  GameIdEntry? blockById(String id) => _blockById[id];

  GameIdEntry? itemByNumId(String numId) =>
      _useOldItem ? _itemByNumIdOld[numId] : _itemByNumId[numId];
  GameIdEntry? itemById(String id) =>
      _useOldItem ? _itemByIdOld[id] : _itemById[id];

  GameIdEntry? biomeByNumId(String numId) =>
      _useOldBiome ? _biomeByNumIdOld[numId] : _biomeByNumId[numId];
  GameIdEntry? biomeById(String id) =>
      _useOldBiome ? _biomeByIdOld[id] : _biomeById[id];

  GameIdEntry? effectByNumId(String numId) => _effectByNumId[numId];
  GameIdEntry? effectById(String id) => _effectById[id];

  GameIdEntry? enchantmentByNumId(String numId) => _enchantmentByNumId[numId];
  GameIdEntry? enchantmentById(String id) => _enchantmentById[id];

  MapColorEntry? mapColorById(String id) => _mapColorById[id];

  int? getResolvedColor(String blockId) => _resolvedColorCache[blockId];
  void cacheResolvedColor(String blockId, int colorValue) {
    _resolvedColorCache[blockId] = colorValue;
  }

  void clearResolvedColorCache() {
    _resolvedColorCache.clear();
  }

  // ─── 加载 ───
  Future<void> _loadEntity() async {
    final data = await rootBundle.loadString('assrts/data/entity.json');
    final list = json.decode(data) as List<dynamic>;
    _loadList(list, entities, _entityByNumId, _entityById);
  }

  Future<void> _loadItems() async {
    final data = await rootBundle.loadString('assrts/data/item.json');
    final list = json.decode(data) as List<dynamic>;
    _loadList(list, items, _itemByNumId, _itemById);
  }

  Future<void> _loadItemsOld() async {
    final data = await rootBundle.loadString('assrts/data/item-old.json');
    final list = json.decode(data) as List<dynamic>;
    _loadList(list, itemsOld, _itemByNumIdOld, _itemByIdOld);
  }

  Future<void> _loadBiomes() async {
    final data = await rootBundle.loadString('assrts/data/biomes.json');
    final list = json.decode(data) as List<dynamic>;
    _loadList(list, biomes, _biomeByNumId, _biomeById);
  }

  Future<void> _loadBiomesOld() async {
    final data = await rootBundle.loadString('assrts/data/biomes-old.json');
    final list = json.decode(data) as List<dynamic>;
    _loadList(list, biomesOld, _biomeByNumIdOld, _biomeByIdOld);
  }

  Future<void> _loadEffects() async {
    final data = await rootBundle.loadString('assrts/data/effect.json');
    final list = json.decode(data) as List<dynamic>;
    // effect.json: "id" = numId, "numId" = stringId (反转)
    for (final item in list) {
      final m = item as Map<String, dynamic>;
      final entry = GameIdEntry(
        name: m['name'] as String? ?? '',
        id: (m['numId'] ?? '').toString(), // 字符串 ID
        numId: (m['id'] ?? '').toString(), // 数字 ID
      );
      effects.add(entry);
      _effectByNumId[entry.numId] = entry;
      _effectById[entry.id] = entry;
    }
  }

  Future<void> _loadEnchantments() async {
    final data = await rootBundle.loadString('assrts/data/enchantment.json');
    final list = json.decode(data) as List<dynamic>;
    _loadList(list, enchantments, _enchantmentByNumId, _enchantmentById);
  }

  Future<void> _loadMapColors() async {
    final data = await rootBundle.loadString('assrts/map/map_color_card.json');
    final list = json.decode(data) as List<dynamic>;
    for (final item in list) {
      final entry = MapColorEntry.fromJson(item as Map<String, dynamic>);
      mapColors.add(entry);
      _mapColorById[entry.id] = entry;
    }
    // 也加载 block 基色到 mapColor（block.json 包含所有方块）
    await _loadBlockColors();
  }

  Future<void> _loadBlockColors() async {
    final data = await rootBundle.loadString('assrts/data/block.json');
    final list = json.decode(data) as List<dynamic>;
    _loadList(list, blocks, _blockByNumId, _blockById);
  }

  void _loadList(
    List<dynamic> jsonList,
    List<GameIdEntry> target,
    Map<String, GameIdEntry> byNumId,
    Map<String, GameIdEntry> byId,
  ) {
    for (final item in jsonList) {
      final entry = GameIdEntry.fromJson(item as Map<String, dynamic>);
      target.add(entry);
      byNumId[entry.numId] = entry;
      if (entry.id.isNotEmpty) byId[entry.id] = entry;
    }
  }
}
