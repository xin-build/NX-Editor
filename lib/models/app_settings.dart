import 'package:flutter/material.dart';

/// 渲染模式枚举
enum MapLayerMode {
  satellite('卫星图 (原版方块)', '展示真实方块纹理基色、水体深度与高度光影', Icons.map_outlined),
  heightmap('高度图 (等高色谱)', '从基岩到天空高度的等高线与渐变色谱', Icons.terrain_outlined),
  biome('生态群系图', '展示各个生态群系的区域分布与特征色彩', Icons.forest_outlined),
  cave('地下洞穴网络', '透视地下空气连通域与天然空腔洞穴', Icons.bubble_chart_outlined),
  xray('X-Ray 矿石透视', '高亮透视钻石、绿宝石、远古残骸等指定矿物', Icons.diamond_outlined),
  nether('下界切片图', '避开下界顶部基岩，自定义截面高度查看下界地貌', Icons.local_fire_department_outlined),
  theEnd('末地岛屿图', '展示末地主岛、外岛及末地城结构', Icons.nightlight_round_outlined),
  slimeChunk('史莱姆区块', '基岩版标准算法实时计算并覆盖史莱姆区块网格', Icons.grid_4x4_outlined),
  blockLight('亮度图', '展示方块光源分布与光照强度等级', Icons.lightbulb_outline),
  foliage('植被与草地', '展示草方块与各生物群系植被着色', Icons.grass_outlined);

  final String title;
  final String description;
  final IconData icon;
  const MapLayerMode(this.title, this.description, this.icon);
}

/// 界面主题模式
enum AppThemeMode {
  dark('深邃暗色 (推荐)', ThemeMode.dark),
  light('明亮模式', ThemeMode.light),
  amoled('纯黑 AMOLED', ThemeMode.dark),
  emerald('绿宝石矿石 (经典)', ThemeMode.dark);

  final String label;
  final ThemeMode mode;
  const AppThemeMode(this.label, this.mode);
}

/// 全局设置模型
class AppSettings extends ChangeNotifier {
  static final AppSettings _instance = AppSettings._internal();
  factory AppSettings() => _instance;
  AppSettings._internal();

  // ─── 1. 常规设置 ───
  String _language = 'zh_CN'; // 'zh_CN' | 'en_US'
  AppThemeMode _themeMode = AppThemeMode.dark;
  Color _accentColor = const Color(0xFF4CAF50); // Minecraft Emerald Green
  bool _autoBackupOnOpen = true;
  bool _confirmOnExit = true;
  bool _autoSaveIntervalEnabled = false;
  int _autoSaveMinutes = 5;

  // ─── 2. 渲染与着色设置 ───
  MapLayerMode _defaultLayer = MapLayerMode.satellite;
  double _hillshadeIntensity = 1.0; // 0.0 ~ 2.0 (地形起伏阴影强度)
  bool _smoothShading = true; // 平滑光影渐变
  double _waterOpacity = 0.75; // 水体透明度
  bool _showChunkGrid = true;
  Color _gridColor = const Color(0x4DFFFFFF);
  double _gridLineWidth = 1.0;
  bool _showCoordinatesOverlay = true;
  Color _slimeChunkColor = const Color(0x5500FF66);
  double _caveOpacity = 0.65;
  int _netherSliceY = 64; // 下界切片截面 Y 坐标 (0 ~ 128)
  String _xrayTargetBlock = 'minecraft:diamond_ore';
  Color _xrayHighlightColor = const Color(0xFFFFEB3B);

  // ─── 3. 标记系统设置 ───
  bool _showPlayerMarkers = true;
  bool _showEntityMarkers = true;
  bool _showTileEntityMarkers = true;
  bool _showDroppedItemMarkers = false;
  double _markerIconSize = 24.0; // 标记图标大小
  bool _showMarkerLabels = true; // 是否显示实体名称标注
  Set<String> _enabledEntityFilter = {}; // 启用的实体类型过滤器 (空表示全启用)
  Set<String> _enabledTileEntityFilter = {};

