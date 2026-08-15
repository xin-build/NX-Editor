import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../data/data_manager.dart';
import '../models/chunk_key.dart';
import '../nbt/nbt_parser.dart';
import '../nbt/nbt_tags.dart';

/// 实体分类
enum EntityCategory {
  passive('被动友好生物', Icons.pets, Colors.green),
  hostile('敌对怪物', Icons.warning_amber, Colors.red),
  neutral('中立生物', Icons.remove_circle_outline, Colors.orange),
  boss('Boss 强力生物', Icons.star, Colors.purple),
  player('玩家角色', Icons.person, Colors.blue),
  vehicle('载具与矿车', Icons.directions_boat, Colors.brown),
  item('掉落物与抛射物', Icons.category, Colors.grey),
  tileEntity('方块实体', Icons.inventory_2, Colors.amber);

  final String label;
  final IconData icon;
  final Color color;
  const EntityCategory(this.label, this.icon, this.color);
}

/// 解析后的世界实体模型
class WorldEntity {
  final String key; // 对应的 LevelDB 键 (Base64 或 Key 标识)
  final String uniqueId;
  final String identifier; // 如 minecraft:zombie, minecraft:cow
  final String name; // 显示名称 (如果有自定义名则优先展示)
  final double x;
  final double y;
  final double z;
  final double rotationYaw;
  final double rotationPitch;
  final int dimension; // 0: 主世界, 1: 下界, 2: 末地
  final double health;
  final double maxHealth;
  final EntityCategory category;
  final NbtCompound nbt;
  final bool isActorPrefix; // 是否为 1.18+ actorprefix 键

  const WorldEntity({
    required this.key,
    required this.uniqueId,
    required this.identifier,
    required this.name,
    required this.x,
    required this.y,
    required this.z,
    this.rotationYaw = 0.0,
    this.rotationPitch = 0.0,
    required this.dimension,
    this.health = 20.0,
    this.maxHealth = 20.0,
    required this.category,
    required this.nbt,
    this.isActorPrefix = true,
  });

  /// 获取实体对应的图标资源路径
  String get iconAssetPath {
    final clean = identifier.replaceAll('minecraft:', '').toLowerCase();
    return 'assrts/images/entity/$clean.png';
  }
}

/// 解析后的世界方块实体模型 (宝箱、刷怪笼、告示牌、指令方块等)
class WorldBlockEntity {
  final String chunkKey;
  final String blockId; // 如 Chest, MobSpawner, CommandBlock, Sign
  final String title;
  final int x;
  final int y;
  final int z;
  final int dimension;
  final NbtCompound nbt;

  const WorldBlockEntity({
    required this.chunkKey,
    required this.blockId,
    required this.title,
    required this.x,
    required this.y,
    required this.z,
    required this.dimension,
    required this.nbt,
  });

  String get iconAssetPath {
    final lower = blockId.toLowerCase();
    if (lower.contains('chest')) return 'assrts/images/block/chest.png';
    if (lower.contains('spawner')) return 'assrts/images/block/mob_spawner.png';
    if (lower.contains('command')) return 'assrts/images/block/command_block.png';
    if (lower.contains('barrel')) return 'assrts/images/block/barrel.png';
    if (lower.contains('shulker')) return 'assrts/images/block/black_shulker_box.png';
    if (lower.contains('furnace')) return 'assrts/images/block/furnace.png';
    if (lower.contains('hopper')) return 'assrts/images/block/hopper.png';
    if (lower.contains('enchant')) return 'assrts/images/block/enchanting_table.png';
    return 'assrts/images/block/chest.png';
  }
}

/// 实体与方块实体全量服务 (精准解析各维度 1.18+ actorprefix、digp 索引与 Tag 50)
class EntityService {
  static final EntityService _instance = EntityService._internal();
  factory EntityService() => _instance;
  EntityService._internal();

