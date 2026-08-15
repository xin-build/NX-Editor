import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/data_manager.dart';
import '../../nbt/nbt_tags.dart';
import '../../services/entity_service.dart';
import '../nbt_tree_widget.dart';

/// 生物与实体专有 NBT 编辑器 (支持可视化属性与完整 NBT 树)
class EntityNbtEditorScreen extends StatefulWidget {
  final WorldEntity entity;
  const EntityNbtEditorScreen({super.key, required this.entity});

  @override
  State<EntityNbtEditorScreen> createState() => _EntityNbtEditorScreenState();
}

class _EntityNbtEditorScreenState extends State<EntityNbtEditorScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  late TextEditingController _nameCtrl;
  late TextEditingController _healthCtrl;
  late TextEditingController _xCtrl;
  late TextEditingController _yCtrl;
  late TextEditingController _zCtrl;

  bool _invulnerable = false;
  bool _noAi = false;
  bool _persistence = true;
  bool _silent = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    final nbt = widget.entity.nbt;
    _nameCtrl = TextEditingController(text: nbt.value['CustomName'] is NbtString ? (nbt.value['CustomName'] as NbtString).value : '');
    _healthCtrl = TextEditingController(text: widget.entity.health.toStringAsFixed(0));
    _xCtrl = TextEditingController(text: widget.entity.x.toStringAsFixed(2));
    _yCtrl = TextEditingController(text: widget.entity.y.toStringAsFixed(2));
    _zCtrl = TextEditingController(text: widget.entity.z.toStringAsFixed(2));

    _invulnerable = (nbt.value['Invulnerable'] as NbtByte?)?.value == 1;
    _noAi = (nbt.value['NoAI'] as NbtByte?)?.value == 1;
    _persistence = (nbt.value['PersistenceRequired'] as NbtByte?)?.value == 1;
    _silent = (nbt.value['Silent'] as NbtByte?)?.value == 1;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose();
    _healthCtrl.dispose();
    _xCtrl.dispose();
    _yCtrl.dispose();
    _zCtrl.dispose();
    super.dispose();
  }

  void _applyChanges() {
    final nbt = widget.entity.nbt;

    // 自定义名
    if (_nameCtrl.text.isNotEmpty) {
      nbt.value['CustomName'] = NbtString(_nameCtrl.text.trim());
      nbt.value['CustomNameVisible'] = NbtByte(1);
    } else {
      nbt.value.remove('CustomName');
      nbt.value.remove('CustomNameVisible');
    }

    // 生命值
    final h = double.tryParse(_healthCtrl.text) ?? widget.entity.health;
    nbt.value['Health'] = NbtFloat(h);

    // 坐标
    final nx = double.tryParse(_xCtrl.text) ?? widget.entity.x;
    final ny = double.tryParse(_yCtrl.text) ?? widget.entity.y;
    final nz = double.tryParse(_zCtrl.text) ?? widget.entity.z;
    nbt.value['Pos'] = NbtList(NbtTagType.float, [NbtFloat(nx), NbtFloat(ny), NbtFloat(nz)]);

    // 状态标签
    nbt.value['Invulnerable'] = NbtByte(_invulnerable ? 1 : 0);
    nbt.value['NoAI'] = NbtByte(_noAi ? 1 : 0);
    nbt.value['PersistenceRequired'] = NbtByte(_persistence ? 1 : 0);
    nbt.value['Silent'] = NbtByte(_silent ? 1 : 0);

    final dm = context.read<DataManager>();
    EntityService().saveEntityNbt(dm, widget.entity, nbt);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('生物 NBT 修改已保存并写入数据库！')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              widget.entity.iconAssetPath,
              width: 28,
              height: 28,
              errorBuilder: (_, __, ___) => Icon(widget.entity.category.icon, color: widget.entity.category.color, size: 24),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('编辑生物: ${widget.entity.name}', overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save, color: Colors.greenAccent),
            tooltip: '保存生物数据',
            onPressed: _applyChanges,
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.tune), text: '可视化属性与状态'),
            Tab(icon: Icon(Icons.account_tree), text: '完整 NBT 原始树'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildVisualEditor(),
          _buildRawNbtTree(),
        ],
      ),
    );
  }

  Widget _buildVisualEditor() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('基础信息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text('类型 ID: ${widget.entity.identifier}', style: const TextStyle(color: Colors.grey)),
                Text('唯一 UID: ${widget.entity.uniqueId}', style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '自定义生物名称 (CustomName)',
                    border: OutlineInputBorder(),
                    helperText: '例如 "守卫者长老"、"超级小白" 等，游戏内头顶直接显示',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _healthCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '当前生命值 (Health)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('世界空间坐标 (Pos)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _xCtrl,
                        keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                        decoration: const InputDecoration(labelText: 'X 坐标', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _yCtrl,
                        keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                        decoration: const InputDecoration(labelText: 'Y 坐标 (高度)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _zCtrl,
                        keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                        decoration: const InputDecoration(labelText: 'Z 坐标', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
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
                title: const Text('无敌模式 (Invulnerable)'),
                subtitle: const Text('免疫任何伤害，不会被玩家或环境击杀'),
                value: _invulnerable,
                onChanged: (v) => setState(() => _invulnerable = v),
              ),
              SwitchListTile(
                title: const Text('禁用 AI (NoAI)'),
                subtitle: const Text('生物将定在原地，不进行移动或攻击（常用作雕像/模型展示）'),
                value: _noAi,
                onChanged: (v) => setState(() => _noAi = v),
              ),
              SwitchListTile(
                title: const Text('永不刷掉 (PersistenceRequired)'),
                subtitle: const Text('即使玩家远离该区块，生物也不会被游戏自动清除'),
                value: _persistence,
                onChanged: (v) => setState(() => _persistence = v),
              ),
              SwitchListTile(
                title: const Text('静音生物 (Silent)'),
                subtitle: const Text('生物不发出任何叫声或环境音效'),
                value: _silent,
                onChanged: (v) => setState(() => _silent = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRawNbtTree() {
    return NbtTreeWidget(
      nbtKey: widget.entity.key,
      root: widget.entity.nbt,
      onSaved: () {
        final dm = context.read<DataManager>();
        EntityService().saveEntityNbt(dm, widget.entity, widget.entity.nbt);
      },
    );
  }
}
