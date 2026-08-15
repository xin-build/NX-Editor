import 'package:flutter/material.dart';
import '../data/data_manager.dart';
import '../render/map_viewport_controller.dart';

/// GPS 定位与坐标跳转弹窗
class LocatorDialog extends StatefulWidget {
  final MapViewportController viewport;
  final DataManager dataManager;
  final void Function(int dim)? onDimensionChanged;

  const LocatorDialog({
    super.key,
    required this.viewport,
    required this.dataManager,
    this.onDimensionChanged,
  });

  @override
  State<LocatorDialog> createState() => _LocatorDialogState();
}

class _LocatorDialogState extends State<LocatorDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _xCtrl = TextEditingController(text: '0');
  final _zCtrl = TextEditingController(text: '0');
  final _cxCtrl = TextEditingController(text: '0');
  final _czCtrl = TextEditingController(text: '0');

  int _targetDim = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _xCtrl.text = widget.viewport.cursorWorldX.round().toString();
    _zCtrl.text = widget.viewport.cursorWorldZ.round().toString();
    _cxCtrl.text = (widget.viewport.cursorWorldX / 16).floor().toString();
    _czCtrl.text = (widget.viewport.cursorWorldZ / 16).floor().toString();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _xCtrl.dispose();
    _zCtrl.dispose();
    _cxCtrl.dispose();
    _czCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.gps_fixed, color: Colors.blueAccent),
          SizedBox(width: 8),
          Text('GPS 定位导航'),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 快速定位按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.person, size: 18),
                    label: const Text('玩家位置'),
                    onPressed: () {
                      widget.viewport.centerOnBlock(widget.dataManager.playerX, widget.dataManager.playerZ);
                      widget.onDimensionChanged?.call(widget.dataManager.playerDimension);
                      Navigator.pop(context);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.flag, size: 18),
                    label: const Text('出生点'),
                    onPressed: () {
                      final sx = widget.dataManager.currentWorldInfo?.spawnX ?? 0;
                      final sz = widget.dataManager.currentWorldInfo?.spawnZ ?? 0;
                      widget.viewport.centerOnBlock(sx, sz);
                      widget.onDimensionChanged?.call(0);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: '按方块坐标 (X, Z)'),
                Tab(text: '按区块坐标 (CX, CZ)'),
              ],
            ),
            const SizedBox(height: 12),

            SizedBox(
              height: 110,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 方块坐标输入
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _xCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '方块 X', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _zCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '方块 Z', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),

                  // 区块坐标输入
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cxCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '区块 CX', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _czCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '区块 CZ', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 维度切换
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('主世界')),
                ButtonSegment(value: 1, label: Text('下界')),
                ButtonSegment(value: 2, label: Text('末地')),
              ],
              selected: {_targetDim},
              onSelectionChanged: (set) => setState(() => _targetDim = set.first),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton.icon(
          icon: const Icon(Icons.arrow_forward),
          label: const Text('跳转'),
          onPressed: () {
            if (_tabController.index == 0) {
              final x = double.tryParse(_xCtrl.text) ?? 0;
              final z = double.tryParse(_zCtrl.text) ?? 0;
              widget.viewport.centerOnBlock(x, z);
            } else {
              final cx = int.tryParse(_cxCtrl.text) ?? 0;
              final cz = int.tryParse(_czCtrl.text) ?? 0;
              widget.viewport.centerOnBlock(cx * 16.0 + 8.0, cz * 16.0 + 8.0);
            }
            widget.onDimensionChanged?.call(_targetDim);
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}