  /// 从当前已加载的 LevelDB 数据库解析所有生物与实体
  List<WorldEntity> parseAllEntities(DataManager dm) {
    final entities = <WorldEntity>[];
    final parser = LittleEndianNbtParser();

    // 1. 扫描所有 digp (DigP actor references) 建立 actor UID -> dimension 映射
    final actorDimMap = <String, int>{};
    for (final e in dm.rawKeyMap.entries) {
      final rawKey = e.value;
      if (rawKey.length >= 12 && rawKey[0] == 0x64 && rawKey[1] == 0x69 && rawKey[2] == 0x67 && rawKey[3] == 0x70) {
        int dim = 0;
        if (rawKey.length >= 16) {
          final bd = ByteData.sublistView(rawKey);
          dim = bd.getInt32(12, Endian.little);
        }
        final val = dm.rawEntries[e.key];
        if (val != null && val.isNotEmpty && val.length % 8 == 0) {
          final valBd = ByteData.sublistView(val);
          for (int i = 0; i < val.length ~/ 8; i++) {
            final uid = valBd.getInt64(i * 8, Endian.little).toString();
            actorDimMap[uid] = dim;
          }
        }
      }
    }

    // 2. 解析 1.18+ actorprefix 实体
    for (final e in dm.rawKeyMap.entries) {
      final b64Key = e.key;
      final rawKey = e.value;

      if (rawKey.length >= 19 && _hasActorPrefix(rawKey)) {
        final valBytes = dm.rawEntries[b64Key];
        if (valBytes == null || valBytes.isEmpty) continue;

        try {
          final parsed = parser.parse(valBytes);
          final root = parsed.value;

          // 从 actorprefix key 中提取 8 字节 actor UID
          int defaultDim = 0;
          if (rawKey.length >= 19) {
            final uidBd = ByteData.sublistView(rawKey, 11, 19);
            final uidStr = uidBd.getInt64(0, Endian.little).toString();
            if (actorDimMap.containsKey(uidStr)) {
              defaultDim = actorDimMap[uidStr]!;
            }
          }

          final entity = _buildWorldEntity(b64Key, root, isActorPrefix: true, defaultDim: defaultDim);
          if (entity != null) {
            entities.add(entity);
          }
        } catch (_) {}
      }
    }

    // 3. 解析旧版/分块实体 Tag 50
    for (final e in dm.rawKeyMap.entries) {
      final b64Key = e.key;
      final rawKey = e.value;
      final parsedChunk = ParsedChunkKey.parse(rawKey);

      if (parsedChunk != null && parsedChunk.tag == ChunkTag.entity) {
        final valBytes = dm.rawEntries[b64Key];
        if (valBytes == null || valBytes.isEmpty) continue;

        try {
          int offset = 0;
          while (offset < valBytes.length) {
            final tag = parser.parseFromBuffer(valBytes.sublist(offset));
            if (tag is NbtCompound) {
              final entity = _buildWorldEntity(b64Key, tag, isActorPrefix: false, defaultDim: parsedChunk.dimension);
              if (entity != null) {
                entities.add(entity);
              }
            }
            offset += parser.bytesRead;
            if (parser.bytesRead <= 0) break;
          }
        } catch (_) {}
      }
    }

    return entities;
  }

  /// 从当前数据库解析所有方块实体 (Tag 49 或 Tag 46)
  List<WorldBlockEntity> parseAllBlockEntities(DataManager dm) {
    final blockEntities = <WorldBlockEntity>[];
    final parser = LittleEndianNbtParser();

    for (final e in dm.rawKeyMap.entries) {
      final b64Key = e.key;
      final rawKey = e.value;
      final parsedChunk = ParsedChunkKey.parse(rawKey);

      if (parsedChunk != null && (parsedChunk.tag == ChunkTag.blockEntity || parsedChunk.tag == ChunkTag.data2DLegacy)) {
        final valBytes = dm.rawEntries[b64Key];
        if (valBytes == null || valBytes.isEmpty) continue;

        try {
          int offset = 0;
          while (offset < valBytes.length) {
            final tag = parser.parseFromBuffer(valBytes.sublist(offset));
            if (tag is NbtCompound) {
              final id = tag.value['id'] is NbtString ? (tag.value['id'] as NbtString).value : 'BlockEntity';
              final x = tag.value['x'] is NbtInt ? (tag.value['x'] as NbtInt).value : (parsedChunk.chunkX * 16);
              final y = tag.value['y'] is NbtInt ? (tag.value['y'] as NbtInt).value : 64;
              final z = tag.value['z'] is NbtInt ? (tag.value['z'] as NbtInt).value : (parsedChunk.chunkZ * 16);

              blockEntities.add(WorldBlockEntity(
                chunkKey: b64Key,
                blockId: id,
                title: _formatBlockEntityTitle(id, tag),
                x: x,
                y: y,
                z: z,
                dimension: parsedChunk.dimension,
                nbt: tag,
              ));
            }
            offset += parser.bytesRead;
            if (parser.bytesRead <= 0) break;
          }
        } catch (_) {}
      }
    }

    return blockEntities;
  }

