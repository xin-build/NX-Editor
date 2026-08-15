import 'package:flutter/material.dart';

/// 2D 视口变换与自由相机控制器 (支持无限制平移自由漫游与流畅缩放)
class MapViewportController extends ChangeNotifier {
  Offset _mapOffset = Offset.zero;
  double _scale = 1.0; // 缩放倍率 (0.05 ~ 64.0)
  double _blockSize = 4.0; // 基础方块像素大小 (1 chunk = 16 * blockSize = 64px on scale 1.0)
  Size _viewportSize = Size.zero;

  // 世界已探索边界 (Chunk 坐标)
  int _worldMinCx = 0;
  int _worldMaxCx = 0;
  int _worldMinCz = 0;
  int _worldMaxCz = 0;
  bool _hasWorldBounds = false;

  // 光标在世界坐标系中的投影
  double _cursorWorldX = 0;
  double _cursorWorldZ = 0;
  bool _isCursorInside = false;

  // Getters
  Offset get mapOffset => _mapOffset;
  double get scale => _scale;
  double get blockSize => _blockSize;
  Size get viewportSize => _viewportSize;
  double get cursorWorldX => _cursorWorldX;
  double get cursorWorldZ => _cursorWorldZ;
  bool get isCursorInside => _isCursorInside;

  int get worldMinCx => _worldMinCx;
  int get worldMaxCx => _worldMaxCx;
  int get worldMinCz => _worldMinCz;
  int get worldMaxCz => _worldMaxCz;
  bool get hasWorldBounds => _hasWorldBounds;

  double get chunkPixelSize => 16 * _blockSize * _scale;

  void setWorldBounds(int minCx, int maxCx, int minCz, int maxCz) {
    _worldMinCx = minCx;
    _worldMaxCx = maxCx;
    _worldMinCz = minCz;
    _worldMaxCz = maxCz;
    _hasWorldBounds = true;
    notifyListeners();
  }

  void setViewportSize(Size size) {
    if (_viewportSize != size) {
      _viewportSize = size;
      notifyListeners();
    }
  }

  void setBlockSize(double size) {
    _blockSize = size;
    notifyListeners();
  }

  /// 自由平移地图 (无边界锁死限制，任意拖拽)
  void pan(Offset delta) {
    _mapOffset += delta;
    notifyListeners();
  }

  void setOffset(Offset offset) {
    _mapOffset = offset;
    notifyListeners();
  }

  /// 以当前视口中心为锚点缩放
  void zoom(double factor) {
    final focal = Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    zoomAt(factor: factor, focalPoint: focal);
  }

  /// 以指定屏幕锚点进行平滑缩放
  void zoomAt({required double factor, required Offset focalPoint}) {
    final oldScale = _scale;
    final newScale = (_scale * factor).clamp(0.05, 64.0);
    if (oldScale == newScale) return;

    final worldBefore = screenToWorld(focalPoint);
    _scale = newScale;
    final screenAfter = worldToScreen(worldBefore);
    final delta = focalPoint - screenAfter;
    _mapOffset += delta;

    _cursorWorldX = worldBefore.dx;
    _cursorWorldZ = worldBefore.dy;
    _isCursorInside = true;

    notifyListeners();
  }

  void setScale(double newScale) {
    _scale = newScale.clamp(0.05, 64.0);
    notifyListeners();
  }

  /// 居中定位到世界中心
  void centerOnWorld() {
    if (!_hasWorldBounds || _viewportSize == Size.zero) return;
    final centerBlockX = (_worldMinCx + _worldMaxCx + 1) * 8.0;
    final centerBlockZ = (_worldMinCz + _worldMaxCz + 1) * 8.0;
    centerOnBlock(centerBlockX, centerBlockZ);
  }

  /// 居中定位到指定方块坐标
  void centerOnBlock(double worldX, double worldZ) {
    if (_viewportSize == Size.zero) return;
    final blockPixels = _blockSize * _scale;
    final screenCenterX = _viewportSize.width / 2.0;
    final screenCenterY = _viewportSize.height / 2.0;

    _mapOffset = Offset(
      screenCenterX - worldX * blockPixels,
      screenCenterY - worldZ * blockPixels,
    );
    notifyListeners();
  }

  /// 屏幕坐标 -> 世界方块坐标
  Offset screenToWorld(Offset screenPos) {
    final blockPixels = _blockSize * _scale;
    final worldX = (screenPos.dx - _mapOffset.dx) / blockPixels;
    final worldZ = (screenPos.dy - _mapOffset.dy) / blockPixels;
    return Offset(worldX, worldZ);
  }

  /// 世界方块坐标 -> 屏幕坐标
  Offset worldToScreen(Offset worldPos) {
    final blockPixels = _blockSize * _scale;
    final screenX = worldPos.dx * blockPixels + _mapOffset.dx;
    final screenY = worldPos.dy * blockPixels + _mapOffset.dy;
    return Offset(screenX, screenY);
  }

  /// 更新光标世界坐标
  void updateCursorPosition(Offset screenPos) {
    final world = screenToWorld(screenPos);
    _cursorWorldX = world.dx;
    _cursorWorldZ = world.dy;
    _isCursorInside = true;
    notifyListeners();
  }

  void cursorLeave() {
    _isCursorInside = false;
    notifyListeners();
  }

  /// 获取当前视口内可见的区块坐标范围 (用于高效视锥裁剪)
  Map<String, int> getVisibleChunkBounds() {
    final topLeft = screenToWorld(Offset.zero);
    final bottomRight = screenToWorld(Offset(_viewportSize.width, _viewportSize.height));

    final minCx = (topLeft.dx / 16.0).floor() - 1;
    final maxCx = (bottomRight.dx / 16.0).ceil() + 1;
    final minCz = (topLeft.dy / 16.0).floor() - 1;
    final maxCz = (bottomRight.dy / 16.0).ceil() + 1;

    return {
      'minCx': minCx,
      'maxCx': maxCx,
      'minCz': minCz,
      'maxCz': maxCz,
    };
  }
}
