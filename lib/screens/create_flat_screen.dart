import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/flat_world_generator.dart';
import '../services/storage_service.dart';
import '../utils/game_data_service.dart';

/// 创建自定义超平坦世界界面
class CreateFlatScreen extends StatefulWidget {
  const CreateFlatScreen({super.key});

  @override
  State<CreateFlatScreen> createState() => _CreateFlatScreenState();
}

class _CreateFlatScreenState extends State<CreateFlatScreen> {
  final _nameCtrl = TextEditingController(text: '我的超平坦世界');
  int _gameMode = 1; // 创造
  final int _difficulty = 1; // 简单
  int _biomeId = 1; // 平原
  bool _cavesAndCliffs = true; // 1.18+

  List<FlatLayerConfig> _layers = FlatWorldGenerator.classicPreset;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  int get _totalHeight => _layers.fold(0, (sum, l) => sum + l.count);

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    if (!isDesktop) {
      // 移动端：双 Tab 标签页布局 (基础参数与预设 / 自定义地层结构)
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('新建超平坦世界'),
            actions: [
              FilledButton.icon(
                icon: const Icon(Icons.check, size: 18),
                label: const Text('立即生成'),
                onPressed: _generateWorld,
              ),
              const SizedBox(width: 8),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.tune), text: '基础属性与预设'),
                Tab(icon: Icon(Icons.layers), text: '地层结构'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _buildParametersView(),
              _buildLayersView(),
            ],
          ),
        ),
      );
    }

    // 桌面端：双栏分屏布局
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建自定义超平坦世界'),
        actions: [
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('立即生成'),
            onPressed: _generateWorld,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          // 左侧参数配置
          SizedBox(
            width: 360,
            child: _buildParametersView(),
          ),

          const VerticalDivider(width: 1),

          // 右侧自定义地层结构列表
          Expanded(
            child: _buildLayersView(),
          ),
        ],
      ),
    );
  }

  Widget _buildParametersView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('基础属性', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: '世界名称', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _gameMode,
                  decoration: const InputDecoration(labelText: '游戏模式', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('创造模式 (Creative)')),
                    DropdownMenuItem(value: 0, child: Text('生存模式 (Survival)')),
                    DropdownMenuItem(value: 2, child: Text('冒险模式 (Adventure)')),
                  ],
                  onChanged: (v) => setState(() => _gameMode = v ?? 1),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _biomeId,
                  decoration: const InputDecoration(labelText: '生态群系 (全量 ID 表)', border: OutlineInputBorder()),
                  items: GameDataService().biomes.map((b) {
                    final numId = int.tryParse(b.numId) ?? 0;
                    return DropdownMenuItem<int>(
                      value: numId,
                      child: Text('${b.name} (${b.id}) [ID: ${b.numId}]'),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _biomeId = v ?? 1),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('1.18+ 扩展高度体系 (-64~320)'),
                  value: _cavesAndCliffs,
                  onChanged: (v) => setState(() => _cavesAndCliffs = v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 快捷预设
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('快捷预设', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('经典草地 (4层)'),
                      onPressed: () => setState(() => _layers = FlatWorldGenerator.classicPreset),
                    ),
                    ActionChip(
                      label: const Text('采矿地下城 (238层)'),
                      onPressed: () => setState(() => _layers = FlatWorldGenerator.tunnelingPreset),
                    ),
                    ActionChip(
                      label: const Text('水世界 (101层)'),
                      onPressed: () => setState(() => _layers = FlatWorldGenerator.waterWorldPreset),
                    ),
                    ActionChip(
                      label: const Text('深板岩洞穴 (201层)'),
                      onPressed: () => setState(() => _layers = FlatWorldGenerator.overworldCavesPreset),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLayersView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '自定义方块层 (总高度: $_totalHeight 格)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加新层'),
              onPressed: _addNewLayerDialog,
            ),
          ],
        ),
        const SizedBox(height: 12),

        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _layers.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex -= 1;
              final item = _layers.removeAt(oldIndex);
              _layers.insert(newIndex, item);
            });
          },
          itemBuilder: (context, index) {
            final layer = _layers[index];
            return Card(
              key: ValueKey('layer_$index'),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.withValues(alpha: 0.2),
                  child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                title: Text(layer.blockName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('厚度: ${layer.count} 方块'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _editLayerDialog(index),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20, color: Colors.redAccent),
                      onPressed: () => setState(() => _layers.removeAt(index)),
                    ),
                    const Icon(Icons.drag_handle, color: Colors.grey),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _addNewLayerDialog() {
    final blockCtrl = TextEditingController(text: 'minecraft:dirt');
    final countCtrl = TextEditingController(text: '1');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加地层'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: blockCtrl,
              decoration: const InputDecoration(labelText: '方块 ID (如 stone, dirt)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: countCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '厚度 (方块格数)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final count = int.tryParse(countCtrl.text.trim()) ?? 1;
              setState(() {
                _layers.add(FlatLayerConfig(blockName: blockCtrl.text.trim(), count: count));
              });
              Navigator.pop(ctx);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _editLayerDialog(int index) {
    final layer = _layers[index];
    final blockCtrl = TextEditingController(text: layer.blockName);
    final countCtrl = TextEditingController(text: layer.count.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑第 ${index + 1} 层'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: blockCtrl,
              decoration: const InputDecoration(labelText: '方块 ID', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: countCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '厚度', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final count = int.tryParse(countCtrl.text.trim()) ?? 1;
              setState(() {
                layer.blockName = blockCtrl.text.trim();
                layer.count = count;
              });
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _generateWorld() async {
    final dirs = await StorageService().getSearchDirectories();
    String targetDir;
    if (dirs.isNotEmpty) {
      targetDir = dirs.first;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      targetDir = appDir.path;
    }

    try {
      final worldPath = await FlatWorldGenerator().createSuperflatWorld(
        targetParentDir: targetDir,
        worldName: _nameCtrl.text.trim(),
        biomeId: _biomeId,
        layers: _layers,
        gameMode: _gameMode,
        difficulty: _difficulty,
        cavesAndCliffs: _cavesAndCliffs,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('超平坦世界已创建: $worldPath')),
        );
        Navigator.pop(context, worldPath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建世界失败: $e')),
        );
      }
    }
  }
}