  bool _hasActorPrefix(Uint8List key) {
    const prefix = [0x61, 0x63, 0x74, 0x6f, 0x72, 0x70, 0x72, 0x65, 0x66, 0x69, 0x78]; // "actorprefix"
    if (key.length < prefix.length) return false;
    for (int i = 0; i < prefix.length; i++) {
      if (key[i] != prefix[i]) return false;
    }
    return true;
  }

  WorldEntity? _buildWorldEntity(String key, NbtCompound root, {required bool isActorPrefix, int defaultDim = 0}) {
    String identifier = 'minecraft:unknown';
    if (root.value.containsKey('identifier')) {
      identifier = (root.value['identifier'] as NbtString).value;
    } else if (root.value.containsKey('id')) {
      identifier = (root.value['id'] as NbtString).value;
    }

    if (!identifier.startsWith('minecraft:')) {
      identifier = 'minecraft:$identifier';
    }

    // 坐标
    double x = 0.0, y = 64.0, z = 0.0;
    if (root.value.containsKey('Pos') && root.value['Pos'] is NbtList) {
      final list = (root.value['Pos'] as NbtList).value;
      if (list.length >= 3) {
        x = (list[0] as NbtFloat).value.toDouble();
        y = (list[1] as NbtFloat).value.toDouble();
        z = (list[2] as NbtFloat).value.toDouble();
      }
    }

    // 旋转角
    double yaw = 0.0, pitch = 0.0;
    if (root.value.containsKey('Rotation') && root.value['Rotation'] is NbtList) {
      final list = (root.value['Rotation'] as NbtList).value;
      if (list.isNotEmpty) yaw = (list[0] as NbtFloat).value.toDouble();
      if (list.length > 1) pitch = (list[1] as NbtFloat).value.toDouble();
    }

    // 维度提取 (全面兼容 DimensionId, dimension, Dimension 的 Int/Byte/Short 类型)
    int dim = defaultDim;
    if (root.value.containsKey('DimensionId')) {
      final dTag = root.value['DimensionId'];
      if (dTag is NbtInt) dim = dTag.value;
      if (dTag is NbtByte) dim = dTag.value;
      if (dTag is NbtShort) dim = dTag.value;
    } else if (root.value.containsKey('dimension')) {
      final dTag = root.value['dimension'];
      if (dTag is NbtInt) dim = dTag.value;
      if (dTag is NbtByte) dim = dTag.value;
      if (dTag is NbtShort) dim = dTag.value;
    } else if (root.value.containsKey('Dimension')) {
      final dTag = root.value['Dimension'];
      if (dTag is NbtInt) dim = dTag.value;
      if (dTag is NbtByte) dim = dTag.value;
      if (dTag is NbtShort) dim = dTag.value;
    }

    // 生命值
    double health = 20.0;
    double maxHealth = 20.0;
    if (root.value.containsKey('Health')) {
      final h = root.value['Health'];
      if (h is NbtShort) health = h.value.toDouble();
      if (h is NbtFloat) health = h.value.toDouble();
      if (h is NbtInt) health = h.value.toDouble();
    }
    if (root.value.containsKey('Attributes') && root.value['Attributes'] is NbtList) {
      final attrs = (root.value['Attributes'] as NbtList).value;
      for (final a in attrs) {
        if (a is NbtCompound && (a.value['Name'] as NbtString?)?.value == 'minecraft:health') {
          final maxTag = a.value['Max'];
          if (maxTag is NbtFloat) maxHealth = maxTag.value.toDouble();
          if (maxTag is NbtInt) maxHealth = maxTag.value.toDouble();
          break;
        }
      }
    }

    // 自定义名称
    String name = _formatEntityName(identifier);
    if (root.value.containsKey('CustomName') && root.value['CustomName'] is NbtString) {
      final custom = (root.value['CustomName'] as NbtString).value;
      if (custom.isNotEmpty) {
        name = '$custom ($name)';
      }
    }

    // 唯一 ID
    String uniqueId = key;
    if (root.value.containsKey('UniqueID')) {
      final uid = root.value['UniqueID'];
      if (uid is NbtLong) uniqueId = uid.value.toString();
    }

    return WorldEntity(
      key: key,
      uniqueId: uniqueId,
      identifier: identifier,
      name: name,
      x: x,
      y: y,
      z: z,
      rotationYaw: yaw,
      rotationPitch: pitch,
      dimension: dim,
      health: health,
      maxHealth: maxHealth,
      category: _categorizeEntity(identifier),
      nbt: root,
      isActorPrefix: isActorPrefix,
    );
  }

