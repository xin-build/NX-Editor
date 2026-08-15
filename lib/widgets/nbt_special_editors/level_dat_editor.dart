import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/data_manager.dart';
import '../../nbt/nbt_tags.dart';
import '../../render/map_layer_types.dart';
import '../../utils/game_data_service.dart';

/// 可视化 level.dat 世界设置编辑器 (包含自定义超平坦方块层与图标可视化)
class LevelDatEditorScreen extends StatefulWidget {
  const LevelDatEditorScreen({super.key});

  @override
  State<LevelDatEditorScreen> createState() => _LevelDatEditorScreenState();
}

class _LevelDatEditorScreenState extends State<LevelDatEditorScreen> {
  final _nameCtrl = TextEditingController();
  final _seedCtrl = TextEditingController();
  final _spawnXCtrl = TextEditingController();
  final _spawnYCtrl = TextEditingController();
  final _spawnZCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();

  int _gameMode = 0;
  int _difficulty = 2;
  int _generator = 1; // 0: 旧版有限, 1: 无限, 2: 超平坦
  bool _cheats = true;
  bool _rain = false;
  bool _lightning = false;

  // 自定义超平坦层结构
  List<Map<String, dynamic>> _flatBlockLayers = [];
  int _flatBiomeId = 1;
  bool _hasFlatWorldConfig = false;

  final Map<String, bool> _gameRules = {
    'keepinventory': false,
    'showcoordinates': true,
    'mobgriefing': true,
    'dodaylightcycle': true,
    'dofiretick': true,
    'domobspawning': true,
    'naturalregeneration': true,
    'pvp': true,
  };

  @override
  void initState() {
    super.initState();
    _loadFromDataManager();
  }

  void _loadFromDataManager() {
    final dm = context.read<DataManager>();
    final root = dm.getNbtCompound('level.dat');
    if (root == null) return;

    if (root.value.containsKey('LevelName')) {
      final t = root.value['LevelName'];
      if (t is NbtString) _nameCtrl.text = t.value;
    }
    if (root.value.containsKey('RandomSeed')) {
      final t = root.value['RandomSeed'];
      if (t is NbtLong) {
        _seedCtrl.text = t.value.toString();
      } else if (t is NbtInt) {
        _seedCtrl.text = t.value.toString();
      }
    }
    if (root.value.containsKey('GameType')) {
      final t = root.value['GameType'];
      if (t is NbtInt) {
        _gameMode = t.value;
      } else if (t is NbtByte) {
        _gameMode = t.value;
      }
    }
    if (root.value.containsKey('Difficulty')) {
      final t = root.value['Difficulty'];
      if (t is NbtInt) {
        _difficulty = t.value;
      } else if (t is NbtByte) {
        _difficulty = t.value;
      }
    }
    if (root.value.containsKey('Generator')) {
      final t = root.value['Generator'];
      if (t is NbtInt) _generator = t.value;
    }
    if (root.value.containsKey('SpawnX')) {
      final t = root.value['SpawnX'];
      if (t is NbtInt) _spawnXCtrl.text = t.value.toString();
    }
    if (root.value.containsKey('SpawnY')) {
      final t = root.value['SpawnY'];
      if (t is NbtInt) _spawnYCtrl.text = t.value.toString();
    }
    if (root.value.containsKey('SpawnZ')) {
      final t = root.value['SpawnZ'];
      if (t is NbtInt) _spawnZCtrl.text = t.value.toString();
    }
    if (root.value.containsKey('Time')) {
      final t = root.value['Time'];
      if (t is NbtLong) _timeCtrl.text = t.value.toString();
    }
    if (root.value.containsKey('cheatsEnabled')) {
      final t = root.value['cheatsEnabled'];
      if (t is NbtByte) _cheats = t.value == 1;
    }
    if (root.value.containsKey('rainLevel')) {
      final t = root.value['rainLevel'];
      if (t is NbtFloat) _rain = t.value > 0.5;
    }

    // 解析超平坦生成层 (FlatWorldLayers)
    if (root.value.containsKey('FlatWorldLayers')) {
      final t = root.value['FlatWorldLayers'];
      if (t is NbtString && t.value.isNotEmpty) {
        try {
          final decoded = json.decode(t.value) as Map<String, dynamic>;
          _flatBiomeId = (decoded['biome_id'] as num?)?.toInt() ?? 1;
          final layers = decoded['block_layers'] as List<dynamic>? ?? [];
          _flatBlockLayers = layers.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _hasFlatWorldConfig = true;
        } catch (_) {}
      }
    }

    // 默认超平坦回退层 (若未配置超平坦则初始化为基岩+2泥土+草方块)
    if (_flatBlockLayers.isEmpty && _generator == 2) {
      _flatBlockLayers = [
        {'block_name': 'minecraft:bedrock', 'count': 1},
        {'block_name': 'minecraft:dirt', 'count': 2},
        {'block_name': 'minecraft:grass_block', 'count': 1},
      ];
      _hasFlatWorldConfig = true;
    }

    // 规则
    for (final ruleKey in _gameRules.keys) {
      if (root.value.containsKey(ruleKey)) {
        final t = root.value[ruleKey];
        if (t is NbtByte) _gameRules[ruleKey] = t.value == 1;
      }
    }
  }