  // ─── 4. GPU 硬件加速与性能 ───
  bool _gpuAcceleration = true; // 是否启用 GPU 纹理瓦片渲染
  int _maxCachedTiles = 8000; // 最大缓存瓦片数量 (LRU)
  int _isolateWorkerThreads = 2; // 后台解析线程数
  bool _viewportCulling = true; // 视口外剔除
  bool _highDpiRendering = true; // 高 DPI 渲染支持
  int _targetFps = 60; // 60 | 120 | 0 (无限制)

  // ─── 5. 控制与操作偏好 (PC & Mobile) ───
  double _mouseWheelZoomSpeed = 1.15;
  bool _zoomToCursor = true; // PC: 滚轮以鼠标光标为中心缩放
  bool _invertZoom = false;
  double _touchZoomSensitivity = 1.0;
  bool _showMobileFloatingPad = true; // 移动端显示悬浮快捷轮盘
  bool _doubleTapToFocus = true;
  int _selectionStep = 1; // 1: 方块对齐, 16: 区块对齐

  // ─── 6. 路径与低版本兼容 ───
  List<String> _customWorldPaths = [];
  bool _enableLegacySaveSupport = true; // 兼容 0.14 - 1.17 等低版本存档
  bool _preferOldBiomes = false; // 是否使用旧版生态群系色表
  bool _preferOldItems = false; // 是否使用旧版物品图标

  // ─── Getters ───
  String get language => _language;
  AppThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;
  bool get autoBackupOnOpen => _autoBackupOnOpen;
  bool get confirmOnExit => _confirmOnExit;
  bool get autoSaveIntervalEnabled => _autoSaveIntervalEnabled;
  int get autoSaveMinutes => _autoSaveMinutes;

  MapLayerMode get defaultLayer => _defaultLayer;
  double get hillshadeIntensity => _hillshadeIntensity;
  bool get smoothShading => _smoothShading;
  double get waterOpacity => _waterOpacity;
  bool get showChunkGrid => _showChunkGrid;
  Color get gridColor => _gridColor;
  double get gridLineWidth => _gridLineWidth;
  bool get showCoordinatesOverlay => _showCoordinatesOverlay;
  Color get slimeChunkColor => _slimeChunkColor;
  double get caveOpacity => _caveOpacity;
  int get netherSliceY => _netherSliceY;
  String get xrayTargetBlock => _xrayTargetBlock;
  Color get xrayHighlightColor => _xrayHighlightColor;

  bool get showPlayerMarkers => _showPlayerMarkers;
  bool get showEntityMarkers => _showEntityMarkers;
  bool get showTileEntityMarkers => _showTileEntityMarkers;
  bool get showDroppedItemMarkers => _showDroppedItemMarkers;
  double get markerIconSize => _markerIconSize;
  bool get showMarkerLabels => _showMarkerLabels;
  Set<String> get enabledEntityFilter => _enabledEntityFilter;
  Set<String> get enabledTileEntityFilter => _enabledTileEntityFilter;

  bool get gpuAcceleration => _gpuAcceleration;
  int get maxCachedTiles => _maxCachedTiles;
  int get isolateWorkerThreads => _isolateWorkerThreads;
  bool get viewportCulling => _viewportCulling;
  bool get highDpiRendering => _highDpiRendering;
  int get targetFps => _targetFps;

  double get mouseWheelZoomSpeed => _mouseWheelZoomSpeed;
  bool get zoomToCursor => _zoomToCursor;
  bool get invertZoom => _invertZoom;
  double get touchZoomSensitivity => _touchZoomSensitivity;
  bool get showMobileFloatingPad => _showMobileFloatingPad;
  bool get doubleTapToFocus => _doubleTapToFocus;
  int get selectionStep => _selectionStep;

  List<String> get customWorldPaths => List.unmodifiable(_customWorldPaths);
  bool get enableLegacySaveSupport => _enableLegacySaveSupport;
  bool get preferOldBiomes => _preferOldBiomes;
  bool get preferOldItems => _preferOldItems;

