import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data/data_manager.dart';
import '../models/app_settings.dart';
import '../models/chunk_key.dart';
import '../models/marker_data.dart';
import '../models/selection_model.dart';
import '../render/gpu_tile_renderer.dart';
import '../render/map_viewport_controller.dart';
import '../screens/nbt_editor_full_screen.dart';
import '../services/entity_service.dart';
import '../utils/asset_icon_cache.dart';
import 'nbt_special_editors/block_entity_editor.dart';
import 'nbt_special_editors/entity_nbt_editor.dart';

/// 交互式 2D 地图画布组件 (直绘实体与方块实体原生高清图标 + 经典 BTR 手势)
class MapCanvasWidget extends StatefulWidget {
  final MapViewportController viewport;
  final SelectionModel? selection;
  final int dimension;
  final MapLayerMode layerMode;
  final bool isSelectionMode;
  final void Function(double worldX, double worldZ)? onMapLongPress;
  final void Function(MapMarker marker)? onMarkerTap;
  final void Function(SelectionModel selection)? onSelectionChanged;

  const MapCanvasWidget({
    super.key,
    required this.viewport,
    this.selection,
    this.dimension = 0,
    required this.layerMode,
    this.isSelectionMode = false,
    this.onMapLongPress,
    this.onMarkerTap,
    this.onSelectionChanged,
  });

  @override
  State<MapCanvasWidget> createState() => _MapCanvasWidgetState();
}

class _MapCanvasWidgetState extends State<MapCanvasWidget> {
  Offset? _dragStart;
  Offset? _initialOffset;
  double _baseScale = 1.0;

  // 选区拖拽与平移状态
  Offset? _selectionDragStartWorld;
  SelectionModel? _initialSelectionSnapshot;
  bool _isDraggingSelection = false;

  // 实体与方块实体缓存
  List<WorldEntity> _cachedEntities = [];
  List<WorldBlockEntity> _cachedBlockEntities = [];

  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DataManager>();
    final settings = context.watch<AppSettings>();

    _cachedEntities = EntityService().parseAllEntities(dm);
    _cachedBlockEntities = EntityService().parseAllBlockEntities(dm);

