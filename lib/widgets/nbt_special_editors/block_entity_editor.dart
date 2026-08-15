import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/data_manager.dart';
import '../../nbt/nbt_tags.dart';
import '../../services/entity_service.dart';
import '../id_reference_dialog.dart';
import '../nbt_tree_widget.dart';

/// 带 NBT 数据的方块实体专有编辑器 (刷怪笼、宝箱、指令方块、告示牌等)
class BlockEntityEditorScreen extends StatefulWidget {
  final WorldBlockEntity blockEntity;
  const BlockEntityEditorScreen({super.key, required this.blockEntity});

  @override
  State<BlockEntityEditorScreen> createState() => _BlockEntityEditorScreenState();
}

class _BlockEntityEditorScreenState extends State<BlockEntityEditorScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 刷怪笼参数
  late TextEditingController _spawnerEntityCtrl;
  late TextEditingController _spawnCountCtrl;
  late TextEditingController _minDelayCtrl;
  late TextEditingController _maxDelayCtrl;
  late TextEditingController _playerRangeCtrl;

  // 指令方块参数
  late TextEditingController _cmdCtrl;
  late TextEditingController _cmdNameCtrl;
  bool _executeOnFirstTick = false;
  bool _auto = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final nbt = widget.blockEntity.nbt;

    // 刷怪笼
    _spawnerEntityCtrl = TextEditingController(text: nbt.value['EntityIdentifier'] is NbtString ? (nbt.value['EntityIdentifier'] as NbtString).value : 'minecraft:zombie');
    _spawnCountCtrl = TextEditingController(text: (nbt.value['SpawnCount'] as NbtShort?)?.value.toString() ?? '4');
    _minDelayCtrl = TextEditingController(text: (nbt.value['MinSpawnDelay'] as NbtShort?)?.value.toString() ?? '200');
    _maxDelayCtrl = TextEditingController(text: (nbt.value['MaxSpawnDelay'] as NbtShort?)?.value.toString() ?? '800');
    _playerRangeCtrl = TextEditingController(text: (nbt.value['RequiredPlayerRange'] as NbtShort?)?.value.toString() ?? '16');

    // 指令方块
    _cmdCtrl = TextEditingController(text: nbt.value['Command'] is NbtString ? (nbt.value['Command'] as NbtString).value : '');
    _cmdNameCtrl = TextEditingController(text: nbt.value['CustomName'] is NbtString ? (nbt.value['CustomName'] as NbtString).value : '');
    _executeOnFirstTick = (nbt.value['ExecuteOnFirstTick'] as NbtByte?)?.value == 1;
    _auto = (nbt.value['auto'] as NbtByte?)?.value == 1;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _spawnerEntityCtrl.dispose();
    _spawnCountCtrl.dispose();
    _minDelayCtrl.dispose();
    _maxDelayCtrl.dispose();
    _playerRangeCtrl.dispose();
    _cmdCtrl.dispose();
    _cmdNameCtrl.dispose();
    super.dispose();
  }

  void _applyChanges() {
    final nbt = widget.blockEntity.nbt;
    final id = widget.blockEntity.blockId;

    if (id == 'MobSpawner') {
      nbt.value['EntityIdentifier'] = NbtString(_spawnerEntityCtrl.text.trim());
      nbt.value['SpawnCount'] = NbtShort(int.tryParse(_spawnCountCtrl.text) ?? 4);
      nbt.value['MinSpawnDelay'] = NbtShort(int.tryParse(_minDelayCtrl.text) ?? 200);
      nbt.value['MaxSpawnDelay'] = NbtShort(int.tryParse(_maxDelayCtrl.text) ?? 800);
      nbt.value['RequiredPlayerRange'] = NbtShort(int.tryParse(_playerRangeCtrl.text) ?? 16);
    } else if (id == 'CommandBlock') {
      nbt.value['Command'] = NbtString(_cmdCtrl.text);
      nbt.value['CustomName'] = NbtString(_cmdNameCtrl.text);
      nbt.value['ExecuteOnFirstTick'] = NbtByte(_executeOnFirstTick ? 1 : 0);
      nbt.value['auto'] = NbtByte(_auto ? 1 : 0);
    }

    final dm = context.read<DataManager>();
    dm.commitNbtModification(widget.blockEntity.chunkKey, [], nbt, nbt);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('方块实体 NBT 数据已成功保存！')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Image.asset(
                widget.blockEntity.iconAssetPath,
                width: 26,
                height: 26,
                errorBuilder: (_, __, ___) => const Icon(Icons.inventory_2, color: Colors.amber, size: 24),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('编辑方块实体: ${widget.blockEntity.title}', overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book, color: Colors.amberAccent),
            tooltip: '打开 Minecraft ID 对照表',
            onPressed: () {
              showDialog(context: context, builder: (_) => const IdReferenceDialog());
            },
          ),
          IconButton(
            icon: const Icon(Icons.save, color: Colors.greenAccent),
            tooltip: '保存修改',
            onPressed: _applyChanges,
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.tune), text: '可视化属性'),
            Tab(icon: Icon(Icons.account_tree), text: '完整 NBT 原始树'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildVisualTab(),
          _buildRawTreeTab(),
        ],
      ),
    );
  }

  Widget _buildVisualTab() {
    final id = widget.blockEntity.blockId;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('方块空间坐标', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('类型: ${widget.blockEntity.blockId}'),
                Text('坐标: X: ${widget.blockEntity.x}, Y: ${widget.blockEntity.y}, Z: ${widget.blockEntity.z}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        if (id == 'MobSpawner') ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('刷怪笼参数 (Mob Spawner)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _spawnerEntityCtrl,
                    decoration: InputDecoration(
                      labelText: '刷出生物 ID (EntityIdentifier)',
                      helperText: '如 minecraft:zombie, minecraft:skeleton, minecraft:blaze',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search, size: 18),
                        tooltip: '在 ID 对照表中查询',
                        onPressed: () => showDialog(context: context, builder: (_) => const IdReferenceDialog()),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _spawnCountCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '单次刷出数量 (SpawnCount)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _playerRangeCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '玩家激活距离 (RequiredPlayerRange)', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minDelayCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '最小冷却刻 (MinSpawnDelay)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _maxDelayCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '最大冷却刻 (MaxSpawnDelay)', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ] else if (id == 'CommandBlock') ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('指令方块参数 (Command Block)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _cmdNameCtrl,
                    decoration: const InputDecoration(labelText: '执行者悬浮名称 (CustomName)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _cmdCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: '控制台指令 (Command)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('保持开启 / 自动执行 (auto)'),
                    value: _auto,
                    onChanged: (v) => setState(() => _auto = v),
                  ),
                  SwitchListTile(
                    title: const Text('首刻执行 (ExecuteOnFirstTick)'),
                    value: _executeOnFirstTick,
                    onChanged: (v) => setState(() => _executeOnFirstTick = v),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('当前方块实体包含 NBT 数据，请切换到“完整 NBT 原始树”标签页查看和编辑所有字段。', style: TextStyle(color: Colors.grey)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRawTreeTab() {
    return NbtTreeWidget(
      nbtKey: widget.blockEntity.chunkKey,
      root: widget.blockEntity.nbt,
      onSaved: () {
        final dm = context.read<DataManager>();
        dm.commitNbtModification(widget.blockEntity.chunkKey, [], widget.blockEntity.nbt, widget.blockEntity.nbt);
      },
    );
  }
}