  // ─── Setters ───
  void setLanguage(String val) { _language = val; notifyListeners(); }
  void setThemeMode(AppThemeMode val) { _themeMode = val; notifyListeners(); }
  void setAccentColor(Color val) { _accentColor = val; notifyListeners(); }
  void setAutoBackupOnOpen(bool val) { _autoBackupOnOpen = val; notifyListeners(); }
  void setConfirmOnExit(bool val) { _confirmOnExit = val; notifyListeners(); }
  void setAutoSave(bool enabled, int minutes) { _autoSaveIntervalEnabled = enabled; _autoSaveMinutes = minutes; notifyListeners(); }

  void setDefaultLayer(MapLayerMode val) { _defaultLayer = val; notifyListeners(); }
  void setHillshadeIntensity(double val) { _hillshadeIntensity = val; notifyListeners(); }
  void setSmoothShading(bool val) { _smoothShading = val; notifyListeners(); }
  void setWaterOpacity(double val) { _waterOpacity = val; notifyListeners(); }
  void setShowChunkGrid(bool val) { _showChunkGrid = val; notifyListeners(); }
  void setGridColor(Color val) { _gridColor = val; notifyListeners(); }
  void setGridLineWidth(double val) { _gridLineWidth = val; notifyListeners(); }
  void setShowCoordinatesOverlay(bool val) { _showCoordinatesOverlay = val; notifyListeners(); }
  void setSlimeChunkColor(Color val) { _slimeChunkColor = val; notifyListeners(); }
  void setCaveOpacity(double val) { _caveOpacity = val; notifyListeners(); }
  void setNetherSliceY(int val) { _netherSliceY = val; notifyListeners(); }
  void setXrayTarget(String blockId, Color color) { _xrayTargetBlock = blockId; _xrayHighlightColor = color; notifyListeners(); }

  void setShowPlayerMarkers(bool val) { _showPlayerMarkers = val; notifyListeners(); }
  void setShowEntityMarkers(bool val) { _showEntityMarkers = val; notifyListeners(); }
  void setShowTileEntityMarkers(bool val) { _showTileEntityMarkers = val; notifyListeners(); }
  void setShowDroppedItemMarkers(bool val) { _showDroppedItemMarkers = val; notifyListeners(); }
  void setMarkerIconSize(double val) { _markerIconSize = val; notifyListeners(); }
  void setShowMarkerLabels(bool val) { _showMarkerLabels = val; notifyListeners(); }
  void setEntityFilter(Set<String> val) { _enabledEntityFilter = val; notifyListeners(); }
  void setTileEntityFilter(Set<String> val) { _enabledTileEntityFilter = val; notifyListeners(); }

  void setGpuAcceleration(bool val) { _gpuAcceleration = val; notifyListeners(); }
  void setMaxCachedTiles(int val) { _maxCachedTiles = val; notifyListeners(); }
  void setIsolateThreads(int val) { _isolateWorkerThreads = val; notifyListeners(); }
  void setViewportCulling(bool val) { _viewportCulling = val; notifyListeners(); }
  void setHighDpiRendering(bool val) { _highDpiRendering = val; notifyListeners(); }
  void setTargetFps(int val) { _targetFps = val; notifyListeners(); }

  void setMouseWheelZoomSpeed(double val) { _mouseWheelZoomSpeed = val; notifyListeners(); }
  void setZoomToCursor(bool val) { _zoomToCursor = val; notifyListeners(); }
  void setInvertZoom(bool val) { _invertZoom = val; notifyListeners(); }
  void setTouchZoomSensitivity(double val) { _touchZoomSensitivity = val; notifyListeners(); }
  void setShowMobileFloatingPad(bool val) { _showMobileFloatingPad = val; notifyListeners(); }
  void setDoubleTapToFocus(bool val) { _doubleTapToFocus = val; notifyListeners(); }
  void setSelectionStep(int val) { _selectionStep = val; notifyListeners(); }

