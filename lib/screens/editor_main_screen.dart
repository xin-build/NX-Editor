import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data/data_manager.dart';
import '../models/app_settings.dart';
import '../models/selection_model.dart';
import '../render/map_viewport_controller.dart';
import '../services/entity_service.dart';
import '../services/terrain_edit_service.dart';
import '../utils/game_data_service.dart';
import '../widgets/adaptive_scaffold.dart';
import '../widgets/entity_finder_dialog.dart';
import '../widgets/id_reference_dialog.dart';
import '../widgets/locator_dialog.dart';
import '../widgets/map_canvas_widget.dart';
import '../widgets/nbt_special_editors/level_dat_editor.dart';
import '../widgets/nbt_special_editors/player_editor.dart';
import '../widgets/nbt_tree_widget.dart';
import '../widgets/selection_panel.dart';
import 'create_flat_screen.dart';
import 'nbt_editor_full_screen.dart';
import 'settings_screen.dart';

/// 核心主编辑器界面 (统一左右面板视觉风格 + 自动定位玩家与维度 + ID字典集成)
class EditorMainScreen extends StatefulWidget {
  const EditorMainScreen({super.key});

  @override
  State<EditorMainScreen> createState() => _EditorMainScreenState();
}

class _EditorMainScreenState extends State<EditorMainScreen> {
  final MapViewportController _viewport = MapViewportController();

  // 当前编辑器状态
  int _dimension = 0; // 0: 主世界, 1: 下界, 2: 末地
  MapLayerMode _layerMode = MapLayerMode.satellite;
  SelectionModel? _selection;
  bool _isSelectionMode = false;

  // 左右面板状态
  bool _showLeftPanel = true;
  String _leftPanelTab = 'overview'; // 'overview' | 'radar' | 'ids' | 'players'

  bool _showRightPanel = true;
  String _rightPanelTab = 'selection'; // 'selection' | 'nbt' | 'player' | 'levelDat'
  String _activeNbtKey = 'level.dat';
  int _mobileNavIndex = 0;
  double _mobilePanelRatio = 0.52; // 移动端底部属性面板高度占比 (18% ~ 90% 可拖拽调节)

  // 快捷 ID 搜索
  final TextEditingController _quickIdSearchCtrl = TextEditingController();
  String _quickIdQuery = '';

