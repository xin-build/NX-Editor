import 'package:flutter/material.dart';

/// 标记类型
enum MarkerType {
  player('玩家', Icons.person_pin_circle),
  networkPlayer('联机玩家', Icons.group),
  spawnPoint('出生点', Icons.flag),
  entity('生物/实体', Icons.pets),
  tileEntity('方块实体', Icons.inventory_2),
  customWaypoint('自定义标记', Icons.place);

  final String label;
  final IconData icon;
  const MarkerType(this.label, this.icon);
}

/// 地图标记模型
class MapMarker {
  final String id;
  final String title;
  final String? subtitle;
  final double x;
  final double y;
  final double z;
  final int dimension;
  final MarkerType type;
  final String? identifier; // minecraft:cow, minecraft:chest 等
  final String? nbtKey; // 对应的 LevelDB 键名
  final Color color;
  final String? iconAssetName;
  final bool isCustom;

  const MapMarker({
    required this.id,
    required this.title,
    this.subtitle,
    required this.x,
    required this.y,
    required this.z,
    required this.dimension,
    required this.type,
    this.identifier,
    this.nbtKey,
    this.color = Colors.blue,
    this.iconAssetName,
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'x': x,
    'y': y,
    'z': z,
    'dimension': dimension,
    'type': type.name,
    'identifier': identifier,
    'nbtKey': nbtKey,
    'color': color.toARGB32(),
    'iconAssetName': iconAssetName,
    'isCustom': isCustom,
  };

  factory MapMarker.fromJson(Map<String, dynamic> json) => MapMarker(
    id: json['id'] as String,
    title: json['title'] as String,
    subtitle: json['subtitle'] as String?,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    z: (json['z'] as num).toDouble(),
    dimension: json['dimension'] as int? ?? 0,
    type: MarkerType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => MarkerType.customWaypoint,
    ),
    identifier: json['identifier'] as String?,
    nbtKey: json['nbtKey'] as String?,
    color: Color(json['color'] as int? ?? Colors.blue.toARGB32()),
    iconAssetName: json['iconAssetName'] as String?,
    isCustom: json['isCustom'] as bool? ?? true,
  );
}