  void addCustomWorldPath(String path) {
    if (!_customWorldPaths.contains(path)) {
      _customWorldPaths.add(path);
      notifyListeners();
    }
  }
  void removeCustomWorldPath(String path) {
    if (_customWorldPaths.remove(path)) {
      notifyListeners();
    }
  }
  void setEnableLegacySaveSupport(bool val) { _enableLegacySaveSupport = val; notifyListeners(); }
  void setPreferOldBiomes(bool val) { _preferOldBiomes = val; notifyListeners(); }
  void setPreferOldItems(bool val) { _preferOldItems = val; notifyListeners(); }

  // ─── JSON 序列化与持久化 ───
  Map<String, dynamic> toJson() => {
    'language': _language,
    'themeMode': _themeMode.name,
    'accentColor': _accentColor.toARGB32(),
    'autoBackupOnOpen': _autoBackupOnOpen,
    'confirmOnExit': _confirmOnExit,
    'autoSaveIntervalEnabled': _autoSaveIntervalEnabled,
    'autoSaveMinutes': _autoSaveMinutes,
    'defaultLayer': _defaultLayer.name,
    'hillshadeIntensity': _hillshadeIntensity,
    'smoothShading': _smoothShading,
    'waterOpacity': _waterOpacity,
    'showChunkGrid': _showChunkGrid,
    'gridColor': _gridColor.toARGB32(),
    'gridLineWidth': _gridLineWidth,
    'showCoordinatesOverlay': _showCoordinatesOverlay,
    'slimeChunkColor': _slimeChunkColor.toARGB32(),
    'caveOpacity': _caveOpacity,
    'netherSliceY': _netherSliceY,
    'xrayTargetBlock': _xrayTargetBlock,
    'xrayHighlightColor': _xrayHighlightColor.toARGB32(),
    'showPlayerMarkers': _showPlayerMarkers,
    'showEntityMarkers': _showEntityMarkers,
    'showTileEntityMarkers': _showTileEntityMarkers,
    'showDroppedItemMarkers': _showDroppedItemMarkers,
    'markerIconSize': _markerIconSize,
    'showMarkerLabels': _showMarkerLabels,
    'gpuAcceleration': _gpuAcceleration,
    'maxCachedTiles': _maxCachedTiles,
    'isolateWorkerThreads': _isolateWorkerThreads,
    'viewportCulling': _viewportCulling,
    'highDpiRendering': _highDpiRendering,
    'targetFps': _targetFps,
    'mouseWheelZoomSpeed': _mouseWheelZoomSpeed,
    'zoomToCursor': _zoomToCursor,
    'invertZoom': _invertZoom,
    'touchZoomSensitivity': _touchZoomSensitivity,
    'showMobileFloatingPad': _showMobileFloatingPad,
    'doubleTapToFocus': _doubleTapToFocus,
    'selectionStep': _selectionStep,
    'customWorldPaths': _customWorldPaths,
    'enableLegacySaveSupport': _enableLegacySaveSupport,
    'preferOldBiomes': _preferOldBiomes,
    'preferOldItems': _preferOldItems,
  };