    return ClipRect(
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          widget.viewport.setViewportSize(Size(constraints.maxWidth, constraints.maxHeight));

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  final zoomFactor = event.scrollDelta.dy < 0
                      ? settings.mouseWheelZoomSpeed
                      : (1.0 / settings.mouseWheelZoomSpeed);
                  final focal = settings.zoomToCursor ? event.localPosition : Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
                  widget.viewport.zoomAt(factor: zoomFactor, focalPoint: focal);
                  widget.viewport.updateCursorPosition(event.localPosition);
                }
              },
              onPointerHover: (event) {
                widget.viewport.updateCursorPosition(event.localPosition);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final worldPos = widget.viewport.screenToWorld(details.localPosition);
                  final isCtrl = HardwareKeyboard.instance.isControlPressed;

                  if (widget.isSelectionMode) {
                    _handleSelectionTap(worldPos.dx, worldPos.dy, isCtrl: isCtrl);
                  } else {
                    _handleTap(worldPos.dx, worldPos.dy, dm);
                  }
                },
                onScaleStart: (details) {
                  _dragStart = details.localFocalPoint;
                  _initialOffset = widget.viewport.mapOffset;
                  _baseScale = widget.viewport.scale;

                  if (widget.isSelectionMode && details.pointerCount == 1) {
                    final worldPos = widget.viewport.screenToWorld(details.localFocalPoint);
                    _selectionDragStartWorld = worldPos;
                    _isDraggingSelection = true;
                    if (widget.selection != null) {
                      _initialSelectionSnapshot = widget.selection!.clone();
                    }
                  }
                },
                onScaleUpdate: (details) {
                  if (details.pointerCount > 1) {
                    final scaleDelta = details.scale;
                    widget.viewport.zoomAt(
                      factor: scaleDelta / (_baseScale > 0 ? _baseScale : 1.0),
                      focalPoint: details.localFocalPoint,
                    );
                    _baseScale = details.scale;
                  } else if (widget.isSelectionMode && _isDraggingSelection && _selectionDragStartWorld != null) {
                    final currentWorld = widget.viewport.screenToWorld(details.localFocalPoint);
                    final isAlt = HardwareKeyboard.instance.isAltPressed;

                    if (isAlt && _initialSelectionSnapshot != null) {
                      final dx = (currentWorld.dx - _selectionDragStartWorld!.dx).round();
                      final dz = (currentWorld.dy - _selectionDragStartWorld!.dy).round();
                      _translateSelection(_initialSelectionSnapshot!, dx, dz);
                    } else {
                      _updateSelectionBox(_selectionDragStartWorld!, currentWorld);
                    }
                  } else if (_dragStart != null && _initialOffset != null) {
                    final delta = details.localFocalPoint - _dragStart!;
                    widget.viewport.setOffset(_initialOffset! + delta);
                  }
                },
                onScaleEnd: (_) {
                  _dragStart = null;
                  _initialOffset = null;
                  _isDraggingSelection = false;
                  _selectionDragStartWorld = null;
                  _initialSelectionSnapshot = null;
                },
                onSecondaryTapUp: (details) {
                  final worldPos = widget.viewport.screenToWorld(details.localPosition);
                  _showContextMenu(context, details.globalPosition, worldPos.dx, worldPos.dy, dm);
                },
                onLongPressStart: (details) {
                  final worldPos = widget.viewport.screenToWorld(details.localPosition);
                  _showContextMenu(context, details.globalPosition, worldPos.dx, worldPos.dy, dm);
                },
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: _MapCanvasPainter(
                      viewport: widget.viewport,
                      dataManager: dm,
                      settings: settings,
                      dimension: widget.dimension,
                      layerMode: widget.layerMode,
                      selection: widget.selection,
                      isSelectionMode: widget.isSelectionMode,
                      entities: _cachedEntities,
                      blockEntities: _cachedBlockEntities,
                      onRepaintRequest: () {
                        if (mounted) {
                          setState(() {});
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),

            if (widget.selection != null && widget.selection!.dimension == widget.dimension)
              Positioned(
                bottom: 16,
                left: 16,
                child: _buildSelectionHud(widget.selection!),
              ),

            // 地图悬浮快捷图层/标记过滤器 (1键开启/隐藏容器、生物、网格与玩家)
            Positioned(
              top: 12,
              right: 16,
              child: _buildFloatingFilterChips(settings),
            ),
          ],
        );
      },
    ),
  );
}

  Widget _buildFloatingFilterChips(AppSettings settings) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xDD1E222B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFilterChip(
            label: '玩家',
            icon: Icons.person,
            active: settings.showPlayerMarkers,
            color: Colors.redAccent,
            onTap: () => settings.setShowPlayerMarkers(!settings.showPlayerMarkers),
          ),
          const SizedBox(width: 4),
          _buildFilterChip(
            label: '生物',
            icon: Icons.pets,
            active: settings.showEntityMarkers,
            color: Colors.greenAccent,
            onTap: () => settings.setShowEntityMarkers(!settings.showEntityMarkers),
          ),
          const SizedBox(width: 4),
          _buildFilterChip(
            label: '容器',
            icon: Icons.inventory_2,
            active: settings.showTileEntityMarkers,
            color: Colors.amberAccent,
            onTap: () => settings.setShowTileEntityMarkers(!settings.showTileEntityMarkers),
          ),
          const SizedBox(width: 4),
          _buildFilterChip(
            label: '网格',
            icon: Icons.grid_on,
            active: settings.showChunkGrid,
            color: Colors.cyanAccent,
            onTap: () => settings.setShowChunkGrid(!settings.showChunkGrid),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    required bool active,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? color : Colors.transparent, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: active ? color : Colors.grey),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: active ? Colors.white : Colors.grey,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSelectionTap(double worldX, double worldZ, {required bool isCtrl}) {
    final sel = widget.selection ?? SelectionModel(dimension: widget.dimension);
    final cx = (worldX / 16).floor();
    final cz = (worldZ / 16).floor();

    if (isCtrl) {
      sel.addChunk(cx, cz);
    } else {
      sel.minX = cx * 16;
      sel.maxX = cx * 16 + 15;
      sel.minZ = cz * 16;
      sel.maxZ = cz * 16 + 15;
      sel.dimension = widget.dimension;
    }
    widget.onSelectionChanged?.call(sel);
  }

  void _updateSelectionBox(Offset start, Offset current) {
    if (widget.selection == null) return;
    final sel = widget.selection!;

    int minX = (start.dx < current.dx ? start.dx : current.dx).floor();
    int maxX = (start.dx > current.dx ? start.dx : current.dx).floor();
    int minZ = (start.dy < current.dy ? start.dy : current.dy).floor();
    int maxZ = (start.dy > current.dy ? start.dy : current.dy).floor();

    sel.minX = minX;
    sel.maxX = maxX;
    sel.minZ = minZ;
    sel.maxZ = maxZ;
    sel.dimension = widget.dimension;
    widget.onSelectionChanged?.call(sel);
  }

  void _translateSelection(SelectionModel base, int dx, int dz) {
    if (widget.selection == null) return;
    final sel = widget.selection!;
    sel.minX = base.minX + dx;
    sel.maxX = base.maxX + dx;
    sel.minZ = base.minZ + dz;
    sel.maxZ = base.maxZ + dz;
    sel.dimension = widget.dimension;
    widget.onSelectionChanged?.call(sel);
  }

  void _handleTap(double worldX, double worldZ, DataManager dm) {
    for (final ent in _cachedEntities) {
      if (ent.dimension == widget.dimension) {
        if ((ent.x - worldX).abs() <= 2.0 && (ent.z - worldZ).abs() <= 2.0) {
          _showEntityInspector(ent, dm);
          return;
        }
      }
    }

    for (final be in _cachedBlockEntities) {
      if (be.dimension == widget.dimension) {
        if ((be.x - worldX).abs() <= 1.5 && (be.z - worldZ).abs() <= 1.5) {
          _showBlockEntityInspector(be, dm);
          return;
        }
      }
    }
  }

  void _showEntityInspector(WorldEntity entity, DataManager dm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Image.asset(
              entity.iconAssetPath,
              width: 32,
              height: 32,
              errorBuilder: (_, __, ___) => Icon(entity.category.icon, color: entity.category.color, size: 28),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(entity.name, style: const TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('类型: ${entity.identifier}'),
            Text('维度: ${_dimName(entity.dimension)}'),
            Text('坐标: X: ${entity.x.toStringAsFixed(1)}, Y: ${entity.y.toStringAsFixed(1)}, Z: ${entity.z.toStringAsFixed(1)}'),
            Text('生命值: ${entity.health.toStringAsFixed(0)} / ${entity.maxHealth.toStringAsFixed(0)}'),
            Text('朝向 Yaw: ${entity.rotationYaw.toStringAsFixed(1)}°'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.flight_takeoff, size: 16),
                    label: const Text('传送玩家'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      dm.teleportPlayer(entity.x, entity.y, entity.z, entity.dimension);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.edit_note, size: 16),
                    label: const Text('编辑 NBT'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.amber[800]),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => EntityNbtEditorScreen(entity: entity)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('删除此生物', style: TextStyle(color: Colors.redAccent)),
            onPressed: () {
              Navigator.pop(ctx);
              EntityService().deleteEntity(dm, entity);
              setState(() {});
            },
          ),
          TextButton(child: const Text('关闭'), onPressed: () => Navigator.pop(ctx)),
        ],
      ),
    );
  }

  void _showBlockEntityInspector(WorldBlockEntity blockEntity, DataManager dm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Image.asset(
              blockEntity.iconAssetPath,
              width: 28,
              height: 28,
              errorBuilder: (_, __, ___) => const Icon(Icons.inventory_2, color: Colors.amberAccent),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(blockEntity.title)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('方块类型: ${blockEntity.blockId}'),
            Text('维度: ${_dimName(blockEntity.dimension)}'),
            Text('坐标: X: ${blockEntity.x}, Y: ${blockEntity.y}, Z: ${blockEntity.z}'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text('进入方块实体 NBT 编辑器'),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => BlockEntityEditorScreen(blockEntity: blockEntity)),
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(child: const Text('关闭'), onPressed: () => Navigator.pop(ctx)),
        ],
      ),
    );
  }

  String _dimName(int dim) {
    if (dim == 1) return '下界 (Nether)';
    if (dim == 2) return '末地 (The End)';
    return '主世界 (Overworld)';
  }

  Widget _buildSelectionHud(SelectionModel sel) {
    final dx = sel.sizeX;
    final dy = sel.sizeY;
    final dz = sel.sizeZ;
    final volume = sel.totalBlocks;
    final chunkCount = sel.totalChunks;

    return Card(
      color: const Color(0xEE1E222B),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.crop_free, color: Colors.amberAccent, size: 18),
                const SizedBox(width: 6),
                Text('选区尺寸: $dx × $dy × $dz 方块', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 4),
            Text('体积: $volume 方块 ($chunkCount 个区块)', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text('Pos1: (${sel.minX}, ${sel.minY}, ${sel.minZ}) -> Pos2: (${sel.maxX}, ${sel.maxY}, ${sel.maxZ})', style: const TextStyle(fontSize: 10, color: Colors.greenAccent)),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset globalPos, double worldX, double worldZ, DataManager dm) {
    final int bx = worldX.floor();
    final int bz = worldZ.floor();
    final int cx = (bx / 16).floor();
    final int cz = (bz / 16).floor();

    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final chunkKeyBytes = ParsedChunkKey.buildKey(cx, cz, widget.dimension, ChunkTag.data3D);
    final chunkKeyB64 = base64Encode(chunkKeyBytes);

    showMenu<dynamic>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<dynamic>>[
        PopupMenuItem<dynamic>(
          enabled: false,
          child: Text(
            '方块: X: $bx, Z: $bz (区块: $cx, $cz)',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<dynamic>(
          child: const ListTile(
            leading: Icon(Icons.flight_takeoff, color: Colors.blueAccent),
            title: Text('传送玩家到此处'),
            dense: true,
          ),
          onTap: () {
            dm.teleportPlayer(worldX, 64.0, worldZ, widget.dimension);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已传送玩家至 X: $bx, Y: 64, Z: $bz')),
            );
          },
        ),
        PopupMenuItem<dynamic>(
          child: const ListTile(
            leading: Icon(Icons.crop_free, color: Colors.orangeAccent),
            title: Text('以此区块建立选区 (16×16)'),
            dense: true,
          ),
          onTap: () {
            if (widget.selection != null) {
              widget.selection!.minX = cx * 16;
              widget.selection!.maxX = cx * 16 + 15;
              widget.selection!.minZ = cz * 16;
              widget.selection!.maxZ = cz * 16 + 15;
              widget.selection!.dimension = widget.dimension;
              widget.onSelectionChanged?.call(widget.selection!);
            }
          },
        ),
        PopupMenuItem<dynamic>(
          child: const ListTile(
            leading: Icon(Icons.account_tree, color: Colors.amberAccent),
            title: Text('查看此区块 LevelDB 数据'),
            dense: true,
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NbtEditorFullScreen(initialKey: chunkKeyB64),
              ),
            );
          },
        ),
        PopupMenuItem<dynamic>(
          child: const ListTile(
            leading: Icon(Icons.copy, color: Colors.cyanAccent),
            title: Text('复制坐标到剪贴板'),
            dense: true,
          ),
          onTap: () {
            Clipboard.setData(ClipboardData(text: '$bx 64 $bz'));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已复制坐标: $bx 64 $bz')),
            );
          },
        ),
      ],
    );
  }
}