  EntityCategory _categorizeEntity(String identifier) {
    final clean = identifier.replaceAll('minecraft:', '').toLowerCase();

    if (clean == 'player') return EntityCategory.player;
    if (clean == 'ender_dragon' || clean == 'wither' || clean == 'warden' || clean == 'elder_guardian') {
      return EntityCategory.boss;
    }
    if (clean.contains('zombie') || clean.contains('skeleton') || clean.contains('creeper') ||
        clean.contains('spider') || clean.contains('slime') || clean.contains('phantom') ||
        clean.contains('witch') || clean.contains('blaze') || clean.contains('ghast') ||
        clean.contains('drowned') || clean.contains('husk') || clean.contains('stray') ||
        clean.contains('pillager') || clean.contains('ravager') || clean.contains('vindicator') ||
        clean.contains('evoker') || clean.contains('vex') || clean.contains('piglin') ||
        clean.contains('hoglin') || clean.contains('breeze') || clean.contains('bogged')) {
      return EntityCategory.hostile;
    }
    if (clean.contains('enderman') || clean.contains('wolf') || clean.contains('iron_golem') ||
        clean.contains('polar_bear') || clean.contains('llama') || clean.contains('bee') ||
        clean.contains('dolphin') || clean.contains('panda') || clean.contains('zombified_piglin')) {
      return EntityCategory.neutral;
    }
    if (clean.contains('boat') || clean.contains('minecart')) {
      return EntityCategory.vehicle;
    }
    if (clean.contains('item') || clean.contains('arrow') || clean.contains('orb') ||
        clean.contains('tnt') || clean.contains('potion') || clean.contains('fireball')) {
      return EntityCategory.item;
    }
    return EntityCategory.passive;
  }

  String _formatEntityName(String id) {
    final clean = id.replaceAll('minecraft:', '');
    return clean.split('_').map((s) => s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : '').join(' ');
  }

  String _formatBlockEntityTitle(String id, NbtCompound nbt) {
    if (id == 'MobSpawner' && nbt.value.containsKey('EntityIdentifier')) {
      final ent = (nbt.value['EntityIdentifier'] as NbtString).value;
      return '刷怪笼 (${_formatEntityName(ent)})';
    }
    if (id == 'CommandBlock' && nbt.value.containsKey('Command')) {
      final cmd = (nbt.value['Command'] as NbtString).value;
      return '指令方块: $cmd';
    }
    if (id == 'Chest' || id == 'Barrel' || id == 'ShulkerBox') {
      if (nbt.value.containsKey('CustomName')) {
        return (nbt.value['CustomName'] as NbtString).value;
      }
      return id == 'Chest' ? '箱子' : (id == 'Barrel' ? '木桶' : '潜影盒');
    }
    return id;
  }

  /// 删除指定实体
  void deleteEntity(DataManager dm, WorldEntity entity) {
    if (entity.isActorPrefix) {
      dm.rawEntries.remove(entity.key);
      dm.rawKeyMap.remove(entity.key);
      dm.executeTransaction(_SimpleCallbackTransaction(
        onUndo: (d) {},
        onRedo: (d) {},
      ));
    }
  }

  /// 更新实体 NBT 数据
  void saveEntityNbt(DataManager dm, WorldEntity entity, NbtCompound newNbt) {
    final writer = LittleEndianNbtWriter();
    final bytes = writer.writeRoot('', newNbt);
    dm.rawEntries[entity.key] = bytes;
    dm.executeTransaction(_SimpleCallbackTransaction(
      onUndo: (d) {},
      onRedo: (d) {},
    ));
  }
}

class _SimpleCallbackTransaction extends ArchiveTransaction {
  final void Function(DataManager dm) onUndo;
  final void Function(DataManager dm) onRedo;
  _SimpleCallbackTransaction({required this.onUndo, required this.onRedo});

  @override
  void undo(DataManager manager) => onUndo(manager);

  @override
  void redo(DataManager manager) => onRedo(manager);
}
