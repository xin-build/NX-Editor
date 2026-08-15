import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/world_info.dart';
import '../services/backup_service.dart';
import '../services/storage_service.dart';
import 'create_flat_screen.dart';
import 'settings_screen.dart';
import 'world_detail_screen.dart';

/// 存档选择与管理主界面
class WorldListScreen extends StatefulWidget {
  const WorldListScreen({super.key});

  @override
  State<WorldListScreen> createState() => _WorldListScreenState();
}

class _WorldListScreenState extends State<WorldListScreen> {
  List<WorldInfo> _worlds = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _sortBy = 'time'; // 'time' | 'name' | 'size'

  @override
  void initState() {
    super.initState();
    _loadAllWorlds();
  }

  Future<void> _loadAllWorlds() async {
    setState(() => _isLoading = true);
    final worlds = await StorageService().scanAllWorlds();
    if (mounted) {
      setState(() {
        _worlds = worlds;
        _isLoading = false;
      });
    }
  }

  List<WorldInfo> get _filteredWorlds {
    var list = _worlds.where((w) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return w.displayName.toLowerCase().contains(q) ||
          w.folderName.toLowerCase().contains(q) ||
          w.seed.toString().contains(q);
    }).toList();

    if (_sortBy == 'time') {
      list.sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));
    } else if (_sortBy == 'name') {
      list.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    } else if (_sortBy == 'size') {
      list.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 700;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terrain, color: Colors.greenAccent),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Minecraft 存档管理',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: isDesktop
            ? [
                IconButton(
                  icon: const Icon(Icons.folder_open),
                  tooltip: '选择并打开任意存档文件夹',
                  onPressed: _openCustomFolder,
                ),
                IconButton(
                  icon: const Icon(Icons.file_upload),
                  tooltip: '导入 .mcworld 存档包',
                  onPressed: _importMcWorld,
                ),
                IconButton(
                  icon: const Icon(Icons.add_box),
                  tooltip: '新建自定义超平坦世界',
                  onPressed: () async {
                    final newWorldPath = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(builder: (_) => const CreateFlatScreen()),
                    );
                    if (newWorldPath != null) {
                      _loadAllWorlds();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: '全局设置',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新存档列表',
                  onPressed: _loadAllWorlds,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.folder_open),
                  tooltip: '打开文件夹',
                  onPressed: _openCustomFolder,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新列表',
                  onPressed: _loadAllWorlds,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: '更多选项',
                  onSelected: (val) async {
                    if (val == 'import') {
                      _importMcWorld();
                    } else if (val == 'create') {
                      final newWorldPath = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(builder: (_) => const CreateFlatScreen()),
                      );
                      if (newWorldPath != null) {
                        _loadAllWorlds();
                      }
                    } else if (val == 'settings') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      );
                    }
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(
                      value: 'import',
                      child: Row(
                        children: [
                          Icon(Icons.file_upload, size: 20),
                          SizedBox(width: 10),
                          Text('导入 .mcworld 存档'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'create',
                      child: Row(
                        children: [
                          Icon(Icons.add_box, size: 20),
                          SizedBox(width: 10),
                          Text('新建自定义超平坦世界'),
                        ],
                      ),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
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
              ],
      ),
      body: Column(
        children: [
          // 搜索与排序栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: const Color(0xFF1E222B),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '搜索存档名称、种子或目录名...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () => setState(() => _searchQuery = ''),
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.sort, size: 22),
                  tooltip: '排序方式',
                  initialValue: _sortBy,
                  onSelected: (v) => setState(() => _sortBy = v),
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'time', child: Text('按最后游玩时间')),
                    PopupMenuItem(value: 'name', child: Text('按世界名称')),
                    PopupMenuItem(value: 'size', child: Text('按占用大小')),
                  ],
                ),
              ],
            ),
          ),

          // 存档卡片列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredWorlds.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.folder_off, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text('未找到任何 Minecraft 存档', style: TextStyle(fontSize: 18, color: Colors.grey)),
                            const SizedBox(height: 8),
                            const Text('您可以点击右上角“打开文件夹”或“导入 .mcworld”直接载入存档', style: TextStyle(color: Colors.grey)),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              icon: const Icon(Icons.folder_open),
                              label: const Text('选择本地存档目录'),
                              onPressed: _openCustomFolder,
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadAllWorlds,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredWorlds.length,
                          itemBuilder: (context, index) {
                            final world = _filteredWorlds[index];
                            return _buildWorldCard(world);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorldCard(WorldInfo world) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => WorldDetailScreen(worldInfo: world)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 世界图标
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: world.iconBytes != null
                    ? Image.memory(world.iconBytes!, width: 72, height: 72, fit: BoxFit.cover)
                    : Container(
                        width: 72,
                        height: 72,
                        color: const Color(0xFF2C3E50),
                        child: const Icon(Icons.terrain, size: 36, color: Colors.white54),
                      ),
              ),
              const SizedBox(width: 14),

              // 详情信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            world.displayName,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _buildVersionBadge(world.versionType),
                      ],
                    ),
                    const SizedBox(height: 4),

                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            world.gameMode.labelZh,
                            style: const TextStyle(fontSize: 11, color: Colors.blueAccent),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '种子: ${world.seed}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 13, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          world.formattedLastPlayed,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const Spacer(),
                        const Icon(Icons.storage, size: 13, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          world.formattedSize,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVersionBadge(SaveVersionType type) {
    Color color = Colors.green;
    if (type == SaveVersionType.legacyBedrock) color = Colors.orange;
    if (type == SaveVersionType.ancientPE) color = Colors.purple;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        type.title,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _openCustomFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      final info = await StorageService().parseWorldInfo(result);
      if (info != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => WorldDetailScreen(worldInfo: info)),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('所选目录下未检测到有效的 level.dat 存档文件')),
        );
      }
    }
  }

  void _importMcWorld() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mcworld', 'zip'],
    );
    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;
      final dirs = await StorageService().getSearchDirectories();
      String targetDir;
      if (dirs.isNotEmpty) {
        targetDir = dirs.first;
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        targetDir = appDir.path;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                SizedBox(width: 12),
                Text('正在后台解压并解析 .mcworld 存档...'),
              ],
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }

      try {
        final folderPath = await BackupService().importFromMcWorld(filePath, targetDir);
        final info = await StorageService().parseWorldInfo(folderPath);

        if (info != null && mounted) {
          _loadAllWorlds();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('成功导入存档: ${info.displayName}')),
          );
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => WorldDetailScreen(worldInfo: info)),
          );
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('导入完成，但未能解析到有效的 level.dat 存档数据')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入存档失败: $e'), backgroundColor: Colors.red[800]),
          );
        }
      }
    }
  }
}
