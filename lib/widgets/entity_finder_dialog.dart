import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/data_manager.dart';
import '../render/map_viewport_controller.dart';
import '../services/entity_service.dart';
import 'nbt_special_editors/entity_nbt_editor.dart';

/// 生物与实体雷达查找器弹窗
class EntityFinderDialog extends StatefulWidget {
  final MapViewportController viewport;
  final int dimension;
  final void Function(int dim)? onDimensionChanged;

  const EntityFinderDialog({
    super.key,
    required this.viewport,
    required this.dimension,
    this.onDimensionChanged,
  });

  @override
  State<EntityFinderDialog> createState() => _EntityFinderDialogState();
}

class _EntityFinderDialogState extends State<EntityFinderDialog> {
  String _searchQuery = '';
  EntityCategory? _selectedCategory;
  List<WorldEntity> _allEntities = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEntities();
  }

  void _loadEntities() {
    final dm = context.read<DataManager>();
    final list = EntityService().parseAllEntities(dm);
    setState(() {
      _allEntities = list;
      _loading = false;
    });
  }

  List<WorldEntity> get _filteredEntities {
    final dm = context.read<DataManager>();
    final px = dm.playerX;
    final pz = dm.playerZ;

    var list = _allEntities.where((e) {
      if (e.dimension != widget.dimension) return false;
      if (_selectedCategory != null && e.category != _selectedCategory) return false;
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return e.name.toLowerCase().contains(q) ||
          e.identifier.toLowerCase().contains(q) ||
          e.uniqueId.toLowerCase().contains(q);
    }).toList();

    // 按与玩家的欧几里得距离升序排列
    list.sort((a, b) {
      final distA = (a.x - px) * (a.x - px) + (a.z - pz) * (a.z - pz);
      final distB = (b.x - px) * (b.x - px) + (b.z - pz) * (b.z - pz);
      return distA.compareTo(distB);
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DataManager>();

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: screenWidth > 720 ? 680 : screenWidth * 0.94,
        height: (screenHeight * 0.85).clamp(400.0, 680.0),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 头部标题
            Row(
              children: [
                const Icon(Icons.radar, color: Colors.greenAccent, size: 22),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    '生物雷达查找器',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 12),

            // 搜索栏
            TextField(
              decoration: InputDecoration(
                hintText: '搜索生物名称、类型 ID (如 zombie, cow, villager) 或自定义名称...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _searchQuery = ''))
                    : null,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
            const SizedBox(height: 8),

            // 分类过滤器 Chip 栏
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('全部'),
                    selected: _selectedCategory == null,
                    onSelected: (v) => setState(() => _selectedCategory = null),
                  ),
                  const SizedBox(width: 6),
                  ...EntityCategory.values.where((c) => c != EntityCategory.tileEntity).map((cat) {
                    final count = _allEntities.where((e) => e.dimension == widget.dimension && e.category == cat).length;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        avatar: Icon(cat.icon, size: 14, color: cat.color),
                        label: Text('${cat.label} ($count)'),
                        selected: _selectedCategory == cat,
                        onSelected: (v) => setState(() => _selectedCategory = v ? cat : null),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 列表内容
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredEntities.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.pets, size: 48, color: Colors.grey),
                              const SizedBox(height: 8),
                              Text(_searchQuery.isEmpty ? '当前维度未检测到生物实体' : '未找到匹配的生物', style: const TextStyle(color: Colors.grey)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _filteredEntities.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final ent = _filteredEntities[index];
                            final dx = ent.x - dm.playerX;
                            final dz = ent.z - dm.playerZ;
                            final distBlocks = (dx * dx + dz * dz > 0) ? (dx * dx + dz * dz) : 0.0;

                            return ListTile(
                              leading: Image.asset(
                                ent.iconAssetPath,
                                width: 36,
                                height: 36,
                                errorBuilder: (_, __, ___) => Icon(ent.category.icon, color: ent.category.color, size: 32),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      ent.name,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: ent.category.color.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      ent.category.label,
                                      style: TextStyle(fontSize: 10, color: ent.category.color, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '坐标: X: ${ent.x.toStringAsFixed(1)}, Y: ${ent.y.toStringAsFixed(1)}, Z: ${ent.z.toStringAsFixed(1)} | 距离: ${sqrt(distBlocks).toStringAsFixed(0)} 格 | 生命: ${ent.health.toStringAsFixed(0)}/${ent.maxHealth.toStringAsFixed(0)}',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                  Text('ID: ${ent.identifier}', style: const TextStyle(fontSize: 10, color: Colors.white38)),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.gps_fixed, color: Colors.greenAccent, size: 20),
                                    tooltip: '地图定位到此生物',
                                    onPressed: () {
                                      Navigator.pop(context);
                                      widget.viewport.centerOnBlock(ent.x, ent.z);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.flight_takeoff, color: Colors.blueAccent, size: 20),
                                    tooltip: '传送玩家至此生物',
                                    onPressed: () {
                                      dm.teleportPlayer(ent.x, ent.y, ent.z, ent.dimension);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('已传送玩家至 ${ent.name} (X: ${ent.x.toStringAsFixed(1)}, Z: ${ent.z.toStringAsFixed(1)})')),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_note, color: Colors.amberAccent, size: 20),
                                    tooltip: '编辑生物 NBT',
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => EntityNbtEditorScreen(entity: ent)),
                                      ).then((_) => _loadEntities());
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                                    tooltip: '删除此生物',
                                    onPressed: () => _confirmDelete(ent),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(WorldEntity entity) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除此生物？'),
        content: Text('即将从存档中永久移除 ${entity.name} (X: ${entity.x.toStringAsFixed(1)}, Z: ${entity.z.toStringAsFixed(1)})。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              EntityService().deleteEntity(context.read<DataManager>(), entity);
              _loadEntities();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已成功删除 ${entity.name}')),
              );
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
