import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../leveldb/leveldb_writer.dart';
import '../nbt/nbt_parser.dart';
import '../nbt/nbt_tags.dart';

/// 超平坦层定义
class FlatLayerConfig {
  String blockName; // minecraft:bedrock, minecraft:dirt, etc.
  int count; // 厚度

  FlatLayerConfig({
    required this.blockName,
    this.count = 1,
  });

  Map<String, dynamic> toJson() => {
    'block_name': blockName.startsWith('minecraft:') ? blockName : 'minecraft:$blockName',
    'count': count,
  };
}

/// 超平坦世界生成器服务
class FlatWorldGenerator {
  static final FlatWorldGenerator _instance = FlatWorldGenerator._internal();
  factory FlatWorldGenerator() => _instance;
  FlatWorldGenerator._internal();

  /// 预设配置
  static List<FlatLayerConfig> get classicPreset => [
    FlatLayerConfig(blockName: 'minecraft:bedrock', count: 1),
    FlatLayerConfig(blockName: 'minecraft:dirt', count: 2),
    FlatLayerConfig(blockName: 'minecraft:grass_block', count: 1),
  ];

  static List<FlatLayerConfig> get tunnelingPreset => [
    FlatLayerConfig(blockName: 'minecraft:bedrock', count: 1),
    FlatLayerConfig(blockName: 'minecraft:stone', count: 230),
    FlatLayerConfig(blockName: 'minecraft:dirt', count: 5),
    FlatLayerConfig(blockName: 'minecraft:grass_block', count: 1),
  ];

  static List<FlatLayerConfig> get waterWorldPreset => [
    FlatLayerConfig(blockName: 'minecraft:bedrock', count: 1),
    FlatLayerConfig(blockName: 'minecraft:dirt', count: 5),
    FlatLayerConfig(blockName: 'minecraft:sand', count: 5),
    FlatLayerConfig(blockName: 'minecraft:water', count: 90),
  ];

  static List<FlatLayerConfig> get overworldCavesPreset => [
    FlatLayerConfig(blockName: 'minecraft:bedrock', count: 1),
    FlatLayerConfig(blockName: 'minecraft:deepslate', count: 64),
    FlatLayerConfig(blockName: 'minecraft:stone', count: 128),
    FlatLayerConfig(blockName: 'minecraft:dirt', count: 3),
    FlatLayerConfig(blockName: 'minecraft:grass_block', count: 1),
  ];

  /// 创建超平坦世界
  Future<String> createSuperflatWorld({
    required String targetParentDir,
    required String worldName,
    required int biomeId,
    required List<FlatLayerConfig> layers,
    int gameMode = 1, // 0: 生存, 1: 创造
    int difficulty = 1, // 0: 和平, 1: 简单, 2: 普通
    bool cavesAndCliffs = true, // 1.18+
  }) async {
    final cleanFolderName = worldName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    var worldPath = p.join(targetParentDir, cleanFolderName);
    int counter = 1;
    while (Directory(worldPath).existsSync()) {
      worldPath = p.join(targetParentDir, '${cleanFolderName}_$counter');
      counter++;
    }

    final worldDir = Directory(worldPath);
    worldDir.createSync(recursive: true);

    // 1. 写入 levelname.txt
    final levelNameFile = File(p.join(worldPath, 'levelname.txt'));
    await levelNameFile.writeAsString(worldName);

    // 2. 构造 flatworldlayers JSON
    final flatLayersJson = {
      'biome_id': biomeId,
      'block_layers': layers.map((l) => l.toJson()).toList(),
      'encoding_version': 6,
      'structure_options': null,
    };
    final flatLayersStr = jsonEncode(flatLayersJson);

    // 3. 构造 level.dat NBT
    final seed = DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    int totalHeight = 0;
    for (final l in layers) {
      totalHeight += l.count;
    }
    final spawnY = cavesAndCliffs ? (-64 + totalHeight + 1) : (totalHeight + 1);

    final levelRoot = NbtCompound({
      'LevelName': NbtString(worldName),
      'RandomSeed': NbtLong(seed),
      'GameType': NbtInt(gameMode),
      'Difficulty': NbtInt(difficulty),
      'Generator': NbtInt(2), // 2 = Flat
      'FlatWorldLayers': NbtString(flatLayersStr),
      'LastPlayed': NbtLong(nowSeconds),
      'StorageVersion': NbtInt(cavesAndCliffs ? 10 : 8),
      'NetworkVersion': NbtInt(0),
      'SpawnX': NbtInt(0),
      'SpawnY': NbtInt(spawnY),
      'SpawnZ': NbtInt(0),
      'Time': NbtLong(1000),
      'DayCycleStopTime': NbtLong(-1),
      'rainTime': NbtInt(0),
      'rainLevel': NbtFloat(0.0),
      'lightningTime': NbtInt(0),
      'lightningLevel': NbtFloat(0.0),
      'commandsEnabled': NbtByte(1),
      'cheatsEnabled': NbtByte(1),
      'hasBeenLoadedInCreative': NbtByte(gameMode == 1 ? 1 : 0),
      'Platform': NbtInt(2),
      'centerMapsToOrigins': NbtByte(1),
      'worldStartCount': NbtLong(1),
    });

    final nbtWriter = LittleEndianNbtWriter();
    final levelDatBytes = nbtWriter.writeLevelDat(levelRoot);
    final levelDatFile = File(p.join(worldPath, 'level.dat'));
    await levelDatFile.writeAsBytes(levelDatBytes, flush: true);

    final levelDatOld = File(p.join(worldPath, 'level.dat_old'));
    await levelDatOld.writeAsBytes(levelDatBytes, flush: true);

    // 4. 创建 db 文件夹及空 SSTable
    final dbDir = Directory(p.join(worldPath, 'db'));
    dbDir.createSync(recursive: true);

    // 写入初始 ldb 文件
    final ldbFile = p.join(dbDir.path, '000004.ldb');
    await BELevelDBWriter.saveToLdbFile(ldbFile, {});

    // 写入 CURRENT 与 MANIFEST
    final currentFile = File(p.join(dbDir.path, 'CURRENT'));
    await currentFile.writeAsString('MANIFEST-000002\n');

    final manifestFile = File(p.join(dbDir.path, 'MANIFEST-000002'));
    await manifestFile.writeAsBytes([0x00, 0x00, 0x00, 0x00]);

    return worldPath;
  }
}