  @override
  void initState() {
    super.initState();
    _layerMode = AppSettings().defaultLayer;

    // 关键：启动时立即自动切换至玩家所在维度，并居中定位到玩家坐标
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dm = context.read<DataManager>();
      setState(() {
        _dimension = dm.playerDimension;
      });

      final bounds = dm.getWorldBounds(_dimension);
      if (bounds != null) {
        _viewport.setWorldBounds(bounds['minCx']!, bounds['maxCx']!, bounds['minCz']!, bounds['maxCz']!);
      }

      _viewport.centerOnBlock(dm.playerX, dm.playerZ);
    });
  }

  @override
  void dispose() {
    _quickIdSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DataManager>();

    final isDesktop = AdaptiveScaffold.isDesktop(context);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveChanges,
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): _centerOnPlayer,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): dm.undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): dm.redo,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _openLocatorDialog,
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): _openEntityFinder,
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): _toggleSelectionMode,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _openFullNbtEditor,
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () => _selectAllExploredWorld(dm),
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): _deselectSelection,
        const SingleActivator(LogicalKeyboardKey.delete): _deleteSelectedChunks,
        const SingleActivator(LogicalKeyboardKey.backspace): _deleteSelectedChunks,
        const SingleActivator(LogicalKeyboardKey.escape): _deselectSelection,
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): _toggleGrid,
        const SingleActivator(LogicalKeyboardKey.equal, control: true): () => _viewport.zoom(1.25),
        const SingleActivator(LogicalKeyboardKey.minus, control: true): () => _viewport.zoom(0.8),
        const SingleActivator(LogicalKeyboardKey.add): () => _viewport.zoom(1.25),
        const SingleActivator(LogicalKeyboardKey.numpadAdd): () => _viewport.zoom(1.25),
        const SingleActivator(LogicalKeyboardKey.numpadSubtract): () => _viewport.zoom(0.8),
        const SingleActivator(LogicalKeyboardKey.digit1, alt: true): () => _switchDimension(0),
        const SingleActivator(LogicalKeyboardKey.digit2, alt: true): () => _switchDimension(1),
        const SingleActivator(LogicalKeyboardKey.digit3, alt: true): () => _switchDimension(2),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _viewport.setOffset(_viewport.mapOffset + const Offset(0, 48)),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _viewport.setOffset(_viewport.mapOffset + const Offset(0, -48)),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _viewport.setOffset(_viewport.mapOffset + const Offset(48, 0)),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _viewport.setOffset(_viewport.mapOffset + const Offset(-48, 0)),
      },
      child: Focus(
        autofocus: true,
        child: AdaptiveScaffold(
          appBar: _buildAppBar(dm, isDesktop),
          drawer: _buildDrawer(dm),
          body: _buildBody(dm, isDesktop),
          desktopSideBar: (isDesktop && _showLeftPanel) ? _buildDesktopLeftPanel(dm) : null,
          desktopRightPanel: (isDesktop && _showRightPanel) ? _buildDesktopRightPanel(dm) : null,
          desktopBottomBar: isDesktop ? _buildDesktopStatusBar(dm) : null,
          bottomNavigationBar: isDesktop ? null : _buildMobileBottomNav(),
          floatingActionButton: isDesktop ? null : _buildMobileFab(),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(DataManager dm, bool isDesktop) {
    final worldInfo = dm.currentWorldInfo;
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  worldInfo?.displayName ?? '未命名世界',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (dm.hasUnsavedChanges)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.amber, width: 0.8),
                  ),
                  child: const Text('已修改', style: TextStyle(fontSize: 9, color: Colors.amberAccent)),
                ),
            ],
          ),
          Text(
            '${_dimensionName(_dimension)} | ${_layerMode.title}',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
      actions: isDesktop ? _buildDesktopAppBarActions(dm) : _buildMobileAppBarActions(dm),
    );
  }

  List<Widget> _buildDesktopAppBarActions(DataManager dm) {
    return [
      // 切换左侧面板 (仅在桌面端显示)
      IconButton(
        icon: Icon(_showLeftPanel ? Icons.dock : Icons.dock_outlined),
        tooltip: '切换左侧导航面板',
        onPressed: () => setState(() => _showLeftPanel = !_showLeftPanel),
      ),

      // 定位到玩家 (快捷定位)
      IconButton(
        icon: const Icon(Icons.my_location, color: Colors.greenAccent),
        tooltip: '定位到玩家 (Ctrl+P)',
        onPressed: _centerOnPlayer,
      ),

      // 选区模式快捷激活按钮
      IconButton(
        icon: Icon(
          Icons.crop_free,
          color: _isSelectionMode ? Colors.orangeAccent : Colors.grey,
        ),
        tooltip: _isSelectionMode ? '选区模式已激活 (Ctrl多选, 拖拽框选, Alt移动)' : '进入选区模式 (Ctrl+B)',
        onPressed: _toggleSelectionMode,
      ),

      // 维度切换
      PopupMenuButton<int>(
        icon: const Icon(Icons.public),
        tooltip: '切换维度',
        initialValue: _dimension,
        itemBuilder: (ctx) => const [
          PopupMenuItem(value: 0, child: Text('主世界 (Overworld)')),
          PopupMenuItem(value: 1, child: Text('下界 (Nether)')),
          PopupMenuItem(value: 2, child: Text('末地 (The End)')),
        ],
        onSelected: (dim) => _switchDimension(dim),
      ),

      // 图层切换
      PopupMenuButton<MapLayerMode>(
        icon: const Icon(Icons.layers),
        tooltip: '切换地图图层',
        initialValue: _layerMode,
        itemBuilder: (ctx) => MapLayerMode.values
            .map((l) => PopupMenuItem(value: l, child: Text(l.title)))
            .toList(),
        onSelected: (m) => setState(() => _layerMode = m),
      ),

      // 生物雷达查找器
      IconButton(
        icon: const Icon(Icons.radar, color: Colors.greenAccent),
        tooltip: '生物与实体查找器 (Ctrl+E)',
        onPressed: _openEntityFinder,
      ),

      // Minecraft ID 对照速查
      IconButton(
        icon: const Icon(Icons.menu_book, color: Colors.amberAccent),
        tooltip: 'Minecraft ID 对照字典',
        onPressed: () => showDialog(context: context, builder: (_) => const IdReferenceDialog()),
      ),

      // 全功能 NBT 数据库编辑器
      IconButton(
        icon: const Icon(Icons.account_tree, color: Colors.cyanAccent),
        tooltip: '全功能 NBT 数据库 (Ctrl+N)',
        onPressed: _openFullNbtEditor,
      ),

      // 快捷定位
      IconButton(
        icon: const Icon(Icons.search),
        tooltip: '坐标与地标定位 (Ctrl+F)',
        onPressed: _openLocatorDialog,
      ),

      // 保存
      IconButton(
        icon: Icon(Icons.save, color: dm.hasUnsavedChanges ? Colors.amber : null),
        tooltip: '保存存档 (Ctrl+S)',
        onPressed: _saveChanges,
      ),

      // 撤销 / 重做
      IconButton(
        icon: const Icon(Icons.undo),
        tooltip: '撤销 (Ctrl+Z)',
        onPressed: dm.canUndo ? dm.undo : null,
      ),
      IconButton(
        icon: const Icon(Icons.redo),
        tooltip: '重做 (Ctrl+Y)',
        onPressed: dm.canRedo ? dm.redo : null,
      ),

      // 切换右侧面板
      IconButton(
        icon: Icon(_showRightPanel ? Icons.view_sidebar : Icons.view_sidebar_outlined),
        tooltip: '切换右侧属性面板',
        onPressed: () => setState(() => _showRightPanel = !_showRightPanel),
      ),

      // 设置
      IconButton(
        icon: const Icon(Icons.settings),
        tooltip: '设置',
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
        },
      ),
    ];
  }

  List<Widget> _buildMobileAppBarActions(DataManager dm) {
    return [
      // 定位到玩家 (移动端高频快捷按钮)
      IconButton(
        icon: const Icon(Icons.my_location, color: Colors.greenAccent),
        tooltip: '定位到玩家',
        onPressed: _centerOnPlayer,
      ),

      // 撤销按钮 (直接在顶栏呈现)
      IconButton(
        icon: const Icon(Icons.undo),
        tooltip: '撤销修改 (Ctrl+Z)',
        onPressed: dm.canUndo ? dm.undo : null,
      ),

      // 重做按钮 (直接在顶栏呈现)
      IconButton(
        icon: const Icon(Icons.redo),
        tooltip: '重做修改 (Ctrl+Y)',
        onPressed: dm.canRedo ? dm.redo : null,
      ),

      // 保存按钮 (直接在顶栏呈现，有未保存修改时高亮)
      IconButton(
        icon: Icon(Icons.save, color: dm.hasUnsavedChanges ? Colors.amber : null),
        tooltip: '保存存档 (Ctrl+S)',
        onPressed: _saveChanges,
      ),

      // 移动端折叠更多功能菜单 (彻底防止顶部溢出与重叠)
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        tooltip: '更多功能',
        onSelected: (action) => _handleMobileAction(action, dm),
        itemBuilder: (ctx) => [
          PopupMenuItem(
            value: 'layer',
            child: Row(
              children: [
                const Icon(Icons.layers, size: 20),
                const SizedBox(width: 10),
                Text('地图图层 (${_layerMode.title})'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'selection',
            child: Row(
              children: [
                Icon(Icons.crop_free, color: _isSelectionMode ? Colors.orangeAccent : Colors.grey, size: 20),
                const SizedBox(width: 10),
                Text(_isSelectionMode ? '退出选区模式' : '选区编辑模式'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'panel',
            child: Row(
              children: [
                Icon(Icons.tune, color: _showRightPanel ? Colors.greenAccent : Colors.grey, size: 20),
                const SizedBox(width: 10),
                Text(_showRightPanel ? '收起底部属性面板' : '打开底部属性面板'),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'dim_0',
            child: Row(
              children: [
                Icon(Icons.public, size: 20),
                SizedBox(width: 10),
                Text('切换到: 主世界'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'dim_1',
            child: Row(
              children: [
                Icon(Icons.local_fire_department, color: Colors.redAccent, size: 20),
                SizedBox(width: 10),
                Text('切换到: 下界'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'dim_2',
            child: Row(
              children: [
                Icon(Icons.nightlight_round, color: Colors.purpleAccent, size: 20),
                SizedBox(width: 10),
                Text('切换到: 末地'),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'radar',
            child: Row(
              children: [
                Icon(Icons.radar, color: Colors.greenAccent, size: 20),
                SizedBox(width: 10),
                Text('生物与实体雷达'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'id_dict',
            child: Row(
              children: [
                Icon(Icons.menu_book, color: Colors.amberAccent, size: 20),
                SizedBox(width: 10),
                Text('Minecraft ID 对照字典'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'nbt_full',
            child: Row(
              children: [
                Icon(Icons.account_tree, color: Colors.cyanAccent, size: 20),
                SizedBox(width: 10),
                Text('全功能 NBT 数据库编辑器'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'locator',
            child: Row(
              children: [
                Icon(Icons.search, size: 20),
                SizedBox(width: 10),
                Text('坐标定位跳转'),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'settings',
            child: Row(
              children: [
                Icon(Icons.settings, size: 20),
                SizedBox(width: 10),
                Text('全局设置'),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  void _handleMobileAction(String action, DataManager dm) {
    switch (action) {
      case 'layer':
        showDialog(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('切换地图图层'),
            children: MapLayerMode.values.map((l) => SimpleDialogOption(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(l == _layerMode ? Icons.check_circle : Icons.circle_outlined, size: 18, color: l == _layerMode ? Colors.greenAccent : Colors.grey),
                    const SizedBox(width: 10),
                    Text(l.title, style: TextStyle(fontWeight: l == _layerMode ? FontWeight.bold : FontWeight.normal)),
                  ],
                ),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _layerMode = l);
              },
            )).toList(),
          ),
        );
        break;
      case 'selection':
        _toggleSelectionMode();
        break;
      case 'panel':
        setState(() => _showRightPanel = !_showRightPanel);
        break;
      case 'dim_0':
        _switchDimension(0);
        break;
      case 'dim_1':
        _switchDimension(1);
        break;
      case 'dim_2':
        _switchDimension(2);
        break;
      case 'radar':
        _openEntityFinder();
        break;
      case 'id_dict':
        showDialog(context: context, builder: (_) => const IdReferenceDialog());
        break;
      case 'nbt_full':
        _openFullNbtEditor();
        break;
      case 'locator':
        _openLocatorDialog();
        break;
      case 'undo':
        dm.undo();
        break;
      case 'redo':
        dm.redo();
        break;
      case 'settings':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
        break;
    }
  }

  Widget _buildBody(DataManager dm, bool isDesktop) {
    if (!isDesktop && _mobileNavIndex == 1) {
      final root = dm.getNbtCompound(_activeNbtKey);
      if (root == null) {
        return Center(child: Text('未找到 $_activeNbtKey 的 NBT 数据'));
      }
      return NbtTreeWidget(nbtKey: _activeNbtKey, root: root);
    } else if (!isDesktop && _mobileNavIndex == 2) {
      return const PlayerEditorScreen();
    }

    if (isDesktop) {
      return MapCanvasWidget(
        viewport: _viewport,
        selection: _selection,
        dimension: _dimension,
        layerMode: _layerMode,
        isSelectionMode: _isSelectionMode,
        onSelectionChanged: (s) => setState(() => _selection = s),
      );
    }

    // 移动端：全屏地图 + 底部可拖拽调节高度的自适应浮动属性面板
    final screenHeight = MediaQuery.of(context).size.height;
    final panelHeight = (screenHeight * _mobilePanelRatio).clamp(140.0, screenHeight * 0.90);

    return Stack(
      children: [
        Positioned.fill(
          child: MapCanvasWidget(
            viewport: _viewport,
            selection: _selection,
            dimension: _dimension,
            layerMode: _layerMode,
            isSelectionMode: _isSelectionMode,
            onSelectionChanged: (s) => setState(() => _selection = s),
          ),
        ),
        if (_showRightPanel)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: panelHeight,
            child: _buildMobileAdaptivePanel(dm, screenHeight),
          ),
      ],
    );
  }

  /// 移动端自适应底部可手势拖拽调节高度的悬浮属性面板
  Widget _buildMobileAdaptivePanel(DataManager dm, double screenHeight) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E222B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(color: Colors.black87, blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      child: Column(
        children: [
          // 顶部手势拖拽把手指示条 (支持上下手势自由拖拽调节面板高度，双击快速切换 25% / 55% / 88%)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) {
              setState(() {
                final deltaRatio = -details.primaryDelta! / screenHeight;
                _mobilePanelRatio = (_mobilePanelRatio + deltaRatio).clamp(0.18, 0.90);
              });
            },
            onDoubleTap: () {
              setState(() {
                if (_mobilePanelRatio > 0.70) {
                  _mobilePanelRatio = 0.25;
                } else if (_mobilePanelRatio < 0.35) {
                  _mobilePanelRatio = 0.55;
                } else {
                  _mobilePanelRatio = 0.88;
                }
              });
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white38,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
          ),
          // 标签栏与控制按钮 (支持全屏/半屏/收起)
          Container(
            color: const Color(0xFF161920),
            child: Row(
              children: [
                _buildRightTabButton('选区', 'selection', Icons.crop_free),
                _buildRightTabButton('NBT 树', 'nbt', Icons.account_tree),
                _buildRightTabButton('玩家', 'player', Icons.person),
                _buildRightTabButton('世界', 'levelDat', Icons.settings_applications),
                // 快速高度切换 (全屏展开 / 还原半屏)
                IconButton(
                  icon: Icon(
                    _mobilePanelRatio > 0.70 ? Icons.fullscreen_exit : Icons.fullscreen,
                    size: 20,
                    color: Colors.grey,
                  ),
                  tooltip: _mobilePanelRatio > 0.70 ? '还原半屏 (50%)' : '全屏展开 (88%)',
                  onPressed: () {
                    setState(() {
                      _mobilePanelRatio = _mobilePanelRatio > 0.70 ? 0.50 : 0.88;
                    });
                  },
                ),
                // 收起按钮
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, size: 22, color: Colors.grey),
                  tooltip: '收起属性面板',
                  onPressed: () => setState(() => _showRightPanel = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildRightPanelContent(dm),
          ),
        ],
      ),
    );
  }

  /// ─── 左侧面板 (100% 不透明 HUD 风格，与右侧面板完全统一) ───
  Widget _buildDesktopLeftPanel(DataManager dm) {
    return Container(
      width: 360,
      decoration: const BoxDecoration(
        color: Color(0xFF1E222B),
        border: Border(right: BorderSide(color: Color(0x22FFFFFF))),
      ),
      child: Column(
        children: [
          Container(
            color: const Color(0xFF161920),
            child: Row(
              children: [
                _buildLeftTabButton('概览', 'overview', Icons.explore),
                _buildLeftTabButton('雷达', 'radar', Icons.radar),
                _buildLeftTabButton('ID表', 'ids', Icons.menu_book),
                _buildLeftTabButton('玩家', 'players', Icons.group),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: '隐藏左侧 HUD 面板',
                  onPressed: () => setState(() => _showLeftPanel = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildLeftPanelContent(dm),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftTabButton(String label, String tab, IconData icon) {
    final isSelected = _leftPanelTab == tab;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _leftPanelTab = tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: isSelected ? const Color(0xFF4CAF50) : Colors.transparent, width: 2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isSelected ? const Color(0xFF4CAF50) : Colors.grey),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? const Color(0xFF4CAF50) : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeftPanelContent(DataManager dm) {
    switch (_leftPanelTab) {
      case 'overview':
        return _buildOverviewTab(dm);
      case 'radar':
        return _buildRadarTab(dm);
      case 'ids':
        return _buildIdsTab();
      case 'players':
        return _buildPlayersTab(dm);
      default:
        return const SizedBox();
    }
  }

  Widget _buildOverviewTab(DataManager dm) {
    final bounds = dm.getWorldBounds(_dimension);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 世界探索限定范围卡片
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF252A36),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.explore, size: 18, color: Color(0xFF4CAF50)),
                  const SizedBox(width: 8),
                  const Text('世界探索限定范围', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 10),
              Text('当前维度: ${_dimensionName(_dimension)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              if (bounds != null) ...[
                Text('X 坐标: ${bounds['minCx']! * 16} ~ ${(bounds['maxCx']! + 1) * 16 - 1}', style: const TextStyle(fontSize: 12)),
                Text('Z 坐标: ${bounds['minCz']! * 16} ~ ${(bounds['maxCz']! + 1) * 16 - 1}', style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Text('已生成区块: ${bounds['totalChunks']} 个区块', style: const TextStyle(fontSize: 12, color: Color(0xFF4CAF50), fontWeight: FontWeight.bold)),
              ] else ...[
                const Text('该维度暂无已生成区块', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.center_focus_strong, size: 14),
                      label: const Text('居中世界', style: TextStyle(fontSize: 12)),
                      onPressed: bounds != null ? () => _viewport.centerOnWorld() : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.select_all, size: 14),
                      label: const Text('全选范围', style: TextStyle(fontSize: 12)),
                      onPressed: bounds != null ? () => _selectAllExploredWorld(dm) : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 快捷功能入口
        const Text('核心功能快捷入口', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 8),

        _buildSidebarActionTile(
          icon: Icons.my_location,
          color: Colors.greenAccent,
          title: '定位到玩家 (~local_player)',
          subtitle: 'X: ${dm.playerX.toStringAsFixed(1)}, Z: ${dm.playerZ.toStringAsFixed(1)} (${_dimensionName(dm.playerDimension)})',
          onTap: _centerOnPlayer,
        ),
        const SizedBox(height: 8),

        _buildSidebarActionTile(
          icon: Icons.public,
          color: Colors.cyanAccent,
          title: '世界参数设置 (level.dat)',
          subtitle: '游戏模式/种子/世界时间/规则',
          onTap: () {
            setState(() {
              _showRightPanel = true;
              _rightPanelTab = 'levelDat';
            });
          },
        ),
        const SizedBox(height: 8),

        _buildSidebarActionTile(
          icon: Icons.crop_free,
          color: Colors.orangeAccent,
          title: '选区与地形修改工具',
          subtitle: '方块替换/批量删除/群系编辑',
          onTap: () {
            setState(() {
              _showRightPanel = true;
              _rightPanelTab = 'selection';
            });
          },
        ),
      ],
    );
  }

  Widget _buildRadarTab(DataManager dm) {
    final entities = EntityService().parseAllEntities(dm).where((e) => e.dimension == _dimension).toList();
    final blockEntities = EntityService().parseAllBlockEntities(dm).where((b) => b.dimension == _dimension).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Text('${_dimensionName(_dimension)} 实体 (${entities.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 14),
              label: const Text('高级雷达', style: TextStyle(fontSize: 11)),
              onPressed: _openEntityFinder,
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...entities.take(15).map((e) => ListTile(
          dense: true,
          leading: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Image.asset(e.iconAssetPath, width: 22, height: 22, errorBuilder: (_, __, ___) => Icon(e.category.icon, color: e.category.color, size: 18)),
          ),
          title: Text(e.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          subtitle: Text('X: ${e.x.toStringAsFixed(1)}, Z: ${e.z.toStringAsFixed(1)} | HP: ${e.health.toStringAsFixed(0)}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          trailing: IconButton(
            icon: const Icon(Icons.gps_fixed, size: 16),
            tooltip: '定位',
            onPressed: () => _viewport.centerOnBlock(e.x, e.z),
          ),
        )),
        const Divider(height: 20),
        Text('${_dimensionName(_dimension)} 方块实体 (${blockEntities.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        ...blockEntities.take(15).map((b) => ListTile(
          dense: true,
          leading: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Image.asset(b.iconAssetPath, width: 20, height: 20, errorBuilder: (_, __, ___) => const Icon(Icons.inventory_2, color: Colors.amber, size: 16)),
          ),
          title: Text(b.title, style: const TextStyle(fontSize: 12)),
          subtitle: Text('X: ${b.x}, Y: ${b.y}, Z: ${b.z}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          trailing: IconButton(
            icon: const Icon(Icons.gps_fixed, size: 16),
            tooltip: '定位',
            onPressed: () => _viewport.centerOnBlock(b.x.toDouble(), b.z.toDouble()),
          ),
        )),
      ],
    );
  }

  Widget _buildIdsTab() {
    final gds = GameDataService();
    final all = [...gds.blocks, ...gds.items, ...gds.entities];
    final filtered = all.where((e) {
      if (_quickIdQuery.isEmpty) return true;
      return e.name.toLowerCase().contains(_quickIdQuery) || e.id.toLowerCase().contains(_quickIdQuery);
    }).take(30).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _quickIdSearchCtrl,
            decoration: InputDecoration(
              hintText: '快捷检索方块/物品/生物 ID...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.open_in_full, size: 16),
                tooltip: '打开完整分类字典',
                onPressed: () => showDialog(context: context, builder: (_) => const IdReferenceDialog()),
              ),
            ),
            onChanged: (v) => setState(() => _quickIdQuery = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final item = filtered[i];
              final fullId = item.id.startsWith('minecraft:') ? item.id : 'minecraft:${item.id}';
              return ListTile(
                dense: true,
                title: Text(item.name.isNotEmpty ? item.name : item.id, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text(fullId, style: const TextStyle(fontSize: 10, color: Colors.cyanAccent)),
                trailing: IconButton(
                  icon: const Icon(Icons.copy, size: 15),
                  tooltip: '复制 ID',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: fullId));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制: $fullId'), duration: const Duration(seconds: 1)));
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPlayersTab(DataManager dm) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ListTile(
          leading: const Icon(Icons.person, color: Colors.blueAccent),
          title: const Text('本地主玩家 (~local_player)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: Text('维度: ${_dimensionName(dm.playerDimension)} | X: ${dm.playerX.toStringAsFixed(1)}, Z: ${dm.playerZ.toStringAsFixed(1)}', style: const TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.edit, size: 16),
          onTap: () {
            setState(() {
              _showRightPanel = true;
              _rightPanelTab = 'player';
            });
          },
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text('多人联机玩家', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        ...dm.getNetworkPlayerKeys().map(
          (k) => ListTile(
            leading: const Icon(Icons.sports_esports, size: 20, color: Colors.tealAccent),
            title: Text(k, style: const TextStyle(fontSize: 12)),
            dense: true,
            onTap: () {
              setState(() {
                _activeNbtKey = k;
                _showRightPanel = true;
                _rightPanelTab = 'nbt';
              });
            },
          ),
        ),
        if (dm.getNetworkPlayerKeys().isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text('当前存档中暂无其他联机玩家数据', style: TextStyle(color: Colors.grey, fontSize: 11)),
          ),
      ],
    );
  }

  Widget _buildSidebarActionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      color: const Color(0xFF252A36),
      child: ListTile(
        leading: Icon(icon, color: color, size: 22),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        trailing: const Icon(Icons.chevron_right, size: 16),
        onTap: onTap,
      ),
    );
  }

  void _selectAllExploredWorld(DataManager dm) {
    final bounds = dm.getWorldBounds(_dimension);
    if (bounds != null) {
      final sel = _selection ?? SelectionModel(dimension: _dimension);
      sel.minX = bounds['minCx']! * 16;
      sel.maxX = (bounds['maxCx']! + 1) * 16 - 1;
      sel.minZ = bounds['minCz']! * 16;
      sel.maxZ = (bounds['maxCz']! + 1) * 16 - 1;
      sel.dimension = _dimension;
      setState(() {
        _selection = sel;
        _showRightPanel = true;
        _rightPanelTab = 'selection';
      });
    }
  }

  /// ─── 右侧属性面板 ───
  Widget _buildDesktopRightPanel(DataManager dm) {
    return Container(
      width: 380,
      decoration: BoxDecoration(
        color: const Color(0xFF1E222B),
        border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      ),
      child: Column(
        children: [
          Container(
            color: const Color(0xFF161920),
            child: Row(
              children: [
                _buildRightTabButton('选区', 'selection', Icons.crop_free),
                _buildRightTabButton('NBT 树', 'nbt', Icons.account_tree),
                _buildRightTabButton('玩家', 'player', Icons.person),
                _buildRightTabButton('世界', 'levelDat', Icons.settings_applications),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: '隐藏右侧面板',
                  onPressed: () => setState(() => _showRightPanel = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildRightPanelContent(dm),
          ),
        ],
      ),
    );
  }

  Widget _buildRightTabButton(String label, String tab, IconData icon) {
    final isSelected = _rightPanelTab == tab;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _rightPanelTab = tab;
            if (_mobilePanelRatio < 0.35) {
              _mobilePanelRatio = 0.52;
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: isSelected ? const Color(0xFF4CAF50) : Colors.transparent, width: 2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isSelected ? const Color(0xFF4CAF50) : Colors.grey),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? const Color(0xFF4CAF50) : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRightPanelContent(DataManager dm) {
    switch (_rightPanelTab) {
      case 'selection':
        return SelectionPanel(
          selection: _selection ?? SelectionModel(dimension: _dimension),
          onSelectionModified: () => setState(() {}),
        );
      case 'nbt':
        final root = dm.getNbtCompound(_activeNbtKey);
        if (root == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('未找到 NBT 数据', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.account_tree),
                  label: const Text('打开全功能 NBT 数据库'),
                  onPressed: _openFullNbtEditor,
                ),
              ],
            ),
          );
        }
        return NbtTreeWidget(nbtKey: _activeNbtKey, root: root);
      case 'player':
        return const PlayerEditorScreen();
      case 'levelDat':
        return const LevelDatEditorScreen();
      default:
        return const SizedBox();
    }
  }

  Widget _buildDesktopStatusBar(DataManager dm) {
    return ListenableBuilder(
      listenable: _viewport,
      builder: (context, _) {
        final bx = _viewport.isCursorInside ? _viewport.cursorWorldX.floor() : 0;
        final bz = _viewport.isCursorInside ? _viewport.cursorWorldZ.floor() : 0;
        final cx = (bx / 16).floor();
        final cz = (bz / 16).floor();
        final zoomPct = (_viewport.scale * 100).toStringAsFixed(0);

        return Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: const Color(0xFF14161D),
          child: Row(
            children: [
              const Icon(Icons.mouse, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                _viewport.isCursorInside
                    ? '光标坐标: X: $bx, Z: $bz (区块: $cx, $cz)'
                    : '光标坐标: --',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(width: 20),
              const Icon(Icons.zoom_in, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Text('缩放率: $zoomPct%', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(width: 20),
              const Icon(Icons.dns, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Text('已加载条目: ${dm.rawEntries.length} | 已生成区块: ${dm.existingChunks.length}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const Spacer(),
              if (dm.lastModifiedKey != null)
                Text('最后修改: ${dm.lastModifiedKey} (${dm.lastModifiedType})', style: const TextStyle(fontSize: 11, color: Colors.amberAccent)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDrawer(DataManager dm) {
    return Drawer(
      child: ListView(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF1E222B)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(dm.currentWorldInfo?.displayName ?? 'Minecraft 存档', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('种子: ${dm.currentWorldInfo?.seed ?? 0}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.radar, color: Colors.greenAccent),
            title: const Text('生物与实体雷达查找器'),
            onTap: () {
              Navigator.pop(context);
              _openEntityFinder();
            },
          ),
          ListTile(
            leading: const Icon(Icons.menu_book, color: Colors.amberAccent),
            title: const Text('Minecraft ID 对照字典速查'),
            onTap: () {
              Navigator.pop(context);
              showDialog(context: context, builder: (_) => const IdReferenceDialog());
            },
          ),
          ListTile(
            leading: const Icon(Icons.account_tree, color: Colors.cyanAccent),
            title: const Text('全功能 NBT 数据库编辑器'),
            onTap: () {
              Navigator.pop(context);
              _openFullNbtEditor();
            },
          ),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('世界规则与属性 (level.dat)'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const Scaffold(appBar: PreferredSize(preferredSize: Size.fromHeight(56), child: CustomAppBar()), body: LevelDatEditorScreen())));
            },
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('玩家背包与属性 (~local_player)'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const Scaffold(appBar: PreferredSize(preferredSize: Size.fromHeight(56), child: CustomAppBar()), body: PlayerEditorScreen())));
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_box),
            title: const Text('创建自定义超平坦世界'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateFlatScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('全局设置'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBottomNav() {
    return NavigationBar(
      selectedIndex: _mobileNavIndex,
      onDestinationSelected: (idx) => setState(() => _mobileNavIndex = idx),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.map), label: '地图'),
        NavigationDestination(icon: Icon(Icons.account_tree), label: 'NBT'),
        NavigationDestination(icon: Icon(Icons.person), label: '玩家'),
      ],
    );
  }

  Widget _buildMobileFab() {
    return FloatingActionButton(
      tooltip: '定位到玩家',
      onPressed: _centerOnPlayer,
      child: const Icon(Icons.my_location),
    );
  }

  void _centerOnPlayer() {
    final dm = context.read<DataManager>();
    if (_dimension != dm.playerDimension) {
      setState(() {
        _dimension = dm.playerDimension;
        final bounds = dm.getWorldBounds(_dimension);
        if (bounds != null) {
          _viewport.setWorldBounds(bounds['minCx']!, bounds['maxCx']!, bounds['minCz']!, bounds['maxCz']!);
        }
      });
    }
    _viewport.centerOnBlock(dm.playerX, dm.playerZ);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已定位至玩家: X: ${dm.playerX.toStringAsFixed(1)}, Z: ${dm.playerZ.toStringAsFixed(1)} (${_dimensionName(dm.playerDimension)})'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _openEntityFinder() {
    showDialog(
      context: context,
      builder: (ctx) => EntityFinderDialog(
        viewport: _viewport,
        dimension: _dimension,
        onDimensionChanged: (dim) => setState(() => _dimension = dim),
      ),
    );
  }

  void _openFullNbtEditor() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NbtEditorFullScreen()),
    );
  }

  void _openLocatorDialog() {
    showDialog(
      context: context,
      builder: (ctx) => LocatorDialog(
        viewport: _viewport,
        dataManager: context.read<DataManager>(),
        onDimensionChanged: (dim) => setState(() => _dimension = dim),
      ),
    );
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (_isSelectionMode && _selection == null) {
        _selection = SelectionModel(dimension: _dimension);
      }
      _showRightPanel = true;
      _rightPanelTab = 'selection';
    });
  }

  void _saveChanges() async {
    final dm = context.read<DataManager>();
    final ok = await dm.saveChanges();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '存档保存成功！已写回 LevelDB 物理文件' : '保存失败: ${dm.error ?? "未知错误"}'),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _deselectSelection() {
    setState(() {
      _selection = null;
      _isSelectionMode = false;
    });
  }

  void _toggleGrid() {
    final settings = AppSettings();
    setState(() {
      settings.setShowChunkGrid(!settings.showChunkGrid);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(settings.showChunkGrid ? '已开启区块网格线 (Ctrl+G)' : '已隐藏区块网格线 (Ctrl+G)'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _switchDimension(int dim) {
    final dm = context.read<DataManager>();
    setState(() {
      _dimension = dim;
      final bounds = dm.getWorldBounds(_dimension);
      if (bounds != null) {
        _viewport.setWorldBounds(bounds['minCx']!, bounds['maxCx']!, bounds['minCz']!, bounds['maxCz']!);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已切换至: ${_dimensionName(dim)} (Alt+${dim + 1})'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _deleteSelectedChunks() async {
    final dm = context.read<DataManager>();
    if (_selection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先框选或选择要删除的区块范围 (Ctrl+B 或拖拽选区)')),
      );
      return;
    }

    final chunkCount = _selection!.totalChunks;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('确认删除选区内的区块？'),
          ],
        ),
        content: Text('即将永久删除选区内 $chunkCount 个区块及其包含的所有地形、生物与方块实体数据。\n\n此操作支持 Ctrl+Z 撤销恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除 (Delete)'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final count = TerrainEditService().deleteChunks(selection: _selection!, dm: dm);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功删除选区内的 $count 个区块及其数据！可在顶部撤销。'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  String _dimensionName(int dim) {
    switch (dim) {
      case 0: return '主世界';
      case 1: return '下界';
      case 2: return '末地';
      default: return '未知维度';
    }
  }
}

class CustomAppBar extends StatelessWidget {
  const CustomAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(title: const Text('属性编辑器'));
  }
}