/// 实际 Canvas 绘制器 (直绘实体与方块实体原生素材图标)
class _MapCanvasPainter extends CustomPainter {
  final MapViewportController viewport;
  final DataManager dataManager;
  final AppSettings settings;
  final int dimension;
  final MapLayerMode layerMode;
  final SelectionModel? selection;
  final bool isSelectionMode;
  final List<WorldEntity> entities;
  final List<WorldBlockEntity> blockEntities;
  final VoidCallback onRepaintRequest;

  _MapCanvasPainter({
    required this.viewport,
    required this.dataManager,
    required this.settings,
    required this.dimension,
    required this.layerMode,
    this.selection,
    this.isSelectionMode = false,
    required this.entities,
    required this.blockEntities,
    required this.onRepaintRequest,
  }) : super(repaint: viewport);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // 1. 绘制虚空背景
    final bgPaint = Paint()..color = const Color(0xFF14161D);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // 2. 视口裁剪与世界边界求交计算 (消灭远景数十万次空循环)
    final bounds = viewport.getVisibleChunkBounds();
    final worldBounds = dataManager.getWorldBounds(dimension);

    int minCx = bounds['minCx']!;
    int maxCx = bounds['maxCx']!;
    int minCz = bounds['minCz']!;
    int maxCz = bounds['maxCz']!;

