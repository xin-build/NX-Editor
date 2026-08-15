import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/data_manager.dart';
import '../../nbt/nbt_tags.dart';
import '../nbt_tree_widget.dart';

/// 完整玩家数据编辑器 (包含状态、背包、末影箱与完整 NBT 原始树)
class PlayerEditorScreen extends StatefulWidget {
  final String playerKey; // '~local_player' 或 'Player' 或 'player_uuid'
  const PlayerEditorScreen({super.key, this.playerKey = '~local_player'});

  @override
  State<PlayerEditorScreen> createState() => _PlayerEditorScreenState();
}

class _PlayerEditorScreenState extends State<PlayerEditorScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _healthCtrl = TextEditingController(text: '20');
  final _foodCtrl = TextEditingController(text: '20');
  final _levelCtrl = TextEditingController(text: '0');
  final _xpCtrl = TextEditingController(text: '0');
  final _xCtrl = TextEditingController(text: '0');
  final _yCtrl = TextEditingController(text: '64');
  final _zCtrl = TextEditingController(text: '0');

  bool _mayFly = false;
  bool _flying = false;
  bool _invulnerable = false;
  int _dimension = 0;

  // 背包物品映射 (Slot -> Item Compound)
  final Map<int, NbtCompound> _inventorySlots = {};
  final Map<int, NbtCompound> _enderChestSlots = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadPlayerData();
  }

  void _loadPlayerData() {
    final dm = context.read<DataManager>();
    NbtCompound? playerComp = dm.getNbtCompound(widget.playerKey);

    // fallback 到 level.dat > Player
    if (playerComp == null && dm.getNbtCompound('level.dat') != null) {
      final levelDat = dm.getNbtCompound('level.dat')!;
      if (levelDat.value.containsKey('Player') && levelDat.value['Player'] is NbtCompound) {
        playerComp = levelDat.value['Player'] as NbtCompound;
      }
    }

    if (playerComp == null) return;

    final p = playerComp.value;

    if (p.containsKey('Health')) {
      final t = p['Health'];
      if (t is NbtShort) {
        _healthCtrl.text = t.value.toString();
      } else if (t is NbtFloat) {
        _healthCtrl.text = t.value.toStringAsFixed(1);
      }
    }
    if (p.containsKey('foodLevel')) {
      final t = p['foodLevel'];
      if (t is NbtInt) _foodCtrl.text = t.value.toString();
    }
    if (p.containsKey('PlayerLevel')) {
      final t = p['PlayerLevel'];
      if (t is NbtInt) _levelCtrl.text = t.value.toString();
    }
    if (p.containsKey('DimensionId')) {
      final t = p['DimensionId'];
      if (t is NbtInt) _dimension = t.value;
    }

    if (p.containsKey('Pos') && p['Pos'] is NbtList) {
      final pos = (p['Pos'] as NbtList).value;
      if (pos.length >= 3) {
        _xCtrl.text = (pos[0] as NbtFloat).value.toStringAsFixed(1);
        _yCtrl.text = (pos[1] as NbtFloat).value.toStringAsFixed(1);
        _zCtrl.text = (pos[2] as NbtFloat).value.toStringAsFixed(1);
      }
    }

    if (p.containsKey('abilities') && p['abilities'] is NbtCompound) {
      final ab = (p['abilities'] as NbtCompound).value;
      if (ab.containsKey('mayfly')) _mayFly = (ab['mayfly'] as NbtByte).value == 1;
      if (ab.containsKey('flying')) _flying = (ab['flying'] as NbtByte).value == 1;
      if (ab.containsKey('invulnerable')) _invulnerable = (ab['invulnerable'] as NbtByte).value == 1;
    }

    // 解析 Inventory
    _inventorySlots.clear();
    if (p.containsKey('Inventory') && p['Inventory'] is NbtList) {
      final invList = (p['Inventory'] as NbtList).value;
      for (final item in invList) {
        if (item is NbtCompound && item.value.containsKey('Slot')) {
          final slot = (item.value['Slot'] as NbtByte).value;
          _inventorySlots[slot] = item;
        }
      }
    }

    // 解析 EnderChestInventory
    _enderChestSlots.clear();
    if (p.containsKey('EnderChestInventory') && p['EnderChestInventory'] is NbtList) {
      final ecList = (p['EnderChestInventory'] as NbtList).value;
      for (final item in ecList) {
        if (item is NbtCompound && item.value.containsKey('Slot')) {
          final slot = (item.value['Slot'] as NbtByte).value;
          _enderChestSlots[slot] = item;
        }
      }
    }
  }

  void _savePlayerData() {
    final dm = context.read<DataManager>();
    NbtCompound? playerComp = dm.getNbtCompound(widget.playerKey);

    if (playerComp == null && dm.getNbtCompound('level.dat') != null) {
      final levelDat = dm.getNbtCompound('level.dat')!;
      if (levelDat.value.containsKey('Player') && levelDat.value['Player'] is NbtCompound) {
        playerComp = levelDat.value['Player'] as NbtCompound;
      }
    }

    if (playerComp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到玩家数据对象！')),
      );
      return;
    }

    final p = playerComp.value;

    // 1. 基础状态
    p['Health'] = NbtShort(double.tryParse(_healthCtrl.text)?.round() ?? 20);
    p['foodLevel'] = NbtInt(int.tryParse(_foodCtrl.text) ?? 20);
    p['PlayerLevel'] = NbtInt(int.tryParse(_levelCtrl.text) ?? 0);
    p['DimensionId'] = NbtInt(_dimension);

    final x = double.tryParse(_xCtrl.text) ?? 0.0;
    final y = double.tryParse(_yCtrl.text) ?? 64.0;
    final z = double.tryParse(_zCtrl.text) ?? 0.0;
    p['Pos'] = NbtList(NbtTagType.float, [NbtFloat(x), NbtFloat(y), NbtFloat(z)]);

    // 2. 能力标签
    final ab = (p['abilities'] is NbtCompound) ? (p['abilities'] as NbtCompound).value : <String, NbtTag>{};
    ab['mayfly'] = NbtByte(_mayFly ? 1 : 0);
    ab['flying'] = NbtByte(_flying ? 1 : 0);
    ab['invulnerable'] = NbtByte(_invulnerable ? 1 : 0);
    p['abilities'] = NbtCompound(ab);

    // 3. 背包列表重构
    final invList = _inventorySlots.values.toList();
    p['Inventory'] = NbtList(NbtTagType.compound, invList);

    // 4. 末影箱重构
    final ecList = _enderChestSlots.values.toList();
    p['EnderChestInventory'] = NbtList(NbtTagType.compound, ecList);

    // 同步到 DataManager 事务并标记修改
    dm.commitNbtModification(widget.playerKey, [], playerComp, playerComp);
    dm.setPlayerPositionInternal(x, y, z, _dimension);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('玩家全量数据 (状态/背包/NBT) 已保存！')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DataManager>();
    final playerComp = dm.getNbtCompound(widget.playerKey) ?? (dm.getNbtCompound('level.dat')?.value['Player'] as NbtCompound?);

    final canPop = Navigator.canPop(context);

    return Scaffold(
      appBar: canPop
          ? AppBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person, color: Colors.blueAccent, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '玩家数据 (${widget.playerKey})',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.save, color: Colors.greenAccent),
                  tooltip: '保存玩家修改',
                  onPressed: _savePlayerData,
                ),
                const SizedBox(width: 8),
              ],
              bottom: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: const [
                  Tab(icon: Icon(Icons.tune), text: '状态与属性'),
                  Tab(icon: Icon(Icons.backpack), text: '物品背包'),
                  Tab(icon: Icon(Icons.all_inbox), text: '末影箱'),
                  Tab(icon: Icon(Icons.account_tree), text: '完整 NBT 树'),
                ],
              ),
            )
          : PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                color: const Color(0xFF1B1F27),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabs: const [
                    Tab(icon: Icon(Icons.tune, size: 16), text: '属性'),
                    Tab(icon: Icon(Icons.backpack, size: 16), text: '背包'),
                    Tab(icon: Icon(Icons.all_inbox, size: 16), text: '末影箱'),
                    Tab(icon: Icon(Icons.account_tree, size: 16), text: 'NBT'),
                  ],
                ),
              ),
            ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStatusTab(),
          _buildInventoryTab(),
          _buildEnderChestTab(),
          playerComp != null
              ? NbtTreeWidget(nbtKey: widget.playerKey, root: playerComp, onSaved: () => setState(() {}))
              : const Center(child: Text('无法加载玩家 NBT 数据树')),
        ],
      ),
    );
  }

  Widget _buildStatusTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('基础生存状态', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildNumField('生命值 (Health)', _healthCtrl, Icons.favorite, Colors.redAccent)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildNumField('饱食度 (Food)', _foodCtrl, Icons.restaurant, Colors.orangeAccent)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildNumField('经验等级 (Level)', _levelCtrl, Icons.star, Colors.greenAccent)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildNumField('经验条进度 (0.0~1.0)', _xpCtrl, Icons.auto_awesome, Colors.tealAccent)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _dimension,
                        decoration: const InputDecoration(labelText: '所在维度', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('主世界 (Overworld)')),
                          DropdownMenuItem(value: 1, child: Text('下界 (Nether)')),
                          DropdownMenuItem(value: 2, child: Text('末地 (The End)')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _dimension = v);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('世界空间坐标 (Pos)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildNumField('X 坐标', _xCtrl, Icons.location_on, Colors.blueAccent)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildNumField('Y 坐标 (高度)', _yCtrl, Icons.height, Colors.cyanAccent)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildNumField('Z 坐标', _zCtrl, Icons.location_on, Colors.blueAccent)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('允许飞行 (mayfly)'),
                subtitle: const Text('在生存模式下解锁双跳飞行能力'),
                value: _mayFly,
                onChanged: (v) => setState(() => _mayFly = v),
              ),
              SwitchListTile(
                title: const Text('正在飞行 (flying)'),
                value: _flying,
                onChanged: (v) => setState(() => _flying = v),
              ),
              SwitchListTile(
                title: const Text('无敌模式 (invulnerable)'),
                subtitle: const Text('免疫任何来源的伤害'),
                value: _invulnerable,
                onChanged: (v) => setState(() => _invulnerable = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInventoryTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('盔甲装备栏 (Armors 100~103) & 副手 (Offhand 106)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSlotWidget(103, '头盔', Icons.face),
            const SizedBox(width: 8),
            _buildSlotWidget(102, '胸甲', Icons.shield),
            const SizedBox(width: 8),
            _buildSlotWidget(101, '护腿', Icons.airline_seat_legroom_reduced),
            const SizedBox(width: 8),
            _buildSlotWidget(100, '靴子', Icons.snowshoeing),
            const SizedBox(width: 24),
            _buildSlotWidget(106, '副手', Icons.pan_tool),
          ],
        ),
        const SizedBox(height: 16),

        const Text('主背包物品栏 (Slots 9~35)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 9,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: 27,
          itemBuilder: (ctx, i) => _buildSlotWidget(i + 9, '背包 ${i + 9}'),
        ),
        const SizedBox(height: 16),

        const Text('快捷栏 (Hotbar Slots 0~8)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.greenAccent)),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 9,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: 9,
          itemBuilder: (ctx, i) => _buildSlotWidget(i, '快捷栏 $i'),
        ),
      ],
    );
  }

  Widget _buildEnderChestTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('末影箱物品槽位 (Slots 0~26)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 9,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: 27,
          itemBuilder: (ctx, i) => _buildEnderSlotWidget(i),
        ),
      ],
    );
  }

  Widget _buildSlotWidget(int slotId, String tooltip, [IconData? defaultIcon]) {
    final item = _inventorySlots[slotId];
    String? name;
    int count = 0;

    if (item != null) {
      if (item.value.containsKey('Name')) {
        name = (item.value['Name'] as NbtString).value.replaceAll('minecraft:', '');
      }
      if (item.value.containsKey('Count')) {
        count = (item.value['Count'] as NbtByte).value;
      }
    }

    return InkWell(
      onTap: () => _editItemSlot(slotId, item, isEnder: false),
      child: Tooltip(
        message: '$tooltip\n${name != null ? "$name x$count" : "空"}',
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF222630),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: item != null ? Colors.amberAccent : Colors.white24, width: item != null ? 1.5 : 1.0),
          ),
          child: Center(
            child: item != null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(name ?? '物品', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('x$count', style: const TextStyle(fontSize: 10, color: Colors.greenAccent)),
                    ],
                  )
                : Icon(defaultIcon ?? Icons.add, size: 16, color: Colors.white24),
          ),
        ),
      ),
    );
  }

  Widget _buildEnderSlotWidget(int slotId) {
    final item = _enderChestSlots[slotId];
    String? name;
    int count = 0;

    if (item != null) {
      if (item.value.containsKey('Name')) {
        name = (item.value['Name'] as NbtString).value.replaceAll('minecraft:', '');
      }
      if (item.value.containsKey('Count')) {
        count = (item.value['Count'] as NbtByte).value;
      }
    }

    return InkWell(
      onTap: () => _editItemSlot(slotId, item, isEnder: true),
      child: Tooltip(
        message: '末影槽 $slotId\n${name != null ? "$name x$count" : "空"}',
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF222630),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: item != null ? Colors.purpleAccent : Colors.white24, width: item != null ? 1.5 : 1.0),
          ),
          child: Center(
            child: item != null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(name ?? '物品', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('x$count', style: const TextStyle(fontSize: 10, color: Colors.purpleAccent)),
                    ],
                  )
                : const Icon(Icons.add, size: 16, color: Colors.white24),
          ),
        ),
      ),
    );
  }

  void _editItemSlot(int slotId, NbtCompound? currentItem, {required bool isEnder}) {
    final nameCtrl = TextEditingController(
      text: currentItem?.value['Name'] is NbtString ? (currentItem!.value['Name'] as NbtString).value : 'minecraft:diamond',
    );
    final countCtrl = TextEditingController(
      text: currentItem?.value['Count'] is NbtByte ? (currentItem!.value['Count'] as NbtByte).value.toString() : '64',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑槽位 $slotId 物品'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '物品 ID (如 minecraft:diamond_sword)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: countCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '数量 (Count 1~64)', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          if (currentItem != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  if (isEnder) {
                    _enderChestSlots.remove(slotId);
                  } else {
                    _inventorySlots.remove(slotId);
                  }
                });
              },
              child: const Text('清空槽位'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              final name = nameCtrl.text.trim();
              final count = int.tryParse(countCtrl.text) ?? 1;

              final comp = NbtCompound({
                'Slot': NbtByte(slotId),
                'Name': NbtString(name.startsWith('minecraft:') ? name : 'minecraft:$name'),
                'Count': NbtByte(count.clamp(1, 64)),
                'Damage': NbtShort(0),
                'tag': NbtCompound({}),
              });

              setState(() {
                if (isEnder) {
                  _enderChestSlots[slotId] = comp;
                } else {
                  _inventorySlots[slotId] = comp;
                }
              });
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildNumField(String label, TextEditingController ctrl, IconData icon, Color color) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: color, size: 18),
        border: const OutlineInputBorder(),
      ),
    );
  }
}
