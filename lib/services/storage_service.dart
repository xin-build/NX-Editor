import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/app_settings.dart';
import '../models/world_info.dart';
import '../nbt/nbt_parser.dart';
import '../nbt/nbt_tags.dart';

/// 存档与存储管理服务
class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  /// 扫描所有可用存档目录
  Future<List<String>> getSearchDirectories() async {
    final dirs = <String>[];

    // 1. Windows Bedrock 默认目录
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null) {
        final winPath = p.join(
          localAppData,
          'Packages',
          'Microsoft.MinecraftUWP_8wekyb3d8bbwe',
          'LocalState',
          'games',
          'com.mojang',
          'minecraftWorlds',
        );
        if (Directory(winPath).existsSync()) {
          dirs.add(winPath);
        }
      }
    }

    // 2. Android 默认目录
    if (Platform.isAndroid) {
      const androidModern = '/storage/emulated/0/Android/data/com.mojang.minecraftpe/files/games/com.mojang/minecraftWorlds';
      const androidLegacy = '/storage/emulated/0/games/com.mojang/minecraftWorlds';
      if (Directory(androidModern).existsSync()) dirs.add(androidModern);
      if (Directory(androidLegacy).existsSync()) dirs.add(androidLegacy);
    }

    // 3. 当前工作目录与父级项目目录
    try {
      final currentDir = Directory.current;
      if (currentDir.existsSync() && !dirs.contains(currentDir.path)) {
        dirs.add(currentDir.path);
      }
      final parentDir = currentDir.parent;
      if (parentDir.existsSync() && !dirs.contains(parentDir.path)) {
        dirs.add(parentDir.path);
      }
    } catch (_) {}

    // 4. 用户自定义目录
    final customPaths = AppSettings().customWorldPaths;
    for (final cp in customPaths) {
      if (Directory(cp).existsSync() && !dirs.contains(cp)) {
        dirs.add(cp);
      }
    }

    return dirs;
  }

  /// 扫描指定目录下的所有 Minecraft 存档
  Future<List<WorldInfo>> scanWorldsInDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];

    final worlds = <WorldInfo>[];

    // 检查目录本身是否为一个存档
    if (File(p.join(dirPath, 'level.dat')).existsSync()) {
      final selfWorld = await parseWorldInfo(dirPath);
      if (selfWorld != null) {
        worlds.add(selfWorld);
      }
    }

    try {
      final entities = dir.listSync();
      for (final entity in entities) {
        if (entity is Directory) {
          final world = await parseWorldInfo(entity.path);
          if (world != null) {
            worlds.add(world);
          }
        }
      }
    } catch (_) {}

    // 按最后游玩时间倒序排列
    worlds.sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));
    return worlds;
  }

  /// 扫描所有目录下的所有存档
  Future<List<WorldInfo>> scanAllWorlds() async {
    final searchDirs = await getSearchDirectories();
    final allWorlds = <WorldInfo>[];
    final seenPaths = <String>{};

    for (final dirPath in searchDirs) {
      final worlds = await scanWorldsInDirectory(dirPath);
      for (final w in worlds) {
        if (!seenPaths.contains(w.folderPath)) {
          seenPaths.add(w.folderPath);
          allWorlds.add(w);
        }
      }
    }

    allWorlds.sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));
    return allWorlds;
  }

  /// 解析单个存档元数据
  Future<WorldInfo?> parseWorldInfo(String worldFolderPath) async {
    final levelDatFile = File(p.join(worldFolderPath, 'level.dat'));
    if (!levelDatFile.existsSync()) return null;

    final folderName = p.basename(worldFolderPath);
    String displayName = folderName;
    int seed = 0;
    GameMode gameMode = GameMode.survival;
    GameDifficulty difficulty = GameDifficulty.normal;
    DateTime lastPlayed = levelDatFile.lastModifiedSync();
    SaveVersionType versionType = SaveVersionType.modernBedrock;
    int storageVersion = 8;
    int networkVersion = 0;
    double? spawnX, spawnY, spawnZ;
    double? playerX, playerY, playerZ;
    int playerDim = 0;
    bool cheats = false;

    // 读取 levelname.txt
    final levelNameFile = File(p.join(worldFolderPath, 'levelname.txt'));
    if (levelNameFile.existsSync()) {
      try {
        final content = await levelNameFile.readAsString();
        if (content.trim().isNotEmpty) {
          displayName = content.trim();
        }
      } catch (_) {}
    }

    // 读取 world_icon.jpeg
    Uint8List? iconBytes;
    final iconFile = File(p.join(worldFolderPath, 'world_icon.jpeg'));
    if (iconFile.existsSync()) {
      try {
        iconBytes = await iconFile.readAsBytes();
      } catch (_) {}
    }

    // 解析 level.dat
    try {
      final bytes = await levelDatFile.readAsBytes();
      final parser = LittleEndianNbtParser();
      final root = parser.parseLevelDat(bytes);

      if (root.value.containsKey('LevelName')) {
        final nameTag = root.value['LevelName'];
        if (nameTag is NbtString && nameTag.value.isNotEmpty) {
          displayName = nameTag.value;
        }
      }
      if (root.value.containsKey('RandomSeed')) {
        final seedTag = root.value['RandomSeed'];
        if (seedTag is NbtLong) {
          seed = seedTag.value;
        } else if (seedTag is NbtInt) {
          seed = seedTag.value;
        }
      }
      if (root.value.containsKey('GameType')) {
        final gmTag = root.value['GameType'];
        if (gmTag is NbtInt) {
          gameMode = GameMode.fromId(gmTag.value);
        } else if (gmTag is NbtByte) {
          gameMode = GameMode.fromId(gmTag.value);
        }
      }
      if (root.value.containsKey('Difficulty')) {
        final diffTag = root.value['Difficulty'];
        if (diffTag is NbtInt) {
          difficulty = GameDifficulty.fromId(diffTag.value);
        } else if (diffTag is NbtByte) {
          difficulty = GameDifficulty.fromId(diffTag.value);
        }
      }
      if (root.value.containsKey('LastPlayed')) {
        final lpTag = root.value['LastPlayed'];
        if (lpTag is NbtLong) {
          lastPlayed = DateTime.fromMillisecondsSinceEpoch(lpTag.value * 1000);
        }
      }
      if (root.value.containsKey('StorageVersion')) {
        final svTag = root.value['StorageVersion'];
        if (svTag is NbtInt) storageVersion = svTag.value;
      }
      if (root.value.containsKey('NetworkVersion')) {
        final nvTag = root.value['NetworkVersion'];
        if (nvTag is NbtInt) networkVersion = nvTag.value;
      }
      if (root.value.containsKey('cheatsEnabled')) {
        final cTag = root.value['cheatsEnabled'];
        if (cTag is NbtByte) cheats = cTag.value == 1;
      }
      if (root.value.containsKey('SpawnX')) {
        final sx = root.value['SpawnX'];
        final sy = root.value['SpawnY'];
        final sz = root.value['SpawnZ'];
        if (sx is NbtInt) spawnX = sx.value.toDouble();
        if (sy is NbtInt) spawnY = sy.value.toDouble();
        if (sz is NbtInt) spawnZ = sz.value.toDouble();
      }

      // 尝试解析玩家位置
      if (root.value.containsKey('Player')) {
        final playerTag = root.value['Player'];
        if (playerTag is NbtCompound && playerTag.value.containsKey('Pos')) {
          final posTag = playerTag.value['Pos'];
          if (posTag is NbtList && posTag.value.length >= 3) {
            final px = posTag.value[0];
            final py = posTag.value[1];
            final pz = posTag.value[2];
            if (px is NbtFloat) playerX = px.value.toDouble();
            if (py is NbtFloat) playerY = py.value.toDouble();
            if (pz is NbtFloat) playerZ = pz.value.toDouble();
          }
          if (playerTag.value.containsKey('DimensionId')) {
            final dimTag = playerTag.value['DimensionId'];
            if (dimTag is NbtInt) playerDim = dimTag.value;
          }
        }
      }

      // 判断版本类型
      if (storageVersion < 4) {
        versionType = SaveVersionType.ancientPE;
      } else if (storageVersion < 9) {
        versionType = SaveVersionType.legacyBedrock;
      } else {
        versionType = SaveVersionType.modernBedrock;
      }
    } catch (_) {}

    // 计算文件夹大小
    int totalSize = 0;
    try {
      final dir = Directory(worldFolderPath);
      for (final file in dir.listSync(recursive: true)) {
        if (file is File) {
          totalSize += file.lengthSync();
        }
      }
    } catch (_) {}

    return WorldInfo(
      folderPath: worldFolderPath,
      folderName: folderName,
      displayName: displayName,
      seed: seed,
      gameMode: gameMode,
      difficulty: difficulty,
      lastPlayed: lastPlayed,
      sizeBytes: totalSize,
      iconBytes: iconBytes,
      versionType: versionType,
      storageVersion: storageVersion,
      networkVersion: networkVersion,
      spawnX: spawnX,
      spawnY: spawnY,
      spawnZ: spawnZ,
      playerX: playerX,
      playerY: playerY,
      playerZ: playerZ,
      playerDimension: playerDim,
      cheatsEnabled: cheats,
    );
  }

  /// 加载与保存设置
  Future<void> loadSettings() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final settingsFile = File(p.join(appDir.path, 'mc_editor_settings.json'));
      if (settingsFile.existsSync()) {
        final str = await settingsFile.readAsString();
        final json = jsonDecode(str) as Map<String, dynamic>;
        AppSettings().loadFromJson(json);
      }
    } catch (_) {}
  }

  Future<void> saveSettings() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final settingsFile = File(p.join(appDir.path, 'mc_editor_settings.json'));
      final str = jsonEncode(AppSettings().toJson());
      await settingsFile.writeAsString(str);
    } catch (_) {}
  }
}