    if (worldBounds != null) {
      final wMinCx = worldBounds['minCx']!;
      final wMaxCx = worldBounds['maxCx']!;
      final wMinCz = worldBounds['minCz']!;
      final wMaxCz = worldBounds['maxCz']!;

      if (layerMode != MapLayerMode.slimeChunk) {
        if (minCx < wMinCx) minCx = wMinCx;
        if (maxCx > wMaxCx) maxCx = wMaxCx;
        if (minCz < wMinCz) minCz = wMinCz;
        if (maxCz > wMaxCz) maxCz = wMaxCz;
      } else {
        if (minCx < wMinCx - 16) minCx = wMinCx - 16;
        if (maxCx > wMaxCx + 16) maxCx = wMaxCx + 16;
        if (minCz < wMinCz - 16) minCz = wMinCz - 16;
        if (maxCz > wMaxCz + 16) maxCz = wMaxCz + 16;
      }
    }

    final gpuRenderer = GpuTileRenderer();
    final tilePaint = Paint()..filterQuality = viewport.scale < 0.5 ? FilterQuality.low : FilterQuality.none;

    // 3. 绘制 Region 区域大单面 GPU 纹理瓦片 (1 Region = 16×16 区块 = 256×256 像素，每屏仅需十几个 Draw Call)
    int minRx = (minCx / 16.0).floor();
    int maxRx = (maxCx / 16.0).floor();
    int minRz = (minCz / 16.0).floor();
    int maxRz = (maxCz / 16.0).floor();

