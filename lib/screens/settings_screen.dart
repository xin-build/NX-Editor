import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_settings.dart';
import '../services/storage_service.dart';

/// 综合设置中心界面
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('全局设置中心'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.settings), text: '常规设置'),
            Tab(icon: Icon(Icons.palette), text: '地图渲染与图层'),
            Tab(icon: Icon(Icons.speed), text: 'GPU加速与性能'),
            Tab(icon: Icon(Icons.mouse), text: '操作与控制偏好'),
            Tab(icon: Icon(Icons.folder), text: '路径与版本兼容'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGeneralTab(settings),
          _buildRenderingTab(settings),
          _buildPerformanceTab(settings),
          _buildControlsTab(settings),
          _buildPathsAndLegacyTab(settings),
        ],
      ),
    );
  }

  Widget _buildGeneralTab(AppSettings settings) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('界面主题模式'),
                subtitle: Text(settings.themeMode.label),
                trailing: DropdownButton<AppThemeMode>(
                  value: settings.themeMode,
                  underline: const SizedBox(),
                  items: AppThemeMode.values
                      .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      settings.setThemeMode(v);
                      StorageService().saveSettings();
                    }
                  },
                ),
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('打开存档时自动创建快照备份'),
                subtitle: const Text('在打开 world 文件夹时自动生成 timestamp 备份，防止误操作丢失数据'),
                value: settings.autoBackupOnOpen,
                onChanged: (v) {
                  settings.setAutoBackupOnOpen(v);
                  StorageService().saveSettings();
                },
              ),
              SwitchListTile(
                title: const Text('退出未保存存档前弹出确认'),
                subtitle: const Text('当有未保存的 NBT 或区块修改时提示保存'),
                value: settings.confirmOnExit,
                onChanged: (v) {
                  settings.setConfirmOnExit(v);
                  StorageService().saveSettings();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRenderingTab(AppSettings settings) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('默认渲染图层', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<MapLayerMode>(
                  value: settings.defaultLayer,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: MapLayerMode.values
                      .map((l) => DropdownMenuItem(value: l, child: Text(l.title)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      settings.setDefaultLayer(v);
                      StorageService().saveSettings();
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text('地形起伏阴影强度 (Hillshading): ${settings.hillshadeIntensity.toStringAsFixed(1)}x'),
                Slider(
                  value: settings.hillshadeIntensity,
                  min: 0.0,
                  max: 2.5,
                  divisions: 25,
                  label: settings.hillshadeIntensity.toStringAsFixed(1),
                  onChanged: (v) {
                    settings.setHillshadeIntensity(v);
                    StorageService().saveSettings();
                  },
                ),
                SwitchListTile(
                  title: const Text('平滑光影过渡 (Smooth Shading)'),
                  value: settings.smoothShading,
                  onChanged: (v) {
                    settings.setSmoothShading(v);
                    StorageService().saveSettings();
                  },
                ),
                SwitchListTile(
                  title: const Text('显示区块网格线 (Chunk Grid 16×16)'),
                  value: settings.showChunkGrid,
                  onChanged: (v) {
                    settings.setShowChunkGrid(v);
                    StorageService().saveSettings();
                  },
                ),
                SwitchListTile(
                  title: const Text('显示玩家标记 (Player Marker)'),
                  value: settings.showPlayerMarkers,
                  onChanged: (v) {
                    settings.setShowPlayerMarkers(v);
                    StorageService().saveSettings();
                  },
                ),
                SwitchListTile(
                  title: const Text('显示生物与实体标记 (Entity Markers)'),
                  value: settings.showEntityMarkers,
                  onChanged: (v) {
                    settings.setShowEntityMarkers(v);
                    StorageService().saveSettings();
                  },
                ),
                SwitchListTile(
                  title: const Text('显示方块实体标记 (Tile Entity Markers)'),
                  value: settings.showTileEntityMarkers,
                  onChanged: (v) {
                    settings.setShowTileEntityMarkers(v);
                    StorageService().saveSettings();
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceTab(AppSettings settings) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('GPU 硬件加速纹理渲染 (推荐开启)'),
                subtitle: const Text('将区块生成为 GPU ui.Image 纹理并缓存，实现 60/120fps 超平滑缩放漫游'),
                value: settings.gpuAcceleration,
                onChanged: (v) {
                  settings.setGpuAcceleration(v);
                  StorageService().saveSettings();
                },
              ),
              const Divider(),
              ListTile(
                title: const Text('最大 GPU 瓦片显存缓存容量'),
                subtitle: Text('${settings.maxCachedTiles} 个区块 (LRU 自动淘汰)'),
                trailing: DropdownButton<int>(
                  value: settings.maxCachedTiles,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 400, child: Text('400 (低显存)')),
                    DropdownMenuItem(value: 800, child: Text('800 (推荐)')),
                    DropdownMenuItem(value: 1600, child: Text('1600 (高性能)')),
                    DropdownMenuItem(value: 3200, child: Text('3200 (超大存档)')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      settings.setMaxCachedTiles(v);
                      StorageService().saveSettings();
                    }
                  },
                ),
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('视口包围盒裁剪 (Frustum Culling)'),
                subtitle: const Text('仅渲染屏幕可视区域内的区块，大幅降低计算开销'),
                value: settings.viewportCulling,
                onChanged: (v) {
                  settings.setViewportCulling(v);
                  StorageService().saveSettings();
                },
              ),
              const Divider(),
              ListTile(
                title: const Text('目标帧率限制 (Target FPS)'),
                subtitle: Text(settings.targetFps == 0 ? '不限制' : '${settings.targetFps} FPS'),
                trailing: DropdownButton<int>(
                  value: settings.targetFps,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 60, child: Text('60 FPS')),
                    DropdownMenuItem(value: 120, child: Text('120 FPS (高刷屏)')),
                    DropdownMenuItem(value: 0, child: Text('无限制')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      settings.setTargetFps(v);
                      StorageService().saveSettings();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControlsTab(AppSettings settings) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('PC 鼠标滚轮缩放灵敏度'),
                subtitle: Text('${settings.mouseWheelZoomSpeed.toStringAsFixed(2)}x / 滚轮刻度'),
                trailing: DropdownButton<double>(
                  value: settings.mouseWheelZoomSpeed,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 1.10, child: Text('细腻 (1.10x)')),
                    DropdownMenuItem(value: 1.15, child: Text('标准 (1.15x)')),
                    DropdownMenuItem(value: 1.25, child: Text('快速 (1.25x)')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      settings.setMouseWheelZoomSpeed(v);
                      StorageService().saveSettings();
                    }
                  },
                ),
              ),
              SwitchListTile(
                title: const Text('以鼠标光标所在位置为中心缩放'),
                subtitle: const Text('鼠标滚轮缩放时保持光标下的世界方块坐标不动'),
                value: settings.zoomToCursor,
                onChanged: (v) {
                  settings.setZoomToCursor(v);
                  StorageService().saveSettings();
                },
              ),
              SwitchListTile(
                title: const Text('反转鼠标滚轮缩放方向'),
                value: settings.invertZoom,
                onChanged: (v) {
                  settings.setInvertZoom(v);
                  StorageService().saveSettings();
                },
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('移动端显示悬浮快捷动作轮盘 (FAB Menu)'),
                subtitle: const Text('在屏幕右下角提供快速定位、图层切换和截图按钮'),
                value: settings.showMobileFloatingPad,
                onChanged: (v) {
                  settings.setShowMobileFloatingPad(v);
                  StorageService().saveSettings();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPathsAndLegacyTab(AppSettings settings) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('自定义 Minecraft 存档扫描目录', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    FilledButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加目录'),
                      onPressed: () async {
                        final result = await FilePicker.platform.getDirectoryPath();
                        if (result != null) {
                          settings.addCustomWorldPath(result);
                          StorageService().saveSettings();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (settings.customWorldPaths.isEmpty)
                  const Text('暂无自定义目录（已默认扫描系统 Minecraft 存储路径）', style: TextStyle(color: Colors.grey))
                else
                  ...settings.customWorldPaths.map(
                    (p) => ListTile(
                      leading: const Icon(Icons.folder_open),
                      title: Text(p),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () {
                          settings.removeCustomWorldPath(p);
                          StorageService().saveSettings();
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('启用经典/低版本存档支持 (0.14 - 1.17)'),
                subtitle: const Text('自动检测并兼容 2D 生态群系 (Tag 45)、旧版高度图与早期 SubChunk 结构'),
                value: settings.enableLegacySaveSupport,
                onChanged: (v) {
                  settings.setEnableLegacySaveSupport(v);
                  StorageService().saveSettings();
                },
              ),
              SwitchListTile(
                title: const Text('优先使用旧版生态群系色表'),
                value: settings.preferOldBiomes,
                onChanged: (v) {
                  settings.setPreferOldBiomes(v);
                  StorageService().saveSettings();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
