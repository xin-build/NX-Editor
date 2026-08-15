import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data/data_manager.dart';
import '../nbt/nbt_clipboard.dart';
import '../nbt/nbt_parser.dart';
import '../nbt/nbt_tags.dart';

/// 全功能 NBT 树形编辑器组件 (支持 12 种标签类型增删改查、NBT 导入/导出、复制/粘贴与跨节点复制)
class NbtTreeWidget extends StatefulWidget {
  final String nbtKey;
  final NbtCompound root;
  final VoidCallback? onSaved;

  const NbtTreeWidget({
    super.key,
    required this.nbtKey,
    required this.root,
    this.onSaved,
  });

  @override
  State<NbtTreeWidget> createState() => _NbtTreeWidgetState();
}

class _NbtTreeWidgetState extends State<NbtTreeWidget> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filterText = '';
  final Set<String> _expandedPaths = {'root'};
  bool _hexMode = false;
  final NbtClipboard _clipboard = NbtClipboard();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DataManager>();

    return Column(
      children: [
        // 顶部工具栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          color: const Color(0xFF222630),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 450;

              return Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: '搜索键名或数值...',
                        prefixIcon: const Icon(Icons.search, size: 16),
                        suffixIcon: _filterText.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _filterText = '');
                                },
                              )
                            : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (val) => setState(() => _filterText = val.trim().toLowerCase()),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: Icon(_hexMode ? Icons.pin : Icons.numbers, size: 18),
                    tooltip: _hexMode ? '十进制显示' : '十六进制显示',
                    onPressed: () => setState(() => _hexMode = !_hexMode),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_box, color: Colors.greenAccent, size: 18),
                    tooltip: '在根节点新建子标签',
                    onPressed: () => _showAddTagDialog(widget.root, []),
                  ),
                  IconButton(
                    icon: const Icon(Icons.file_upload, color: Colors.cyanAccent, size: 18),
                    tooltip: '导入 .nbt / .dat 文件',
                    onPressed: () => _importNbtFile(dm, parentPath: []),
                  ),
                  if (!isNarrow) ...[
                    IconButton(
                      icon: const Icon(Icons.file_download, color: Colors.amberAccent, size: 18),
                      tooltip: '导出为 .nbt 文件',
                      onPressed: _exportNbtFile,
                    ),
                    IconButton(
                      icon: const Icon(Icons.unfold_more, size: 18),
                      tooltip: '展开全部',
                      onPressed: () => setState(() => _expandAll(widget.root, 'root')),
                    ),
                    IconButton(
                      icon: const Icon(Icons.unfold_less, size: 18),
                      tooltip: '折叠全部',
                      onPressed: () {
                        setState(() {
                          _expandedPaths.clear();
                          _expandedPaths.add('root');
                        });
                      },
                    ),
                  ] else ...[
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18),
                      tooltip: '更多操作',
                      onSelected: (val) {
                        if (val == 'export') {
                          _exportNbtFile();
                        } else if (val == 'expand') {
                          setState(() => _expandAll(widget.root, 'root'));
                        } else if (val == 'collapse') {
                          setState(() {
                            _expandedPaths.clear();
                            _expandedPaths.add('root');
                          });
                        }
                      },
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(
                          value: 'export',
                          child: Row(
                            children: [
                              Icon(Icons.file_download, color: Colors.amberAccent, size: 18),
                              SizedBox(width: 8),
                              Text('导出为 .nbt 文件'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'expand',
                          child: Row(
                            children: [
                              Icon(Icons.unfold_more, size: 18),
                              SizedBox(width: 8),
                              Text('展开全部节点'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'collapse',
                          child: Row(
                            children: [
                              Icon(Icons.unfold_less, size: 18),
                              SizedBox(width: 8),
                              Text('折叠全部节点'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ),

        // 剪贴板状态快捷横幅 (如果有复制的内容)
        if (_clipboard.hasItem)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: const Color(0x332196F3),
            child: Row(
              children: [
                const Icon(Icons.content_paste, size: 14, color: Colors.blueAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '剪贴板: ${_clipboard.name ?? "元素"} (${NbtTagType.getTypeName(_clipboard.type ?? 0)})',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                  onPressed: () => _pasteIntoTag(widget.root, []),
                  child: const Text('粘贴至根', style: TextStyle(fontSize: 11, color: Colors.greenAccent)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 14, color: Colors.grey),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: '清空剪贴板',
                  onPressed: () => setState(() => _clipboard.clear()),
                ),
              ],
            ),
          ),

        // NBT 树列表
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _buildNode(
                name: widget.nbtKey,
                tag: widget.root,
                path: [],
                pathStr: 'root',
                isRoot: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _expandAll(NbtTag tag, String pathStr) {
    _expandedPaths.add(pathStr);
    if (tag is NbtCompound) {
      tag.value.forEach((k, v) {
        _expandAll(v, '$pathStr/$k');
      });
    } else if (tag is NbtList) {
      for (int i = 0; i < tag.value.length; i++) {
        _expandAll(tag.value[i], '$pathStr/[$i]');
      }
    }
  }

  Widget _buildNode({
    required String name,
    required NbtTag tag,
    required List<String> path,
    required String pathStr,
    bool isRoot = false,
  }) {
    final isCompound = tag is NbtCompound;
    final isList = tag is NbtList;
    final isExpandable = isCompound || isList;
    final isExpanded = _expandedPaths.contains(pathStr);

    // 过滤匹配
    if (_filterText.isNotEmpty) {
      final nameMatches = name.toLowerCase().contains(_filterText);
      final valMatches = _formatValue(tag).toLowerCase().contains(_filterText);
      if (!nameMatches && !valMatches && !isExpandable) {
        return const SizedBox.shrink();
      }
    }

    final depth = path.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            if (isExpandable) {
              setState(() {
                if (isExpanded) {
                  _expandedPaths.remove(pathStr);
                } else {
                  _expandedPaths.add(pathStr);
                }
              });
            } else {
              _editTagValue(name, tag, path);
            }
          },
          onSecondaryTapDown: (details) {
            _showNodeContextMenu(details.globalPosition, name, tag, path);
          },
          onLongPress: () {
            _showNodeContextMenu(Offset.zero, name, tag, path);
          },
          child: Padding(
            padding: EdgeInsets.only(left: depth * 16.0, top: 3.0, bottom: 3.0),
            child: Row(
              children: [
                if (isExpandable)
                  Icon(
                    isExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                    size: 18,
                    color: Colors.grey,
                  )
                else
                  const SizedBox(width: 18),

                // 标签类型徽章
                _buildTagBadge(tag.type),
                const SizedBox(width: 6),

                // 标签名
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: isExpandable ? FontWeight.bold : FontWeight.w500,
                    color: isRoot ? Colors.amberAccent : Colors.white,
                    fontSize: 13,
                  ),
                ),

                const SizedBox(width: 8),

                // 标签值
                Expanded(
                  child: Text(
                    _formatValue(tag),
                    style: TextStyle(
                      color: isExpandable ? Colors.grey : _getValueColor(tag.type),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // 行末操作菜单按钮
                IconButton(
                  icon: const Icon(Icons.more_horiz, size: 16, color: Colors.white38),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  tooltip: '标签操作菜单',
                  onPressed: () {
                    _showNodeContextMenu(Offset.zero, name, tag, path);
                  },
                ),
              ],
            ),
          ),
        ),

        // 子节点递归展开
        if (isExpandable && isExpanded) ...[
          if (tag is NbtCompound)
            for (final entry in tag.value.entries)
              _buildNode(
                name: entry.key,
                tag: entry.value,
                path: [...path, entry.key],
                pathStr: '$pathStr/${entry.key}',
              ),
          if (tag is NbtList)
            for (int i = 0; i < tag.value.length; i++)
              _buildNode(
                name: '[$i]',
                tag: tag.value[i],
                path: [...path, '$i'],
                pathStr: '$pathStr/[$i]',
              ),
        ],
      ],
    );
  }

  Widget _buildTagBadge(int type) {
    final label = NbtTagType.getTypeBadge(type);
    Color color = Colors.grey;

    switch (type) {
      case NbtTagType.byte: color = const Color(0xFF4CAF50); break;
      case NbtTagType.short: color = const Color(0xFF009688); break;
      case NbtTagType.intValue: color = const Color(0xFF2196F3); break;
      case NbtTagType.long: color = const Color(0xFF3F51B5); break;
      case NbtTagType.float: color = const Color(0xFFFF9800); break;
      case NbtTagType.double: color = const Color(0xFFFF5722); break;
      case NbtTagType.byteArray: color = const Color(0xFF8BC34A); break;
      case NbtTagType.string: color = const Color(0xFFE91E63); break;
      case NbtTagType.list: color = const Color(0xFF9C27B0); break;
      case NbtTagType.compound: color = const Color(0xFFFFC107); break;
      case NbtTagType.intArray: color = const Color(0xFF03A9F4); break;
      case NbtTagType.longArray: color = const Color(0xFF673AB7); break;
      case NbtTagType.shortArray: color = const Color(0xFF00BCD4); break;
    }

    return Tooltip(
      message: '${NbtTagType.getTypeName(type)}\n${NbtTagType.getTypeDescription(type)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  String _formatValue(NbtTag tag) {
    if (tag is NbtByte) {
      if (_hexMode) return '0x${tag.value.toRadixString(16).padLeft(2, '0').toUpperCase()} (${tag.value})';
      return '${tag.value}b';
    }
    if (tag is NbtShort) return '${tag.value}s';
    if (tag is NbtInt) {
      if (_hexMode) return '0x${tag.value.toRadixString(16).toUpperCase()} (${tag.value})';
      return '${tag.value}';
    }
    if (tag is NbtLong) return '${tag.value}L';
    if (tag is NbtFloat) return '${tag.value.toStringAsFixed(3)}f';
    if (tag is NbtDouble) return '${tag.value.toStringAsFixed(3)}d';
    if (tag is NbtString) return '"${tag.value}"';
    if (tag is NbtCompound) return '{${tag.value.length} 个条目}';
    if (tag is NbtList) return '[${tag.value.length} 个元素 (${NbtTagType.getTypeName(tag.elementType)})]';
    if (tag is NbtByteArray) return '[B; ${tag.value.length} 字节]';
    if (tag is NbtIntArray) return '[I; ${tag.value.length} 个整数]';
    if (tag is NbtLongArray) return '[L; ${tag.value.length} 个长整数]';
    if (tag is NbtShortArray) return '[S; ${tag.value.length} 个短整数]';
    return '';
  }

  Color _getValueColor(int type) {
    switch (type) {
      case NbtTagType.string: return const Color(0xFFF48FB1);
      case NbtTagType.byte:
      case NbtTagType.short:
      case NbtTagType.intValue:
      case NbtTagType.long:
        return const Color(0xFF90CAF9);
      case NbtTagType.float:
      case NbtTagType.double:
        return const Color(0xFFFFCC80);
      default:
        return Colors.white70;
    }
  }

  // ─── 节点上下文操作菜单 ───

  void _showNodeContextMenu(Offset globalPos, String name, NbtTag tag, List<String> path) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = globalPos != Offset.zero
        ? RelativeRect.fromRect(Rect.fromLTWH(globalPos.dx, globalPos.dy, 1, 1), Offset.zero & overlay.size)
        : RelativeRect.fromRect(Rect.fromCenter(center: overlay.size.center(Offset.zero), width: 1, height: 1), Offset.zero & overlay.size);

    final dm = context.read<DataManager>();

    showMenu<dynamic>(
      context: context,
      position: position,
      items: <PopupMenuEntry<dynamic>>[
        // 1. 如果是 Compound：新建子标签 / 粘贴到此 / 导入 NBT
        if (tag is NbtCompound) ...[
          PopupMenuItem(
            child: const ListTile(
              leading: Icon(Icons.add_circle, color: Colors.greenAccent),
              title: Text('新建子标签 (New Tag)'),
              dense: true,
            ),
            onTap: () => Future.delayed(Duration.zero, () => _showAddTagDialog(tag, path)),
          ),
          if (_clipboard.hasItem)
            PopupMenuItem(
              child: ListTile(
                leading: const Icon(Icons.content_paste, color: Colors.blueAccent),
                title: Text('粘贴标签 "${_clipboard.name}" 到此 Compound'),
                dense: true,
              ),
              onTap: () => Future.delayed(Duration.zero, () => _pasteIntoTag(tag, path)),
            ),
          PopupMenuItem(
            child: const ListTile(
              leading: Icon(Icons.file_upload, color: Colors.cyanAccent),
              title: Text('导入 .nbt 文件到此节点...'),
              dense: true,
            ),
            onTap: () => Future.delayed(Duration.zero, () => _importNbtFile(dm, parentPath: path)),
          ),
          const PopupMenuDivider(),
        ],

        // 2. 如果是 List：新建/追加元素 / 粘贴到此
        if (tag is NbtList) ...[
          PopupMenuItem(
            child: const ListTile(
              leading: Icon(Icons.add, color: Colors.greenAccent),
              title: Text('追加列表元素 (Append Element)'),
              dense: true,
            ),
            onTap: () => Future.delayed(Duration.zero, () => _showAddListElementDialog(tag, path)),
          ),
          if (_clipboard.hasItem)
            PopupMenuItem(
              child: ListTile(
                leading: const Icon(Icons.content_paste, color: Colors.blueAccent),
                title: Text('粘贴标签 "${_clipboard.name}" 到列表尾部'),
                dense: true,
              ),
              onTap: () => Future.delayed(Duration.zero, () => _pasteIntoTag(tag, path)),
            ),
          const PopupMenuDivider(),
        ],

        // 3. 通用值修改 (非 Compound/List 根)
        if (tag is! NbtCompound && tag is! NbtList)
          PopupMenuItem(
            child: const ListTile(
              leading: Icon(Icons.edit, color: Colors.orangeAccent),
              title: Text('修改标签值 (Edit Value)'),
              dense: true,
            ),
            onTap: () => Future.delayed(Duration.zero, () => _editTagValue(name, tag, path)),
          ),

        // 4. 重命名键名 (如果不是根节点且父节点是 Compound)
        if (path.isNotEmpty)
          PopupMenuItem(
            child: const ListTile(
              leading: Icon(Icons.drive_file_rename_outline, color: Colors.amberAccent),
              title: Text('重命名键名 (Rename Key)'),
              dense: true,
            ),
            onTap: () => Future.delayed(Duration.zero, () => _showRenameKeyDialog(name, path)),
          ),

        // 5. 复制标签 (内存 NBT 剪贴板 + 系统剪贴板 JSON)
        PopupMenuItem(
          child: const ListTile(
            leading: Icon(Icons.copy, color: Colors.blueAccent),
            title: Text('复制此标签 (Copy Tag)'),
            dense: true,
          ),
          onTap: () => _copyTag(name, tag, path),
        ),

        // 6. 复制到其他标签下... (跨路径选择器)
        PopupMenuItem(
          child: const ListTile(
            leading: Icon(Icons.drive_file_move_rtl, color: Colors.tealAccent),
            title: Text('复制到某标签下... (Copy To...)'),
            dense: true,
          ),
          onTap: () => Future.delayed(Duration.zero, () => _showCopyToTargetDialog(name, tag)),
        ),

        // 7. 导出此节点为 .nbt
        PopupMenuItem(
          child: const ListTile(
            leading: Icon(Icons.file_download, color: Colors.amberAccent),
            title: Text('导出此节点为 .nbt'),
            dense: true,
          ),
          onTap: () => _exportSubTagFile(name, tag),
        ),

        // 8. 复制为 JSON / SNBT
        PopupMenuItem(
          child: const ListTile(
            leading: Icon(Icons.code, color: Colors.purpleAccent),
            title: Text('复制为 JSON 字符串'),
            dense: true,
          ),
          onTap: () {
            Clipboard.setData(ClipboardData(text: tag.toJsonString()));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已复制 NBT JSON 字符串至剪贴板')),
            );
          },
        ),

        // 9. 删除此标签
        if (path.isNotEmpty) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            child: const ListTile(
              leading: Icon(Icons.delete, color: Colors.redAccent),
              title: Text('删除此标签 (Delete)'),
              dense: true,
            ),
            onTap: () => _deleteTag(path, tag),
          ),
        ],
      ],
    );
  }

  // ─── 复制与粘贴核心 ───

  void _copyTag(String name, NbtTag tag, List<String> path) {
    _clipboard.copy(name, tag, sourceKey: widget.nbtKey, sourcePath: path);
    Clipboard.setData(ClipboardData(text: tag.toJsonString()));
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制标签 "$name" (${NbtTagType.getTypeName(tag.type)}) 至剪贴板！'),
        action: SnackBarAction(
          label: '查看 JSON',
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('$name JSON 数据'),
                content: SingleChildScrollView(child: SelectableText(tag.toJsonString())),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
              ),
            );
          },
        ),
      ),
    );
  }

  void _pasteIntoTag(NbtTag targetTag, List<String> targetPath) {
    if (!_clipboard.hasItem) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('剪贴板为空，请先复制标签！')));
      return;
    }

    final dm = context.read<DataManager>();
    final tagToPaste = _clipboard.tag!;
    final initialName = _clipboard.name ?? 'tag_pasted';

    if (targetTag is NbtCompound) {
      // 检查键名冲突
      if (targetTag.value.containsKey(initialName)) {
        final nameCtrl = TextEditingController(text: '${initialName}_copy');
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('键名已存在，请输入新键名'),
            content: TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '新标签键名', border: OutlineInputBorder()),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  final newKey = nameCtrl.text.trim();
                  if (newKey.isNotEmpty) {
                    dm.commitNbtAddition(widget.nbtKey, targetPath, newKey, tagToPaste);
                    setState(() {});
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('确认粘贴'),
              ),
            ],
          ),
        );
      } else {
        dm.commitNbtAddition(widget.nbtKey, targetPath, initialName, tagToPaste);
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已将 "$initialName" 粘贴至目标 Compound！')),
        );
      }
    } else if (targetTag is NbtList) {
      dm.commitNbtAddition(widget.nbtKey, targetPath, '${targetTag.value.length}', tagToPaste);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已将标签追加至目标 List 列表尾部！')),
      );
    }
  }

  // ─── 跨节点复制弹窗: 复制到某标签下 ───

  void _showCopyToTargetDialog(String sourceName, NbtTag sourceTag) {
    final containers = <MapEntry<String, List<String>>>[];

    void collectContainers(NbtTag current, List<String> path, String label) {
      if (current is NbtCompound) {
        containers.add(MapEntry(label.isEmpty ? '根节点 (Root Compound)' : label, List.from(path)));
        current.value.forEach((k, v) {
          if (v is NbtCompound || v is NbtList) {
            collectContainers(v, [...path, k], label.isEmpty ? k : '$label / $k');
          }
        });
      } else if (current is NbtList) {
        containers.add(MapEntry('$label [TAG_List]', List.from(path)));
        for (int i = 0; i < current.value.length; i++) {
          final item = current.value[i];
          if (item is NbtCompound || item is NbtList) {
            collectContainers(item, [...path, '$i'], '$label / [$i]');
          }
        }
      }
    }

    collectContainers(widget.root, [], '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.drive_file_move_rtl, color: Colors.tealAccent),
            const SizedBox(width: 8),
            Flexible(child: Text('复制 "$sourceName" 到指定标签下', overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: SizedBox(
          width: 480,
          height: 380,
          child: containers.isEmpty
              ? const Center(child: Text('没有可用的目标 Compound 或 List 容器'))
              : ListView.builder(
                  itemCount: containers.length,
                  itemBuilder: (ctx, index) {
                    final item = containers[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.folder, color: Colors.amberAccent),
                        title: Text(item.key, style: const TextStyle(fontSize: 13)),
                        subtitle: Text('路径: /${item.value.join('/')}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                        onTap: () {
                          Navigator.pop(ctx);
                          final dm = context.read<DataManager>();
                          dm.commitNbtAddition(widget.nbtKey, item.value, sourceName, sourceTag.clone());
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('已将 "$sourceName" 复制并挂载到 /${item.value.join('/')}')),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ],
      ),
    );
  }

  // ─── 新建标签弹窗 (全量 12 种 Minecraft 标签类别) ───

  void _showAddTagDialog(NbtCompound parentComp, List<String> parentPath) {
    final nameCtrl = TextEditingController(text: 'new_tag');
    final valCtrl = TextEditingController(text: '0');
    int selectedType = NbtTagType.string;

    final availableTypes = [
      NbtTagType.byte,
      NbtTagType.short,
      NbtTagType.intValue,
      NbtTagType.long,
      NbtTagType.float,
      NbtTagType.double,
      NbtTagType.byteArray,
      NbtTagType.string,
      NbtTagType.list,
      NbtTagType.compound,
      NbtTagType.intArray,
      NbtTagType.longArray,
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.add_circle, color: Colors.greenAccent),
              SizedBox(width: 8),
              Text('新建 NBT 标签'),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '标签键名 (Key Name)',
                      hintText: '如 CustomName, Health, Pos, Items 等',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 标签类型下拉选择
                  DropdownButtonFormField<int>(
                    value: selectedType,
                    decoration: const InputDecoration(
                      labelText: '标签类别 (TAG_Type)',
                      border: OutlineInputBorder(),
                    ),
                    items: availableTypes.map((t) {
                      return DropdownMenuItem<int>(
                        value: t,
                        child: Row(
                          children: [
                            _buildTagBadge(t),
                            const SizedBox(width: 8),
                            Text(NbtTagType.getTypeChineseName(t), style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setDialogState(() {
                          selectedType = v;
                          if (v == NbtTagType.string) {
                            valCtrl.text = '';
                          } else if (v == NbtTagType.float || v == NbtTagType.double) {
                            valCtrl.text = '0.0';
                          } else if (v == NbtTagType.byteArray || v == NbtTagType.intArray || v == NbtTagType.longArray) {
                            valCtrl.text = '0, 0, 0';
                          } else {
                            valCtrl.text = '0';
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),

                  // 类型说明卡片
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1F27),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      NbtTagType.getTypeDescription(selectedType),
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 初始值输入框 (如果不是 Compound 或 List)
                  if (selectedType != NbtTagType.compound && selectedType != NbtTagType.list)
                    TextField(
                      controller: valCtrl,
                      decoration: InputDecoration(
                        labelText: '初始值',
                        hintText: (selectedType == NbtTagType.byteArray || selectedType == NbtTagType.intArray || selectedType == NbtTagType.longArray)
                            ? '以英文逗号分隔，如 1, 2, 3'
                            : '输入标签初始数值或文本',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton.icon(
              icon: const Icon(Icons.check, size: 16),
              label: const Text('创建标签'),
              onPressed: () {
                final k = nameCtrl.text.trim();
                if (k.isNotEmpty) {
                  final newChild = _createTagFromInput(selectedType, valCtrl.text.trim());
                  final dm = context.read<DataManager>();
                  dm.commitNbtAddition(widget.nbtKey, parentPath, k, newChild);
                  setState(() {});
                }
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── 追加列表元素弹窗 ───

  void _showAddListElementDialog(NbtList parentList, List<String> parentPath) {
    final valCtrl = TextEditingController(text: '0');
    final elemType = parentList.elementType == 0 ? NbtTagType.string : parentList.elementType;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('追加 List 元素 (${NbtTagType.getTypeName(elemType)})'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('当前列表已有 ${parentList.value.length} 个元素，新元素将追加至末尾。', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            if (elemType != NbtTagType.compound && elemType != NbtTagType.list)
              TextField(
                controller: valCtrl,
                decoration: const InputDecoration(labelText: '元素初始值', border: OutlineInputBorder()),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final newChild = _createTagFromInput(elemType, valCtrl.text.trim());
              final dm = context.read<DataManager>();
              dm.commitNbtAddition(widget.nbtKey, parentPath, '${parentList.value.length}', newChild);
              setState(() {});
              Navigator.pop(ctx);
            },
            child: const Text('追加'),
          ),
        ],
      ),
    );
  }

  // ─── 重命名键名弹窗 ───

  void _showRenameKeyDialog(String oldName, List<String> path) {
    final nameCtrl = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('重命名键名: $oldName'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: '新键名', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final newName = nameCtrl.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                _renameKey(path, oldName, newName);
              }
              Navigator.pop(ctx);
            },
            child: const Text('确认修改'),
          ),
        ],
      ),
    );
  }

  void _renameKey(List<String> path, String oldKey, String newKey) {
    final dm = context.read<DataManager>();
    final parentPath = path.sublist(0, path.length - 1);
    NbtTag current = widget.root;
    for (final seg in parentPath) {
      if (current is NbtCompound) {
        current = current.value[seg]!;
      } else if (current is NbtList) {
        current = current.value[int.parse(seg)];
      }
    }

    if (current is NbtCompound) {
      final tag = current.value[oldKey];
      if (tag != null) {
        dm.commitNbtDeletion(widget.nbtKey, path, tag);
        dm.commitNbtAddition(widget.nbtKey, parentPath, newKey, tag);
        setState(() {});
      }
    }
  }

  // ─── 编辑标签值 ───

  void _editTagValue(String name, NbtTag tag, List<String> path) {
    final ctrl = TextEditingController(text: _getRawValueString(tag));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            _buildTagBadge(tag.type),
            const SizedBox(width: 8),
            Expanded(child: Text('修改 $name 的值', overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('类型: ${NbtTagType.getTypeName(tag.type)} (${NbtTagType.getTypeChineseName(tag.type)})', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: '新数值 / 文本', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final newTag = _parseTagFromString(tag.type, ctrl.text.trim());
              if (newTag != null) {
                final dm = context.read<DataManager>();
                dm.commitNbtModification(widget.nbtKey, path, tag, newTag);
                setState(() {});
              }
              Navigator.pop(ctx);
            },
            child: const Text('保存修改'),
          ),
        ],
      ),
    );
  }

  // ─── 删除标签 ───

  void _deleteTag(List<String> path, NbtTag tag) {
    if (path.isEmpty) return;

    final dm = context.read<DataManager>();
    final last = path.last;
    dm.commitNbtDeletion(widget.nbtKey, path, tag);
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除标签 "$last"'),
        action: SnackBarAction(
          label: '撤销 (Undo)',
          onPressed: () {
            dm.undo();
            setState(() {});
          },
        ),
      ),
    );
  }

  // ─── 导入 / 导出 NBT 文件 ───

  void _importNbtFile(DataManager dm, {required List<String> parentPath}) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择要导入的 NBT 文件',
      type: FileType.any,
    );

    if (result != null && result.files.single.path != null) {
      try {
        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();
        final parsed = LittleEndianNbtParser.parseAnyNbt(bytes);
        final importedCompound = parsed.value;

        if (parentPath.isEmpty) {
          // 根节点导入：提供覆盖或合并选项
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('导入 NBT 数据'),
                content: Text('成功解析 "${result.files.single.name}" (共 ${importedCompound.value.length} 个条目)。\n请选择导入方式：'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      // 合并
                      importedCompound.value.forEach((k, v) {
                        dm.commitNbtAddition(widget.nbtKey, [], k, v);
                      });
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('NBT 条目已合并到当前根节点！')),
                      );
                    },
                    child: const Text('合并条目 (Merge)'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      dm.commitNbtReplaceRoot(widget.nbtKey, widget.root, importedCompound);
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已使用导入的 NBT 完全覆盖替换！')),
                      );
                    },
                    child: const Text('完全覆盖 (Replace)'),
                  ),
                ],
              ),
            );
          }
        } else {
          // 导入到子 Compound
          final targetName = result.files.single.name.replaceAll(RegExp(r'\.[^.]+$'), '');
          dm.commitNbtAddition(widget.nbtKey, parentPath, targetName, importedCompound);
          setState(() {});
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已导入 "$targetName" 到当前节点下！')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入 NBT 失败: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _exportNbtFile() async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '导出 NBT 文件',
      fileName: '${widget.nbtKey.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.nbt',
      type: FileType.custom,
      allowedExtensions: ['nbt'],
    );
    if (result != null) {
      final writer = LittleEndianNbtWriter();
      final bytes = writer.writeRoot(widget.nbtKey, widget.root);
      final file = File(result);
      await file.writeAsBytes(bytes, flush: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('NBT 文件已保存: $result')),
        );
      }
    }
  }

  void _exportSubTagFile(String name, NbtTag tag) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '导出节点 $name 为 NBT 文件',
      fileName: '$name.nbt',
      type: FileType.custom,
      allowedExtensions: ['nbt'],
    );
    if (result != null) {
      final writer = LittleEndianNbtWriter();
      NbtCompound compToSave;
      if (tag is NbtCompound) {
        compToSave = tag;
      } else {
        compToSave = NbtCompound({name: tag.clone()});
      }
      final bytes = writer.writeRoot(name, compToSave);
      final file = File(result);
      await file.writeAsBytes(bytes, flush: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('节点 NBT 文件已保存: $result')),
        );
      }
    }
  }

  // ─── 帮助与转换工具 ───

  NbtTag _createTagFromInput(int type, String str) {
    if (type == NbtTagType.compound) return NbtCompound({});
    if (type == NbtTagType.list) return NbtList(NbtTagType.string, []);
    return _parseTagFromString(type, str) ?? NbtString(str);
  }

  String _getRawValueString(NbtTag tag) {
    if (tag is NbtByte) return tag.value.toString();
    if (tag is NbtShort) return tag.value.toString();
    if (tag is NbtInt) return tag.value.toString();
    if (tag is NbtLong) return tag.value.toString();
    if (tag is NbtFloat) return tag.value.toString();
    if (tag is NbtDouble) return tag.value.toString();
    if (tag is NbtString) return tag.value;
    if (tag is NbtByteArray) return tag.value.join(', ');
    if (tag is NbtIntArray) return tag.value.join(', ');
    if (tag is NbtLongArray) return tag.value.join(', ');
    if (tag is NbtShortArray) return tag.value.join(', ');
    return '';
  }

  NbtTag? _parseTagFromString(int type, String str) {
    try {
      switch (type) {
        case NbtTagType.byte: return NbtByte(int.parse(str));
        case NbtTagType.short: return NbtShort(int.parse(str));
        case NbtTagType.intValue: return NbtInt(int.parse(str));
        case NbtTagType.long: return NbtLong(int.parse(str));
        case NbtTagType.float: return NbtFloat(double.parse(str));
        case NbtTagType.double: return NbtDouble(double.parse(str));
        case NbtTagType.string: return NbtString(str);
        case NbtTagType.byteArray:
          final parts = str.split(',').map((s) => int.tryParse(s.trim()) ?? 0).toList();
          return NbtByteArray(Uint8List.fromList(parts));
        case NbtTagType.intArray:
          final parts = str.split(',').map((s) => int.tryParse(s.trim()) ?? 0).toList();
          return NbtIntArray(Int32List.fromList(parts));
        case NbtTagType.longArray:
          final parts = str.split(',').map((s) => int.tryParse(s.trim()) ?? 0).toList();
          return NbtLongArray(Int64List.fromList(parts));
        case NbtTagType.shortArray:
          final parts = str.split(',').map((s) => int.tryParse(s.trim()) ?? 0).toList();
          return NbtShortArray(parts);
      }
    } catch (_) {}
    return null;
  }
}