    if (minRx <= maxRx && minRz <= maxRz) {
      for (int rx = minRx; rx <= maxRx; rx++) {
        for (int rz = minRz; rz <= maxRz; rz++) {
          final tl = viewport.worldToScreen(Offset(rx * 256.0, rz * 256.0));
          final br = viewport.worldToScreen(Offset((rx + 1) * 256.0, (rz + 1) * 256.0));
          final destRect = Rect.fromPoints(tl, br);

          gpuRenderer.drawRegionTile(
            canvas: canvas,
            regionX: rx,
            regionZ: rz,
            dimension: dimension,
            layerMode: layerMode,
            destRect: destRect,
            dataManager: dataManager,
            paint: tilePaint,
            onTileReady: onRepaintRequest,
          );
        }
      }
    }

    // 史莱姆图层特化高亮叠加
    if (layerMode == MapLayerMode.slimeChunk && dimension == 0 && viewport.scale >= 0.25 && minCx <= maxCx && minCz <= maxCz) {
      for (int cx = minCx; cx <= maxCx; cx++) {
        for (int cz = minCz; cz <= maxCz; cz++) {
          if (GpuTileRenderer.isSlimeChunk(cx, cz)) {
            final tl = viewport.worldToScreen(Offset(cx * 16.0, cz * 16.0));
            final br = viewport.worldToScreen(Offset((cx + 1) * 16.0, (cz + 1) * 16.0));
            final destRect = Rect.fromPoints(tl, br);

            final slimeFillPaint = Paint()..color = const Color(0x444CAF50);
            canvas.drawRect(destRect, slimeFillPaint);
            final slimeBorderPaint = Paint()
              ..color = const Color(0xCC4CAF50)
              ..strokeWidth = 1.0
              ..style = PaintingStyle.stroke;
            canvas.drawRect(destRect, slimeBorderPaint);
          }
        }
      }
    }

