import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/data_manager.dart';
import '../widgets/id_reference_dialog.dart';
import '../widgets/nbt_tree_widget.dart';

/// 全功能 NBT 与数据库浏览器全屏界面 (完美适配 PC 宽屏与移动端窄屏)
class NbtEditorFullScreen extends StatefulWidget {
  final String? initialKey;
  const NbtEditorFullScreen({super.key, this.initialKey});

  @override
  State<NbtEditorFullScreen> createState() => _NbtEditorFullScreenState();
}

class _NbtEditorFullScreenState extends State<NbtEditorFullScreen> with SingleTickerProviderStateMixin {
  String _selectedKey = 'level.dat';
  String _searchFilter = '';
  final TextEditingController _searchCtrl = TextEditingController();
  TabController? _mobileTabController;

  @override
  void initState() {
    super.initState();
    if (widget.initialKey != null) {
      _selectedKey = widget.initialKey!;
    }
    _mobileTabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _mobileTabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DataManager>();
    final categories = dm.getCategorizedDbKeys();
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_tree, color: Colors.amberAccent, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                isDesktop ? '全功能 NBT 与 LevelDB 数据库编辑器' : 'NBT 数据库',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book, color: Colors.amberAccent),
            tooltip: '打开 Minecraft ID 对照速查表',
            onPressed: () {
              showDialog(context: context, builder: (_) => const IdReferenceDialog());
            },
          ),
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: '撤销 (Ctrl+Z)',
            onPressed: dm.canUndo ? dm.undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: '重做 (Ctrl+Y)',
            onPressed: dm.canRedo ? dm.redo : null,
          ),
          if (isDesktop && dm.hasUnsavedChanges)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.amber),
              ),
              child: const Text('已修改', style: TextStyle(fontSize: 11, color: Colors.amberAccent)),
            ),
          IconButton(
            icon: dm.isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(Icons.save, color: dm.hasUnsavedChanges ? Colors.amberAccent : Colors.greenAccent),
            tooltip: '保存所有修改到 LevelDB (Ctrl+S)',
            onPressed: dm.isSaving
                ? null
                : () async {
                    final ok = await dm.saveChanges();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok ? '修改已全部写回 LevelDB 数据库物理文件！' : '保存失败: ${dm.error ?? "未知错误"}'),
                          backgroundColor: ok ? Colors.green : Colors.red,
                        ),
                      );
                    }
                  },
          ),
        ],
        bottom: !isDesktop
            ? TabBar(
                controller: _mobileTabController,
                tabs: const [
                  Tab(icon: Icon(Icons.list_alt), text: '条目目录'),
                  Tab(icon: Icon(Icons.edit_document), text: '数据编辑'),
                ],
              )
            : null,
      ),
      body: isDesktop
          ? Row(
              children: [
                // 桌面端左侧分类目录树
                Container(
                  width: 320,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1F27),
                    border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                  ),
                  child: _buildCategoryList(categories),
                ),
                // 桌面端右侧 NBT 编辑区
                Expanded(
                  child: _buildNbtEditorArea(dm, isDesktop: true),
                ),
              ],
            )
          : TabBarView(
              controller: _mobileTabController,
              children: [
                // 移动端 Tab 1: 条目分类列表
                Container(
                  color: const Color(0xFF1B1F27),
                  child: _buildCategoryList(categories, onItemSelected: (key) {
                    setState(() => _selectedKey = key);
                    _mobileTabController?.animateTo(1);
                  }),
                ),
                // 移动端 Tab 2: NBT 编辑区
                _buildNbtEditorArea(dm, isDesktop: false),
              ],
            ),
    );
  }

  Widget _buildCategoryList(Map<String, List<MapEntry<String, String>>> categories, {ValueChanged<String>? onItemSelected}) {
    return Column(
      children: [
        // 搜索框
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索数据库键名...',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchFilter.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchFilter = '');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (v) => setState(() => _searchFilter = v.trim().toLowerCase()),
          ),
        ),

        // 分类列表
        Expanded(
          child: ListView(
            children: categories.entries.map((cat) {
              final filteredItems = cat.value.where((item) {
                if (_searchFilter.isEmpty) return true;
                return item.key.toLowerCase().contains(_searchFilter) ||
                    item.value.toLowerCase().contains(_searchFilter);
              }).toList();

              if (filteredItems.isEmpty && _searchFilter.isNotEmpty) {
                return const SizedBox.shrink();
              }

              return ExpansionTile(
                initiallyExpanded: true,
                leading: _getCategoryIcon(cat.key),
                title: Text(
                  '${cat.key} (${filteredItems.length})',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                children: filteredItems.map((item) {
                  final isSelected = _selectedKey == item.key;
                  return ListTile(
                    dense: true,
                    selected: isSelected,
                    selectedTileColor: const Color(0x334CAF50),
                    title: Text(
                      item.value,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected ? Colors.greenAccent : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      setState(() => _selectedKey = item.key);
                      if (onItemSelected != null) {
                        onItemSelected(item.key);
                      }
                    },
                  );
                }).toList(),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildNbtEditorArea(DataManager dm, {required bool isDesktop}) {
    final root = dm.getNbtCompound(_selectedKey);

    if (root == null) {
      final rawBytes = dm.rawEntries[_selectedKey] ??
          (dm.rawEntries.containsKey(base64Encode(utf8.encode(_selectedKey)))
              ? dm.rawEntries[base64Encode(utf8.encode(_selectedKey))]
              : null);
      if (rawBytes != null) {
        return _buildHexViewer(_selectedKey, rawBytes);
      }
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text('未找到 $_selectedKey 的数据', style: const TextStyle(color: Colors.grey)),
            if (!isDesktop) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.list_alt, size: 16),
                label: const Text('返回条目目录'),
                onPressed: () => _mobileTabController?.animateTo(0),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        // 面板头部 (显示当前编辑键与快捷切换)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: const Color(0xFF222630),
          child: Row(
            children: [
              const Icon(Icons.label, color: Colors.amberAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '正在编辑: $_selectedKey',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (!isDesktop)
                TextButton.icon(
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('选其他', style: TextStyle(fontSize: 12)),
                  onPressed: () => _mobileTabController?.animateTo(0),
                ),
            ],
          ),
        ),

        // NBT 树形编辑核心
        Expanded(
          child: NbtTreeWidget(
            nbtKey: _selectedKey,
            root: root,
            onSaved: () => setState(() {}),
          ),
        ),
      ],
    );
  }

  Widget _buildHexViewer(String key, List<int> bytes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF222630),
          child: Text('原始二进制 Hex 视图 ($key, 共 ${bytes.length} 字节)', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              _formatHex(bytes),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  String _formatHex(List<int> bytes) {
    final sb = StringBuffer();
    for (int i = 0; i < bytes.length && i < 2048; i += 16) {
      final hexPart = bytes.sublist(i, (i + 16 > bytes.length ? bytes.length : i + 16))
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
      final asciiPart = bytes.sublist(i, (i + 16 > bytes.length ? bytes.length : i + 16))
          .map((b) => (b >= 32 && b <= 126) ? String.fromCharCode(b) : '.')
          .join('');
      sb.writeln('${i.toRadixString(16).padLeft(6, '0').toUpperCase()}:  ${hexPart.padRight(48)}  |$asciiPart|');
    }
    if (bytes.length > 2048) {
      sb.writeln('... (余下 ${bytes.length - 2048} 字节已截断)');
    }
    return sb.toString();
  }

  Widget _getCategoryIcon(String cat) {
    switch (cat) {
      case '世界核心数据': return const Icon(Icons.public, color: Colors.greenAccent, size: 18);
      case '多人游戏玩家': return const Icon(Icons.group, color: Colors.blueAccent, size: 18);
      case '生物与实体': return const Icon(Icons.pets, color: Colors.redAccent, size: 18);
      case '方块实体': return const Icon(Icons.inventory_2, color: Colors.amberAccent, size: 18);
      case '维度与全局': return const Icon(Icons.landscape, color: Colors.purpleAccent, size: 18);
      case '村庄与聚集地': return const Icon(Icons.home_work, color: Colors.amberAccent, size: 18);
      case '结构模板': return const Icon(Icons.architecture, color: Colors.orangeAccent, size: 18);
      case '地图画卷': return const Icon(Icons.map, color: Colors.cyanAccent, size: 18);
      default: return const Icon(Icons.data_object, color: Colors.grey, size: 18);
    }
  }
}
