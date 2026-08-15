import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/data_manager.dart';
import '../models/world_info.dart';
import '../services/backup_service.dart';
import 'editor_main_screen.dart';

/// 存档详情与备份管理页面
class WorldDetailScreen extends StatefulWidget {
  final WorldInfo worldInfo;
  const WorldDetailScreen({super.key, required this.worldInfo});

  @override
  State<WorldDetailScreen> createState() => _WorldDetailScreenState();
}

class _WorldDetailScreenState extends State<WorldDetailScreen> {
  List<BackupItem> _backups = [];
  bool _loadingBackups = false;

  @override
  void initState() {
    super.initState();
    _refreshBackups();
  }

  void _refreshBackups() {
    setState(() => _loadingBackups = true);
    final backups = BackupService().getBackupsForWorld(widget.worldInfo.folderPath);
    setState(() {
      _backups = backups;
      _loadingBackups = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.worldInfo;

    return Scaffold(
      appBar: AppBar(
        title: Text(info.displayName),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: '导出为 .mcworld',
            onPressed: _exportMcWorld,
          ),
          IconButton(
            icon: const Icon(Icons.backup),
            tooltip: '创建快照备份',
            onPressed: _createBackup,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 头部大卡片 (图标 + 基础属性)
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (info.iconBytes != null)
                  Image.memory(info.iconBytes!, height: 160, fit: BoxFit.cover)
                else
                  Container(
                    height: 120,
                    color: const Color(0xFF2C3E50),
                    child: const Center(
                      child: Icon(Icons.terrain, size: 64, color: Colors.white54),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              info.displayName,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Chip(
                            label: Text(info.versionType.title),
                            backgroundColor: Colors.green.withValues(alpha: 0.2),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      _buildDetailRow('世界种子 (Seed)', '${info.seed}'),
                      _buildDetailRow('游戏模式', info.gameMode.labelZh),
                      _buildDetailRow('游戏难度', info.difficulty.labelZh),
                      _buildDetailRow('最后游玩时间', info.formattedLastPlayed),
                      _buildDetailRow('存档占用大小', info.formattedSize),
                      _buildDetailRow('存档目录', info.folderPath),
                      if (info.playerX != null)
                        _buildDetailRow('玩家最后坐标', 'X: ${info.playerX!.toStringAsFixed(1)}, Y: ${info.playerY!.toStringAsFixed(1)}, Z: ${info.playerZ!.toStringAsFixed(1)} (维度: ${info.playerDimension})'),

                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.edit_note, size: 22),
                          label: const Text('进入世界编辑器 (Open Map & NBT)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: const Color(0xFF2E7D32),
                          ),
                          onPressed: _openEditor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 历史备份列表
          Row(
            children: [
              const Text('历史快照备份', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('立即备份'),
                onPressed: _createBackup,
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_loadingBackups)
            const Center(child: CircularProgressIndicator())
          else if (_backups.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text('暂无历史备份，建议在修改前先创建一个备份。', style: TextStyle(color: Colors.grey)),
                ),
              ),
            )
          else
            ..._backups.map(
              (b) => Card(
                child: ListTile(
                  leading: const Icon(Icons.history, color: Colors.blueAccent),
                  title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('时间: ${b.formattedTime}   大小: ${b.formattedSize}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.restore, color: Colors.amberAccent),
                        tooltip: '还原此备份',
                        onPressed: () => _confirmRestore(b),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        tooltip: '删除备份',
                        onPressed: () async {
                          await BackupService().deleteBackup(b.path);
                          _refreshBackups();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
        ],
      ),
    );
  }

  void _openEditor() async {
    final dm = context.read<DataManager>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在加载 LevelDB 与区块数据...'),
              ],
            ),
          ),
        ),
      ),
    );

    final ok = await dm.loadWorld(widget.worldInfo.folderPath);
    if (mounted) {
      Navigator.pop(context); // 关掉 loading 弹窗
      if (ok) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const EditorMainScreen()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(dm.error ?? '加载失败')),
        );
      }
    }
  }

  void _createBackup() async {
    try {
      final backupPath = await BackupService().createSnapshotBackup(widget.worldInfo.folderPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('快照备份创建成功: $backupPath')),
        );
      }
      _refreshBackups();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建备份失败: $e')),
        );
      }
    }
  }

  void _exportMcWorld() async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '导出 .mcworld 存档',
      fileName: '${widget.worldInfo.displayName}.mcworld',
      type: FileType.custom,
      allowedExtensions: ['mcworld'],
    );
    if (result != null) {
      await BackupService().exportToMcWorld(widget.worldInfo.folderPath, result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已成功导出: $result')),
        );
      }
    }
  }

  void _confirmRestore(BackupItem backup) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认还原此备份？', style: TextStyle(color: Colors.amberAccent)),
        content: Text('还原将使用备份 "${backup.name}" 覆盖当前世界数据。建议先备份当前状态。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await BackupService().restoreBackup(backup.path, widget.worldInfo.folderPath);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('备份还原完成！')),
                );
              }
            },
            child: const Text('确认还原'),
          ),
        ],
      ),
    );
  }
}