    // 4. 绘制网格线 (缩放缩小时自动隐藏区块网格以极大提高渲染性能并消除密集黑线)
    if (settings.showChunkGrid && viewport.scale >= 0.35 && minCx <= maxCx && minCz <= maxCz) {
      final gridPaint = Paint()
        ..color = settings.gridColor
        ..strokeWidth = settings.gridLineWidth
        ..style = PaintingStyle.stroke;

      for (int cx = minCx; cx <= maxCx + 1; cx++) {
        final start = viewport.worldToScreen(Offset(cx * 16.0, minCz * 16.0));
        final end = viewport.worldToScreen(Offset(cx * 16.0, (maxCz + 1) * 16.0));
        canvas.drawLine(start, end, gridPaint);
      }

      for (int cz = minCz; cz <= maxCz + 1; cz++) {
        final start = viewport.worldToScreen(Offset(minCx * 16.0, cz * 16.0));
        final end = viewport.worldToScreen(Offset((maxCx + 1) * 16.0, cz * 16.0));
        canvas.drawLine(start, end, gridPaint);
      }
    }

    // 5. 绘制选区 (Selection Box + 手柄)
    if (selection != null && selection!.dimension == dimension) {
      final sMinX = selection!.normMinX;
      final sMaxX = selection!.normMaxX;
      final sMinZ = selection!.normMinZ;
      final sMaxZ = selection!.normMaxZ;

      final selTopLeft = viewport.worldToScreen(Offset(sMinX.toDouble(), sMinZ.toDouble()));
      final selBottomRight = viewport.worldToScreen(Offset((sMaxX + 1).toDouble(), (sMaxZ + 1).toDouble()));
      final selRect = Rect.fromPoints(selTopLeft, selBottomRight);

      final selFillPaint = Paint()..color = const Color(0x33FFB300);
      canvas.drawRect(selRect, selFillPaint);

      final selBorderPaint = Paint()
        ..color = const Color(0xFFFFB300)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawRect(selRect, selBorderPaint);

      final handlePaint = Paint()..color = const Color(0xFFFFC107);
      const handleRadius = 5.0;
      canvas.drawCircle(selRect.topLeft, handleRadius, handlePaint);
      canvas.drawCircle(selRect.topRight, handleRadius, handlePaint);
      canvas.drawCircle(selRect.bottomLeft, handleRadius, handlePaint);
      canvas.drawCircle(selRect.bottomRight, handleRadius, handlePaint);
    }

    final iconCache = AssetIconCache();
    const iconSize = 22.0;
    final iconPaint = Paint()..filterQuality = FilterQuality.medium;

