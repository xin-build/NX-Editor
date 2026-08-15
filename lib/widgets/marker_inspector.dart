import 'package:flutter/material.dart';
import '../data/data_manager.dart';
import '../models/marker_data.dart';

/// 标记详情与操作弹窗
class MarkerInspectorDialog extends StatelessWidget {
  final MapMarker marker;
  final DataManager dataManager;
  final void Function(String nbtKey)? onOpenNbt;

  const MarkerInspectorDialog({
    super.key,
    required this.marker,
    required this.dataManager,
    this.onOpenNbt,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(marker.type.icon, color: marker.color),
          const SizedBox(width: 8),
          Expanded(child: Text(marker.title, overflow: TextOverflow.ellipsis)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (marker.subtitle != null) ...[
            Text(marker.subtitle!, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
          ],
          _buildInfoRow('类型', marker.type.label),
          _buildInfoRow('标识符', marker.identifier ?? '未知'),
          _buildInfoRow('X 坐标', marker.x.toStringAsFixed(1)),
          _buildInfoRow('Y 坐标', marker.y.toStringAsFixed(1)),
          _buildInfoRow('Z 坐标', marker.z.toStringAsFixed(1)),
          _buildInfoRow('维度', marker.dimension == 0 ? '主世界' : (marker.dimension == 1 ? '下界' : '末地')),
          if (marker.nbtKey != null) ...[
            const SizedBox(height: 8),
            Text('NBT Key: ${marker.nbtKey}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ],
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.flight_takeoff),
          label: const Text('传送玩家到此处'),
          onPressed: () {
            dataManager.teleportPlayer(marker.x, marker.y, marker.z, marker.dimension);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已传送至 ${marker.title}')),
            );
          },
        ),
        if (marker.nbtKey != null)
          FilledButton.icon(
            icon: const Icon(Icons.account_tree),
            label: const Text('编辑 NBT'),
            onPressed: () {
              Navigator.pop(context);
              onOpenNbt?.call(marker.nbtKey!);
            },
          ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
        ],
      ),
    );
  }
}
