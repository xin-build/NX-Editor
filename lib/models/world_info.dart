import 'dart:typed_data';

/// 游戏模式
enum GameMode {
  survival(0, '生存模式', 'Survival'),
  creative(1, '创造模式', 'Creative'),
  adventure(2, '冒险模式', 'Adventure'),
  spectator(6, '旁观模式', 'Spectator'),
  unknown(-1, '未知模式', 'Unknown');

  final int id;
  final String labelZh;
  final String labelEn;
  const GameMode(this.id, this.labelZh, this.labelEn);

  static GameMode fromId(int id) {
    return GameMode.values.firstWhere((e) => e.id == id, orElse: () => GameMode.survival);
  }
}

/// 游戏难度
enum GameDifficulty {
  peaceful(0, '和平', 'Peaceful'),
  easy(1, '简单', 'Easy'),
  normal(2, '普通', 'Normal'),
  hard(3, '困难', 'Hard');

  final int id;
  final String labelZh;
  final String labelEn;
  const GameDifficulty(this.id, this.labelZh, this.labelEn);

  static GameDifficulty fromId(int id) {
    return GameDifficulty.values.firstWhere((e) => e.id == id, orElse: () => GameDifficulty.normal);
  }
}

/// 存档版本架构
enum SaveVersionType {
  ancientPE('远古 PE (0.11 - 0.13)', 'PocketChunk 单文件格式'),
  legacyBedrock('经典基岩版 (0.14 - 1.17)', '2D群系 (Tag 45) / 256高度'),
  modernBedrock('现代基岩版 (1.18+)', '3D群系 (Tag 43) / -64~320高度');

  final String title;
  final String description;
  const SaveVersionType(this.title, this.description);
}

/// 存档信息模型
class WorldInfo {
  final String folderPath;
  final String folderName;
  String displayName;
  int seed;
  GameMode gameMode;
  GameDifficulty difficulty;
  DateTime lastPlayed;
  int sizeBytes;
  Uint8List? iconBytes;
  SaveVersionType versionType;
  int storageVersion;
  int networkVersion;
  double? spawnX;
  double? spawnY;
  double? spawnZ;
  double? playerX;
  double? playerY;
  double? playerZ;
  int playerDimension;
  bool cheatsEnabled;

  WorldInfo({
    required this.folderPath,
    required this.folderName,
    required this.displayName,
    this.seed = 0,
    this.gameMode = GameMode.survival,
    this.difficulty = GameDifficulty.normal,
    required this.lastPlayed,
    this.sizeBytes = 0,
    this.iconBytes,
    this.versionType = SaveVersionType.modernBedrock,
    this.storageVersion = 8,
    this.networkVersion = 0,
    this.spawnX,
    this.spawnY,
    this.spawnZ,
    this.playerX,
    this.playerY,
    this.playerZ,
    this.playerDimension = 0,
    this.cheatsEnabled = false,
  });

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedLastPlayed {
    final now = DateTime.now();
    final diff = now.difference(lastPlayed);
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${lastPlayed.year}-${lastPlayed.month.toString().padLeft(2, '0')}-${lastPlayed.day.toString().padLeft(2, '0')}';
  }
}