    // 6. 绘制生物实体高清图标 (含同区块同类生物智能聚合 xN 徽章，大视野 scale < 0.45 自动剔除)
    if (settings.showEntityMarkers && viewport.scale >= 0.45) {
      final isHighResMode = viewport.scale >= 0.8;
      // 按区块与生物类型进行智能聚合
      final Map<String, List<WorldEntity>> entityClusters = {};
      for (final ent in entities) {
        if (ent.dimension == dimension) {
          final clusterKey = '${(ent.x / 16).floor()},${(ent.z / 16).floor()}:${ent.identifier}';
          (entityClusters[clusterKey] ??= []).add(ent);
        }
      }

      for (final cluster in entityClusters.values) {
        final firstEnt = cluster.first;
        final entScreenPos = viewport.worldToScreen(Offset(firstEnt.x, firstEnt.z));
        if (entScreenPos.dx < -30 || entScreenPos.dx > size.width + 30 ||
            entScreenPos.dy < -30 || entScreenPos.dy > size.height + 30) {
          continue;
        }

        if (isHighResMode) {
          final img = iconCache.getEntityIcon(firstEnt.identifier, onReady: onRepaintRequest);
          final destRect = Rect.fromCenter(center: entScreenPos, width: iconSize, height: iconSize);

          if (img != null) {
            final bgPaint = Paint()..color = const Color(0xFFE2E8F0);
            canvas.drawRRect(RRect.fromRectAndRadius(destRect.inflate(2), const Radius.circular(4)), bgPaint);
            canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), destRect, iconPaint);

            final ringPaint = Paint()
              ..color = firstEnt.category.color
              ..strokeWidth = 1.4
              ..style = PaintingStyle.stroke;
            canvas.drawRRect(RRect.fromRectAndRadius(destRect.inflate(2), const Radius.circular(4)), ringPaint);
          } else {
            final dotPaint = Paint()..color = firstEnt.category.color;
            canvas.drawCircle(entScreenPos, 6.0, dotPaint);
            final borderPaint = Paint()
              ..color = Colors.white
              ..strokeWidth = 1.5
              ..style = PaintingStyle.stroke;
            canvas.drawCircle(entScreenPos, 6.0, borderPaint);
          }

          // 如果同区域有多个同类生物，绘制 xN 聚合徽章
          if (cluster.length > 1) {
            final badgeBg = Paint()..color = const Color(0xDD000000);
            final badgePos = entScreenPos + const Offset(7, -9);
            final badgeRect = Rect.fromCenter(center: badgePos, width: 18, height: 12);
            canvas.drawRRect(RRect.fromRectAndRadius(badgeRect, const Radius.circular(3)), badgeBg);
            final textPainter = TextPainter(
              text: TextSpan(
                text: 'x${cluster.length}',
                style: const TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            textPainter.paint(canvas, badgePos - Offset(textPainter.width / 2, textPainter.height / 2));
          } else if (settings.showMarkerLabels) {
            final textPainter = TextPainter(
              text: TextSpan(
                text: firstEnt.name,
                style: const TextStyle(color: Colors.white, fontSize: 10, backgroundColor: Color(0xCC000000)),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            textPainter.paint(canvas, entScreenPos + const Offset(-12, iconSize / 2 + 2));
          }
        } else {
          final dotPaint = Paint()..color = firstEnt.category.color;
          canvas.drawCircle(entScreenPos, 4.0, dotPaint);
        }
      }
    }

    // 7. 绘制方块实体 (刷怪笼等高价值目标优先，容器类按区块智能聚合并限制远景显示)
    if (settings.showTileEntityMarkers && viewport.scale >= 0.45) {
      final isHighResMode = viewport.scale >= 0.8;
      final showCommonContainers = viewport.scale >= 1.0;

      // 区分高价值方块实体与普通海量容器
      final Map<String, List<WorldBlockEntity>> containerClusters = {};
      final List<WorldBlockEntity> highValueEntities = [];

      for (final be in blockEntities) {
        if (be.dimension != dimension) continue;
        final isHighValue = be.blockId.contains('spawner') ||
            be.blockId.contains('command') ||
            be.blockId.contains('portal') ||
            be.blockId.contains('beacon');

        if (isHighValue) {
          highValueEntities.add(be);
        } else if (showCommonContainers) {
          final clusterKey = '${(be.x / 16).floor()},${(be.z / 16).floor()}:${be.blockId}';
          (containerClusters[clusterKey] ??= []).add(be);
        }
      }

      // 绘制高价值方块实体 (刷怪笼等)
      for (final be in highValueEntities) {
        final beScreenPos = viewport.worldToScreen(Offset(be.x + 0.5, be.z + 0.5));
        if (beScreenPos.dx < -30 || beScreenPos.dx > size.width + 30 ||
            beScreenPos.dy < -30 || beScreenPos.dy > size.height + 30) {
          continue;
        }

        if (isHighResMode) {
          final img = iconCache.getBlockIcon(be.blockId, onReady: onRepaintRequest);
          final destRect = Rect.fromCenter(center: beScreenPos, width: iconSize, height: iconSize);

          if (img != null) {
            final bgPaint = Paint()..color = const Color(0xFFE2E8F0);
            canvas.drawRRect(RRect.fromRectAndRadius(destRect.inflate(2), const Radius.circular(4)), bgPaint);
            canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), destRect, iconPaint);

            final borderPaint = Paint()
              ..color = Colors.deepOrangeAccent
              ..strokeWidth = 1.6
              ..style = PaintingStyle.stroke;
            canvas.drawRRect(RRect.fromRectAndRadius(destRect.inflate(2), const Radius.circular(4)), borderPaint);
          } else {
            final squarePaint = Paint()..color = Colors.deepOrange;
            canvas.drawRect(Rect.fromCenter(center: beScreenPos, width: 10, height: 10), squarePaint);
          }
        } else {
          final squarePaint = Paint()..color = Colors.deepOrange;
          canvas.drawRect(Rect.fromCenter(center: beScreenPos, width: 5, height: 5), squarePaint);
        }
      }

      // 绘制聚合后的普通容器 (箱子、漏斗等，同区块同类型仅绘 1 个图标 + xN 徽章)
      for (final cluster in containerClusters.values) {
        final firstBe = cluster.first;
        final beScreenPos = viewport.worldToScreen(Offset(firstBe.x + 0.5, firstBe.z + 0.5));
        if (beScreenPos.dx < -30 || beScreenPos.dx > size.width + 30 ||
            beScreenPos.dy < -30 || beScreenPos.dy > size.height + 30) {
          continue;
        }

        if (isHighResMode) {
          final img = iconCache.getBlockIcon(firstBe.blockId, onReady: onRepaintRequest);
          final destRect = Rect.fromCenter(center: beScreenPos, width: iconSize, height: iconSize);

          if (img != null) {
            final bgPaint = Paint()..color = const Color(0xFFE2E8F0);
            canvas.drawRRect(RRect.fromRectAndRadius(destRect.inflate(2), const Radius.circular(4)), bgPaint);
            canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), destRect, iconPaint);

            final borderPaint = Paint()
              ..color = Colors.amber[800]!
              ..strokeWidth = 1.2
              ..style = PaintingStyle.stroke;
            canvas.drawRRect(RRect.fromRectAndRadius(destRect.inflate(2), const Radius.circular(4)), borderPaint);
          } else {
            final squarePaint = Paint()..color = Colors.amber;
            canvas.drawRect(Rect.fromCenter(center: beScreenPos, width: 10, height: 10), squarePaint);
          }

          if (cluster.length > 1) {
            final badgeBg = Paint()..color = const Color(0xDD000000);
            final badgePos = beScreenPos + const Offset(7, -9);
            final badgeRect = Rect.fromCenter(center: badgePos, width: 18, height: 12);
            canvas.drawRRect(RRect.fromRectAndRadius(badgeRect, const Radius.circular(3)), badgeBg);
            final textPainter = TextPainter(
              text: TextSpan(
                text: 'x${cluster.length}',
                style: const TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            textPainter.paint(canvas, badgePos - Offset(textPainter.width / 2, textPainter.height / 2));
          }
        } else {
          final squarePaint = Paint()..color = Colors.amber;
          canvas.drawRect(Rect.fromCenter(center: beScreenPos, width: 4, height: 4), squarePaint);
        }
      }
    }

