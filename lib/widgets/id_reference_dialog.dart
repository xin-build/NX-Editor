import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/game_data_service.dart';

/// 游戏全量 ID 对照查询组件与弹窗 (用于 NBT 编辑及游戏查阅)
class IdReferenceDialog extends StatefulWidget {
  const IdReferenceDialog({super.key});

  @override
  State<IdReferenceDialog> createState() => _IdReferenceDialogState();
}

class _IdReferenceDialogState extends State<IdReferenceDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gds = GameDataService();

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: const Color(0xFF1E222B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: screenWidth > 800 ? 780 : screenWidth * 0.94,
        height: (screenHeight * 0.85).clamp(420.0, 680.0),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 顶部标题与关闭
            Row(
              children: [
                const Icon(Icons.menu_book, color: Colors.amberAccent, size: 22),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Minecraft ID 对照字典',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 搜索框
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '输入中文名、英文 ID 或数字 ID 快速检索 (如 钻石、diamond、1、zombie)...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),

            // 标签栏
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(icon: Icon(Icons.grid_view, size: 16), text: '方块 (Blocks)'),
                Tab(icon: Icon(Icons.pets, size: 16), text: '实体与生物 (Entities)'),
                Tab(icon: Icon(Icons.backpack, size: 16), text: '物品 (Items)'),
                Tab(icon: Icon(Icons.forest, size: 16), text: '生态群系 (Biomes)'),
                Tab(icon: Icon(Icons.auto_fix_high, size: 16), text: '魔咒附魔 (Enchantments)'),
                Tab(icon: Icon(Icons.science, size: 16), text: '药水效果 (Effects)'),
              ],
            ),
            const SizedBox(height: 8),

            // 列表内容
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildIdList(gds.blocks, 'block'),
                  _buildIdList(gds.entities, 'entity'),
                  _buildIdList(gds.items, 'item'),
                  _buildIdList(gds.biomes, 'biome'),
                  _buildIdList(gds.enchantments, 'enchantment'),
                  _buildIdList(gds.effects, 'effect'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdList(List<GameIdEntry> list, String type) {
    final filtered = list.where((item) {
      if (_searchQuery.isEmpty) return true;
      return item.name.toLowerCase().contains(_searchQuery) ||
          item.id.toLowerCase().contains(_searchQuery) ||
          item.numId.contains(_searchQuery);
    }).toList();

    if (filtered.isEmpty) {
      return const Center(child: Text('未找到匹配的条目', style: TextStyle(color: Colors.grey)));
    }

    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0x15FFFFFF)),
      itemBuilder: (ctx, i) {
        final item = filtered[i];
        final cleanId = item.id.replaceAll('minecraft:', '');

        return ListTile(
          dense: true,
          leading: _buildThumbnail(type, cleanId),
          title: Row(
            children: [
              Text(item.name.isNotEmpty ? item.name : item.id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 8),
              Text(
                item.id.startsWith('minecraft:') ? item.id : 'minecraft:${item.id}',
                style: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
              ),
            ],
          ),
          subtitle: Text('数字 ID: ${item.numId}${item.hexId != null ? " | Hex: 0x${item.hexId}" : ""}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          trailing: IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: '复制字符串 ID',
            onPressed: () {
              final fullId = item.id.startsWith('minecraft:') ? item.id : 'minecraft:${item.id}';
              Clipboard.setData(ClipboardData(text: fullId));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已复制: $fullId'), duration: const Duration(seconds: 1)),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildThumbnail(String type, String cleanId) {
    String? path;
    if (type == 'block') path = 'assrts/images/block/$cleanId.png';
    if (type == 'entity') path = 'assrts/images/entity/$cleanId.png';
    if (type == 'item') path = 'assrts/images/item/$cleanId.png';

    if (path != null) {
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Image.asset(
          path,
          width: 22,
          height: 22,
          errorBuilder: (_, __, ___) => _defaultIconForType(type),
        ),
      );
    }
    return _defaultIconForType(type);
  }

  Widget _defaultIconForType(String type) {
    IconData icon = Icons.category;
    Color color = Colors.grey;
    if (type == 'block') {
      icon = Icons.grid_view;
      color = Colors.amber;
    } else if (type == 'entity') {
      icon = Icons.pets;
      color = Colors.green;
    } else if (type == 'item') {
      icon = Icons.backpack;
      color = Colors.blue;
    } else if (type == 'biome') {
      icon = Icons.forest;
      color = Colors.teal;
    } else if (type == 'enchantment') {
      icon = Icons.auto_fix_high;
      color = Colors.purpleAccent;
    } else if (type == 'effect') {
      icon = Icons.science;
      color = Colors.pinkAccent;
    }
    return Icon(icon, size: 20, color: color);
  }
}