  void _save() {
    final dm = context.read<DataManager>();
    final root = dm.getNbtCompound('level.dat');
    if (root == null) return;

    root.value['LevelName'] = NbtString(_nameCtrl.text.trim());
    final seed = int.tryParse(_seedCtrl.text.trim());
    if (seed != null) root.value['RandomSeed'] = NbtLong(seed);

    root.value['GameType'] = NbtInt(_gameMode);
    root.value['Difficulty'] = NbtInt(_difficulty);
    root.value['Generator'] = NbtInt(_generator);
    root.value['cheatsEnabled'] = NbtByte(_cheats ? 1 : 0);
    root.value['commandsEnabled'] = NbtByte(_cheats ? 1 : 0);

    final sx = int.tryParse(_spawnXCtrl.text.trim());
    final sy = int.tryParse(_spawnYCtrl.text.trim());
    final sz = int.tryParse(_spawnZCtrl.text.trim());
    if (sx != null) root.value['SpawnX'] = NbtInt(sx);
    if (sy != null) root.value['SpawnY'] = NbtInt(sy);
    if (sz != null) root.value['SpawnZ'] = NbtInt(sz);

    final time = int.tryParse(_timeCtrl.text.trim());
    if (time != null) root.value['Time'] = NbtLong(time);

    root.value['rainLevel'] = NbtFloat(_rain ? 1.0 : 0.0);
    root.value['lightningLevel'] = NbtFloat(_lightning ? 1.0 : 0.0);

    // 保存超平坦层
    if (_generator == 2 || _hasFlatWorldConfig) {
      final flatData = {
        'biome_id': _flatBiomeId,
        'block_layers': _flatBlockLayers,
        'encoding_version': 6,
        'structure_options': null,
      };
      root.value['FlatWorldLayers'] = NbtString(json.encode(flatData));
    }

    for (final e in _gameRules.entries) {
      root.value[e.key] = NbtByte(e.value ? 1 : 0);
    }

    dm.notifyDataChanged();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已更新 level.dat 内存数据，记得点击顶部保存！')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);

    return Scaffold(
      appBar: canPop
          ? AppBar(
              title: const Text('世界设置 (level.dat)'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.greenAccent),
                  tooltip: '应用修改',
                  onPressed: _save,
                ),
              ],
            )
          : PreferredSize(
              preferredSize: const Size.fromHeight(42),
              child: Container(
                color: const Color(0xFF222630),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(Icons.settings_applications, color: Colors.amberAccent, size: 18),
                    const SizedBox(width: 8),
                    const Text('世界全局配置 (level.dat)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.check, size: 14),
                      label: const Text('应用', style: TextStyle(fontSize: 12)),
                      onPressed: _save,
                    ),
                  ],
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 基础世界信息
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('基础信息', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: '世界名称 (LevelName)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _seedCtrl,
                    decoration: const InputDecoration(labelText: '世界种子 (RandomSeed)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _gameMode,
                    decoration: const InputDecoration(labelText: '默认游戏模式', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('生存模式 (Survival)')),
                      DropdownMenuItem(value: 1, child: Text('创造模式 (Creative)')),
                      DropdownMenuItem(value: 2, child: Text('冒险模式 (Adventure)')),
                      DropdownMenuItem(value: 6, child: Text('旁观模式 (Spectator)')),
                    ],
                    onChanged: (v) => setState(() => _gameMode = v ?? 0),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _generator,
                    decoration: const InputDecoration(labelText: '世界生成类型 (Generator)', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('旧版有限 (Old Limited)')),
                      DropdownMenuItem(value: 1, child: Text('无限世界 (Infinite)')),
                      DropdownMenuItem(value: 2, child: Text('超平坦世界 (Flat)')),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _generator = v ?? 1;
                        if (_generator == 2 && _flatBlockLayers.isEmpty) {
                          _flatBlockLayers = [
                            {'block_name': 'minecraft:bedrock', 'count': 1},
                            {'block_name': 'minecraft:dirt', 'count': 2},
                            {'block_name': 'minecraft:grass_block', 'count': 1},
                          ];
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _difficulty,
                    decoration: const InputDecoration(labelText: '游戏难度', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('和平 (Peaceful)')),
                      DropdownMenuItem(value: 1, child: Text('简单 (Easy)')),
                      DropdownMenuItem(value: 2, child: Text('普通 (Normal)')),
                      DropdownMenuItem(value: 3, child: Text('困难 (Hard)')),
                    ],
                    onChanged: (v) => setState(() => _difficulty = v ?? 2),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('启用作弊 (Cheats Enabled)'),
                    value: _cheats,
                    onChanged: (v) => setState(() => _cheats = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 超平坦层结构设置与方块图标可视化
          if (_generator == 2 || _hasFlatWorldConfig) ...[
            _buildFlatWorldLayersCard(),
            const SizedBox(height: 16),
          ],

          // 出生点与环境
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('出生点坐标与环境', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _spawnXCtrl, decoration: const InputDecoration(labelText: 'SpawnX', border: OutlineInputBorder()))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: _spawnYCtrl, decoration: const InputDecoration(labelText: 'SpawnY', border: OutlineInputBorder()))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: _spawnZCtrl, decoration: const InputDecoration(labelText: 'SpawnZ', border: OutlineInputBorder()))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _timeCtrl,
                    decoration: const InputDecoration(labelText: '世界时间 (Time Ticks)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('正在降雨 (Rain)'),
                    value: _rain,
                    onChanged: (v) => setState(() => _rain = v),
                  ),
                  SwitchListTile(
                    title: const Text('雷暴天气 (Lightning)'),
                    value: _lightning,
                    onChanged: (v) => setState(() => _lightning = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 常用游戏规则
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('游戏规则 (GameRules)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('死亡保留物品 (keepInventory)'),
                    value: _gameRules['keepinventory'] ?? false,
                    onChanged: (v) => setState(() => _gameRules['keepinventory'] = v),
                  ),
                  SwitchListTile(
                    title: const Text('显示坐标 (showCoordinates)'),
                    value: _gameRules['showcoordinates'] ?? true,
                    onChanged: (v) => setState(() => _gameRules['showcoordinates'] = v),
                  ),
                  SwitchListTile(
                    title: const Text('生物破坏 (mobGriefing)'),
                    value: _gameRules['mobgriefing'] ?? true,
                    onChanged: (v) => setState(() => _gameRules['mobgriefing'] = v),
                  ),
                  SwitchListTile(
                    title: const Text('昼夜更替 (doDaylightCycle)'),
                    value: _gameRules['dodaylightcycle'] ?? true,
                    onChanged: (v) => setState(() => _gameRules['dodaylightcycle'] = v),
                  ),
                  SwitchListTile(
                    title: const Text('生物自然生成 (doMobSpawning)'),
                    value: _gameRules['domobspawning'] ?? true,
                    onChanged: (v) => setState(() => _gameRules['domobspawning'] = v),
                  ),
                  SwitchListTile(
                    title: const Text('生命自然恢复 (naturalRegeneration)'),
                    value: _gameRules['naturalregeneration'] ?? true,
                    onChanged: (v) => setState(() => _gameRules['naturalregeneration'] = v),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 自定义超平坦生成层结构与方块图标可视化卡片
  Widget _buildFlatWorldLayersCard() {
    final gds = GameDataService();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.layers, color: Colors.amberAccent, size: 20),
                const SizedBox(width: 8),
                const Text('自定义超平坦方块层 (FlatWorldLayers)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加层'),
                  onPressed: () {
                    setState(() {
                      _flatBlockLayers.add({'block_name': 'minecraft:dirt', 'count': 1});
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: MapLayerConfig.biomeToColor(_flatBiomeId),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text('生态群系 ID: $_flatBiomeId (${gds.biomeByNumId(_flatBiomeId.toString())?.name ?? "平原"})', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () => _openChangeFlatBiome(context),
                  child: const Text('【选择群系】', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._flatBlockLayers.asMap().entries.map((entry) {
              final idx = entry.key;
              final layer = entry.value;
              final rawName = (layer['block_name'] ?? 'minecraft:dirt').toString();
              final cleanName = rawName.replaceAll('minecraft:', '').toLowerCase();
              final count = (layer['count'] as num?)?.toInt() ?? 1;

              final blockInfo = gds.blockById(cleanName);
              final displayName = blockInfo?.name.isNotEmpty == true ? blockInfo!.name : cleanName;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF252A36),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    // 高清方块图标 (浅灰底色包裹)
                    Container(
                      width: 32,
                      height: 32,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Image.asset(
                        'assrts/images/block/$cleanName.png',
                        errorBuilder: (_, __, ___) => const Icon(Icons.grid_view, color: Colors.grey, size: 20),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('第 ${idx + 1} 层: $displayName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('ID: $rawName', style: const TextStyle(fontSize: 10, color: Colors.cyanAccent)),
                        ],
                      ),
                    ),
                    Text('厚度: $count 层', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                      tooltip: '删除该层',
                      onPressed: () {
                        setState(() {
                          _flatBlockLayers.removeAt(idx);
                        });
                      },
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _openChangeFlatBiome(BuildContext context) {
    final gds = GameDataService();
    final allBiomes = gds.biomes;
    int tempBiomeId = _flatBiomeId;
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

          final currentSelected = gds.biomeByNumId(tempBiomeId.toString());

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.forest, color: Colors.greenAccent),
                SizedBox(width: 8),
                Text('选择超平坦生态群系'),
              ],
            ),
            content: SizedBox(
              width: 440,
              height: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: '搜索群系 (如: 樱花 / 192 / plains / 下界)...',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (v) => setDialogState(() => searchQuery = v.trim()),
                  ),
                  const SizedBox(height: 12),
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
                            color: MapLayerConfig.biomeToColor(tempBiomeId),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '当前选择: ${currentSelected?.name ?? "平原"} (ID: $tempBiomeId / ${currentSelected?.id ?? "plains"})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
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
                          final isSelected = numId == tempBiomeId;
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
                                tempBiomeId = numId;
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
                label: const Text('确认选择'),
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _flatBiomeId = tempBiomeId;
                  });
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