    // 8. 绘制玩家标记 (Player Marker，根据视野动态降级)
    if (settings.showPlayerMarkers && dataManager.playerDimension == dimension) {
      final playerScreenPos = viewport.worldToScreen(Offset(dataManager.playerX, dataManager.playerZ));

      final radius = viewport.scale < 0.4 ? 5.0 : 9.0;
      final playerPaint = Paint()..color = Colors.redAccent;
      canvas.drawCircle(playerScreenPos, radius, playerPaint);

      final strokePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = viewport.scale < 0.4 ? 1.2 : 2.2
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(playerScreenPos, radius, strokePaint);

      if (settings.showMarkerLabels && viewport.scale >= 0.5) {
        final textPainter = TextPainter(
          text: const TextSpan(
            text: '玩家',
            style: TextStyle(color: Colors.white, fontSize: 11, backgroundColor: Color(0x88000000), fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, playerScreenPos + const Offset(-12, 12));
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MapCanvasPainter oldDelegate) {
    return oldDelegate.dimension != dimension ||
        oldDelegate.layerMode != layerMode ||
        oldDelegate.selection != selection ||
        oldDelegate.isSelectionMode != isSelectionMode ||
        oldDelegate.entities.length != entities.length ||
        oldDelegate.blockEntities.length != blockEntities.length;
  }
}
