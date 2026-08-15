import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data/data_manager.dart';
import '../models/app_settings.dart';
import '../models/selection_model.dart';
import '../nbt/structure_serializer.dart';
import '../render/highres_exporter.dart';
import '../render/map_layer_types.dart';
import '../services/terrain_edit_service.dart';
import '../utils/game_data_service.dart';

/// 选区操作与属性面板 (支持负数坐标输入、原版/BTR快捷操作)
class SelectionPanel extends StatefulWidget {
  final SelectionModel selection;
  final VoidCallback? onSelectionModified;
  final VoidCallback? onClose;

  const SelectionPanel({
    super.key,
    required this.selection,
    this.onSelectionModified,
    this.onClose,
  });

  @override
  State<SelectionPanel> createState() => _SelectionPanelState();
}

class _SelectionPanelState extends State<SelectionPanel> {
  final _minXCtrl = TextEditingController();
  final _maxXCtrl = TextEditingController();
  final _minZCtrl = TextEditingController();
  final _maxZCtrl = TextEditingController();
  final _minYCtrl = TextEditingController();
  final _maxYCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant SelectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅在坐标发生实质改变且当前未处于输入焦点时同步，避免打字中断
    if (oldWidget.selection.minX != widget.selection.minX ||
        oldWidget.selection.maxX != widget.selection.maxX ||
        oldWidget.selection.minZ != widget.selection.minZ ||
        oldWidget.selection.maxZ != widget.selection.maxZ ||
        oldWidget.selection.minY != widget.selection.minY ||
        oldWidget.selection.maxY != widget.selection.maxY) {
      _syncControllers();
    }
  }

  void _syncControllers() {
    _minXCtrl.text = widget.selection.minX.toString();
    _maxXCtrl.text = widget.selection.maxX.toString();
    _minZCtrl.text = widget.selection.minZ.toString();
    _maxZCtrl.text = widget.selection.maxZ.toString();
    _minYCtrl.text = widget.selection.minY.toString();
    _maxYCtrl.text = widget.selection.maxY.toString();
  }

  @override
  void dispose() {
    _minXCtrl.dispose();
    _maxXCtrl.dispose();
    _minZCtrl.dispose();
    _maxZCtrl.dispose();
    _minYCtrl.dispose();
    _maxYCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DataManager>();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E222B),
        border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 面板标题
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF282E3A),
            child: Row(
              children: [
                const Icon(Icons.crop_free, color: Colors.orangeAccent),
                const SizedBox(width: 8),
                const Text('选区操作与地形编辑', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                if (widget.onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: widget.onClose,
                  ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 选区统计 HUD
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x33FFB300),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('尺寸: ${widget.selection.sizeX} × ${widget.selection.sizeY} × ${widget.selection.sizeZ} 方块', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('涵盖区块: ${widget.selection.totalChunks} 个区块 (${widget.selection.chunkCountX} × ${widget.selection.chunkCountZ})'),
                      const SizedBox(height: 4),
                      Text('总方块体积: ${widget.selection.totalBlocks} Blocks', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 快捷选区操作按钮
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.public, size: 14),
                      label: const Text('全选已探索世界', style: TextStyle(fontSize: 11)),
                      onPressed: () => _selectAllExploredWorld(dm),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.person_pin, size: 14),
                      label: const Text('选玩家所在区块', style: TextStyle(fontSize: 11)),
                      onPressed: () => _selectPlayerChunk(dm),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.zoom_out_map, size: 14),
                      label: const Text('扩大 1 区块 (+16)', style: TextStyle(fontSize: 11)),
                      onPressed: () => _expandSelection(16),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.zoom_in_map, size: 14),
                      label: const Text('收缩 1 区块 (-16)', style: TextStyle(fontSize: 11)),
                      onPressed: () => _expandSelection(-16),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 坐标输入 (完美支持负数如 -64, -1000)
                const Text('选区边界 (Pos1 / Pos2)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildCoordField('Min X', _minXCtrl, (v) => widget.selection.minX = v)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildCoordField('Max X', _maxXCtrl, (v) => widget.selection.maxX = v)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildCoordField('Min Z', _minZCtrl, (v) => widget.selection.minZ = v)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildCoordField('Max Z', _maxZCtrl, (v) => widget.selection.maxZ = v)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildCoordField('Min Y (高度)', _minYCtrl, (v) => widget.selection.minY = v)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildCoordField('Max Y (高度)', _maxYCtrl, (v) => widget.selection.maxY = v)),
                  ],
                ),
                const SizedBox(height: 20),

                // 批量修改操作
                const Text('批量地形与区块操作', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),

                _buildOperationTile(
                  icon: Icons.find_replace,
                  color: Colors.blueAccent,
                  title: '方块查找与替换',
                  subtitle: '在选区内将指定方块批量替换为另一方块',
                  onTap: () => _openSearchAndReplace(context, dm),
                ),
                const SizedBox(height: 8),

                _buildOperationTile(
                  icon: Icons.delete_forever,
                  color: Colors.redAccent,
                  title: '批量删除 / 重置区块',
                  subtitle: '将选区内所有区块从数据库完全删除',
                  onTap: () => _openDeleteChunks(context, dm),
                ),
                const SizedBox(height: 8),

                _buildOperationTile(
                  icon: Icons.forest,
                  color: Colors.greenAccent,
                  title: '修改生态群系 (Biome)',
                  subtitle: '批量修改选区内所有群系 ID',
                  onTap: () => _openChangeBiome(context, dm),
                ),
                const SizedBox(height: 8),

                _buildOperationTile(
                  icon: Icons.file_download,
                  color: Colors.orangeAccent,
                  title: '导出为 .mcstructure 结构',
                  subtitle: '导出为可用于基岩版结构方块的标准结构文件',
                  onTap: () => _exportStructure(context, dm),
                ),
                const SizedBox(height: 8),

                _buildOperationTile(
                  icon: Icons.camera_alt,
                  color: Colors.purpleAccent,
                  title: '导出高清卫星地图 (PNG / Picer)',
                  subtitle: '将选区导出为高分辨率超清地图图片',
                  onTap: () => _exportHighResMap(context, dm),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectAllExploredWorld(DataManager dm) {
    final bounds = dm.getWorldBounds(widget.selection.dimension);
    if (bounds != null) {
      widget.selection.minX = bounds['minCx']! * 16;
      widget.selection.maxX = (bounds['maxCx']! + 1) * 16 - 1;
      widget.selection.minZ = bounds['minCz']! * 16;
      widget.selection.maxZ = (bounds['maxCz']! + 1) * 16 - 1;
      _syncControllers();
      widget.onSelectionModified?.call();
    }
  }

  void _selectPlayerChunk(DataManager dm) {
    final cx = (dm.playerX / 16).floor();
    final cz = (dm.playerZ / 16).floor();
    widget.selection.minX = cx * 16;
    widget.selection.maxX = cx * 16 + 15;
    widget.selection.minZ = cz * 16;
    widget.selection.maxZ = cz * 16 + 15;
    widget.selection.dimension = dm.playerDimension;
    _syncControllers();
    widget.onSelectionModified?.call();
  }

  void _expandSelection(int delta) {
    widget.selection.minX -= delta;
    widget.selection.maxX += delta;
    widget.selection.minZ -= delta;
    widget.selection.maxZ += delta;
    _syncControllers();
    widget.onSelectionModified?.call();
  }

  Widget _buildCoordField(String label, TextEditingController ctrl, Function(int) onChanged) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: false),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^-?[0-9]*')),
      ],
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: (val) {
        if (val == '-' || val.isEmpty) return; // 允许正在输入负号
        final parsed = int.tryParse(val);
        if (parsed != null) {
          onChanged(parsed);
          widget.onSelectionModified?.call();
        }
      },
    );
  }

  Widget _buildOperationTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      color: const Color(0xFF222630),
      child: ListTile(
        leading: Icon(icon, color: color, size: 24),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        trailing: const Icon(Icons.chevron_right, size: 16),
        onTap: onTap,
      ),
    );
  }

  void _openSearchAndReplace(BuildContext context, DataManager dm) {
    final fromCtrl = TextEditingController(text: 'minecraft:stone');
    final toCtrl = TextEditingController(text: 'minecraft:diamond_block');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('方块查找与替换'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: fromCtrl,
              decoration: const InputDecoration(labelText: '原方块 ID (From)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: toCtrl,
              decoration: const InputDecoration(labelText: '替换为方块 ID (To)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final count = await TerrainEditService().searchAndReplace(
                selection: widget.selection,
                fromBlockId: fromCtrl.text.trim(),
                toBlockId: toCtrl.text.trim(),
                dm: dm,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('查找替换完成！共修改了 $count 个方块。')),
                );
              }
            },
            child: const Text('执行替换'),
          ),
        ],
      ),
    );
  }

  void _openDeleteChunks(BuildContext context, DataManager dm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认批量删除选区区块？', style: TextStyle(color: Colors.redAccent)),
        content: Text('即将从数据库中永久移除选区内的 ${widget.selection.totalChunks} 个区块。\nMinecraft 再次进入时将重新生成这些区块。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              final count = TerrainEditService().deleteChunks(
                selection: widget.selection,
                dm: dm,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已成功删除 $count 个区块！')),
                );
              }
            },
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
  }

  void _openChangeBiome(BuildContext context, DataManager dm) {
    final gds = GameDataService();
    final allBiomes = gds.biomes;
    int selectedBiomeId = 1; // Plains
    String searchQuery = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filtered = allBiomes.where((b) {
            if (searchQuery.isEmpty) return true;
            final q = searchQuery.toLowerCase();
            return b.name.toLowerCase().contains(q) ||
                b.id.toLowerCase().contains(q) ||
                b.numId.contains(q);
          }).toList();

          final currentSelected = gds.biomeByNumId(selectedBiomeId.toString());

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.forest, color: Colors.greenAccent),
                SizedBox(width: 8),
                Text('批量修改生态群系 (全量 ID 表)'),
              ],
            ),
            content: SizedBox(
              width: 440,
              height: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 搜索栏
                  TextField(
                    decoration: InputDecoration(
                      hintText: '搜索群系 (如: 樱花 / 192 / plains / 下界 / 恶地)...',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (v) => setDialogState(() => searchQuery = v.trim()),
                  ),
                  const SizedBox(height: 12),

                  // 当前选中提示
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252A36),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: MapLayerConfig.biomeToColor(selectedBiomeId),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '当前选择: ${currentSelected?.name ?? "平原"} (ID: $selectedBiomeId / ${currentSelected?.id ?? "plains"})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 群系全量列表
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, idx) {
                          final b = filtered[idx];
                          final numId = int.tryParse(b.numId) ?? 0;
                          final isSelected = numId == selectedBiomeId;
                          final color = MapLayerConfig.biomeToColor(numId);

                          return ListTile(
                            dense: true,
                            selected: isSelected,
                            selectedTileColor: const Color(0x334CAF50),
                            leading: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24),
                              ),
                            ),
                            title: Text(b.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                            subtitle: Text('ID: ${b.numId} (${b.id})', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            trailing: isSelected ? const Icon(Icons.check, color: Colors.greenAccent, size: 18) : null,
                            onTap: () {
                              setDialogState(() {
                                selectedBiomeId = numId;
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: Text('应用群系 (ID: $selectedBiomeId)'),
                onPressed: () {
                  Navigator.pop(ctx);
                  final count = TerrainEditService().changeBiome(
                    selection: widget.selection,
                    targetBiomeId: selectedBiomeId,
                    dm: dm,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已修改 $count 个区块的生态群系为 ${currentSelected?.name ?? selectedBiomeId}！')),
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _exportStructure(BuildContext context, DataManager dm) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '导出 .mcstructure 结构文件',
      fileName: 'exported_structure.mcstructure',
      type: FileType.custom,
      allowedExtensions: ['mcstructure'],
    );
    if (result != null) {
      await StructureSerializer.exportSelectionToStructureFile(
        selection: widget.selection,
        dataManager: dm,
        outputPath: result,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('结构文件已成功导出: $result')),
        );
      }
    }
  }

  void _exportHighResMap(BuildContext context, DataManager dm) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '导出高清卫星地图 PNG',
      fileName: 'world_map_hd.png',
      type: FileType.custom,
      allowedExtensions: ['png'],
    );
    if (result != null) {
      await HighResExporter.exportMapToPng(
        selection: widget.selection,
        dataManager: dm,
        layerMode: AppSettings().defaultLayer,
        targetFilePath: result,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('高清地图已导出: $result')),
        );
      }
    }
  }
}