  void loadFromJson(Map<String, dynamic> json) {
    try {
      if (json['language'] != null) _language = json['language'] as String;
      if (json['themeMode'] != null) {
        _themeMode = AppThemeMode.values.firstWhere(
          (e) => e.name == json['themeMode'],
          orElse: () => AppThemeMode.dark,
        );
      }
      if (json['accentColor'] != null) _accentColor = Color(json['accentColor'] as int);
      if (json['autoBackupOnOpen'] != null) _autoBackupOnOpen = json['autoBackupOnOpen'] as bool;
      if (json['confirmOnExit'] != null) _confirmOnExit = json['confirmOnExit'] as bool;
      if (json['autoSaveIntervalEnabled'] != null) _autoSaveIntervalEnabled = json['autoSaveIntervalEnabled'] as bool;
      if (json['autoSaveMinutes'] != null) _autoSaveMinutes = json['autoSaveMinutes'] as int;

      if (json['defaultLayer'] != null) {
        _defaultLayer = MapLayerMode.values.firstWhere(
          (e) => e.name == json['defaultLayer'],
          orElse: () => MapLayerMode.satellite,
        );
      }
      if (json['hillshadeIntensity'] != null) _hillshadeIntensity = (json['hillshadeIntensity'] as num).toDouble();
      if (json['smoothShading'] != null) _smoothShading = json['smoothShading'] as bool;
      if (json['waterOpacity'] != null) _waterOpacity = (json['waterOpacity'] as num).toDouble();
      if (json['showChunkGrid'] != null) _showChunkGrid = json['showChunkGrid'] as bool;
      if (json['gridColor'] != null) _gridColor = Color(json['gridColor'] as int);
      if (json['gridLineWidth'] != null) _gridLineWidth = (json['gridLineWidth'] as num).toDouble();
      if (json['showCoordinatesOverlay'] != null) _showCoordinatesOverlay = json['showCoordinatesOverlay'] as bool;
      if (json['slimeChunkColor'] != null) _slimeChunkColor = Color(json['slimeChunkColor'] as int);
      if (json['caveOpacity'] != null) _caveOpacity = (json['caveOpacity'] as num).toDouble();
      if (json['netherSliceY'] != null) _netherSliceY = json['netherSliceY'] as int;
      if (json['xrayTargetBlock'] != null) _xrayTargetBlock = json['xrayTargetBlock'] as String;
      if (json['xrayHighlightColor'] != null) _xrayHighlightColor = Color(json['xrayHighlightColor'] as int);

      if (json['showPlayerMarkers'] != null) _showPlayerMarkers = json['showPlayerMarkers'] as bool;
      if (json['showEntityMarkers'] != null) _showEntityMarkers = json['showEntityMarkers'] as bool;
      if (json['showTileEntityMarkers'] != null) _showTileEntityMarkers = json['showTileEntityMarkers'] as bool;
      if (json['showDroppedItemMarkers'] != null) _showDroppedItemMarkers = json['showDroppedItemMarkers'] as bool;
      if (json['markerIconSize'] != null) _markerIconSize = (json['markerIconSize'] as num).toDouble();
      if (json['showMarkerLabels'] != null) _showMarkerLabels = json['showMarkerLabels'] as bool;

      if (json['gpuAcceleration'] != null) _gpuAcceleration = json['gpuAcceleration'] as bool;
      if (json['maxCachedTiles'] != null) _maxCachedTiles = json['maxCachedTiles'] as int;
      if (json['isolateWorkerThreads'] != null) _isolateWorkerThreads = json['isolateWorkerThreads'] as int;
      if (json['viewportCulling'] != null) _viewportCulling = json['viewportCulling'] as bool;
      if (json['highDpiRendering'] != null) _highDpiRendering = json['highDpiRendering'] as bool;
      if (json['targetFps'] != null) _targetFps = json['targetFps'] as int;

      if (json['mouseWheelZoomSpeed'] != null) _mouseWheelZoomSpeed = (json['mouseWheelZoomSpeed'] as num).toDouble();
      if (json['zoomToCursor'] != null) _zoomToCursor = json['zoomToCursor'] as bool;
      if (json['invertZoom'] != null) _invertZoom = json['invertZoom'] as bool;
      if (json['touchZoomSensitivity'] != null) _touchZoomSensitivity = (json['touchZoomSensitivity'] as num).toDouble();
      if (json['showMobileFloatingPad'] != null) _showMobileFloatingPad = json['showMobileFloatingPad'] as bool;
      if (json['doubleTapToFocus'] != null) _doubleTapToFocus = json['doubleTapToFocus'] as bool;
      if (json['selectionStep'] != null) _selectionStep = json['selectionStep'] as int;

      if (json['customWorldPaths'] != null) {
        _customWorldPaths = List<String>.from(json['customWorldPaths'] as List);
      }
      if (json['enableLegacySaveSupport'] != null) _enableLegacySaveSupport = json['enableLegacySaveSupport'] as bool;
      if (json['preferOldBiomes'] != null) _preferOldBiomes = json['preferOldBiomes'] as bool;
      if (json['preferOldItems'] != null) _preferOldItems = json['preferOldItems'] as bool;

      notifyListeners();
    } catch (_) {}
  }
}
