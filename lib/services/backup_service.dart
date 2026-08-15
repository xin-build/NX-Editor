import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class _ExtractRequest {
  final String zipPath;
  final String targetDir;
  _ExtractRequest(this.zipPath, this.targetDir);
}

/// 备份项信息
class BackupItem {
  final String path;
  final String name;
  final DateTime createdAt;
  final int sizeBytes;

  const BackupItem({
    required this.path,
    required this.name,
    required this.createdAt,
    required this.sizeBytes,
  });

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedTime {
    return '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
  }
}

/// 存档备份与导入导出服务
class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  /// 获取指定存档的所有备份列表
  List<BackupItem> getBackupsForWorld(String worldFolderPath) {
    final parentDir = Directory(p.dirname(worldFolderPath));
    final folderName = p.basename(worldFolderPath);
    final prefix = '${folderName}_backup_';
    final backups = <BackupItem>[];

    if (!parentDir.existsSync()) return backups;

    for (final entity in parentDir.listSync()) {
      final name = p.basename(entity.path);
      if (name.startsWith(prefix)) {
        int size = 0;
        if (entity is Directory) {
          for (final f in entity.listSync(recursive: true)) {
            if (f is File) size += f.lengthSync();
          }
        } else if (entity is File) {
          size = entity.lengthSync();
        }

        DateTime time = entity.statSync().modified;
        final timestampStr = name.replaceFirst(prefix, '').replaceAll('.mcworld', '').replaceAll('.zip', '');
        final parsedTime = int.tryParse(timestampStr);
        if (parsedTime != null) {
          time = DateTime.fromMillisecondsSinceEpoch(parsedTime);
        }

        backups.add(BackupItem(
          path: entity.path,
          name: name,
          createdAt: time,
          sizeBytes: size,
        ));
      }
    }

    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return backups;
  }

  /// 创建快照备份 (复制文件夹)
  Future<String> createSnapshotBackup(String worldFolderPath) async {
    final parentDir = p.dirname(worldFolderPath);
    final folderName = p.basename(worldFolderPath);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final backupPath = p.join(parentDir, '${folderName}_backup_$timestamp');

    await _copyDirectory(Directory(worldFolderPath), Directory(backupPath));
    return backupPath;
  }

  /// 导出为 .mcworld 压缩文件
  Future<File> exportToMcWorld(String worldFolderPath, String exportFilePath) async {
    final encoder = ZipFileEncoder();
    encoder.create(exportFilePath);
    final sourceDir = Directory(worldFolderPath);
    for (final entity in sourceDir.listSync(recursive: true)) {
      if (entity is File) {
        final relPath = p.relative(entity.path, from: worldFolderPath);
        encoder.addFile(entity, relPath);
      }
    }
    encoder.close();
    return File(exportFilePath);
  }

  /// 从 .mcworld 导入解压到目标目录 (支持后台 Isolate 流式解压与子目录自适应展开)
  Future<String> importFromMcWorld(String mcWorldFilePath, String targetParentDir) async {
    final folderName = p.basenameWithoutExtension(mcWorldFilePath);
    var targetFolderPath = p.join(targetParentDir, folderName);
    var counter = 1;
    while (Directory(targetFolderPath).existsSync()) {
      targetFolderPath = p.join(targetParentDir, '${folderName}_$counter');
      counter++;
    }

    final targetDir = Directory(targetFolderPath);
    targetDir.createSync(recursive: true);

    // 1. 在后台 Isolate 中进行流式解压，绝不阻塞 UI 线程
    await compute(_isolateExtractZip, _ExtractRequest(mcWorldFilePath, targetFolderPath));

    // 2. 智能规范化世界目录层级：检测 level.dat 是否位于子文件夹中
    final normalizedPath = _normalizeWorldDirectory(targetFolderPath);
    return normalizedPath;
  }

  static void _isolateExtractZip(_ExtractRequest req) {
    try {
      extractFileToDisk(req.zipPath, req.targetDir);
    } catch (_) {
      // 备用纯 Dart 解码
      final bytes = File(req.zipPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File(p.join(req.targetDir, filename));
          outFile.createSync(recursive: true);
          outFile.writeAsBytesSync(data);
        } else {
          Directory(p.join(req.targetDir, filename)).createSync(recursive: true);
        }
      }
    }
  }

  /// 如果解压后 level.dat 在子文件夹内，将其文件提升到根目录以规范化
  String _normalizeWorldDirectory(String worldDirPath) {
    final rootLevelDat = File(p.join(worldDirPath, 'level.dat'));
    if (rootLevelDat.existsSync()) {
      return worldDirPath;
    }

    // 递归寻找 level.dat
    final rootDir = Directory(worldDirPath);
    for (final entity in rootDir.listSync(recursive: true)) {
      if (entity is File && p.basename(entity.path).toLowerCase() == 'level.dat') {
        final actualWorldDir = entity.parent;
        // 如果就在根目录的下一层子文件夹，将子文件夹内的所有内容移到根目录
        if (actualWorldDir.path != worldDirPath) {
          try {
            for (final subEntity in actualWorldDir.listSync(recursive: false)) {
              final destPath = p.join(worldDirPath, p.basename(subEntity.path));
              if (subEntity is File) {
                subEntity.renameSync(destPath);
              } else if (subEntity is Directory) {
                if (Directory(destPath).existsSync()) {
                  Directory(destPath).deleteSync(recursive: true);
                }
                subEntity.renameSync(destPath);
              }
            }
            // 清理空的子文件夹
            try {
              actualWorldDir.deleteSync(recursive: true);
            } catch (_) {}
            return worldDirPath;
          } catch (_) {
            return actualWorldDir.path;
          }
        }
      }
    }
    return worldDirPath;
  }

  /// 还原备份
  Future<void> restoreBackup(String backupPath, String targetWorldFolderPath) async {
    final targetDir = Directory(targetWorldFolderPath);
    if (targetDir.existsSync()) {
      targetDir.deleteSync(recursive: true);
    }
    targetDir.createSync(recursive: true);

    final backupEntity = FileSystemEntity.typeSync(backupPath);
    if (backupEntity == FileSystemEntityType.directory) {
      await _copyDirectory(Directory(backupPath), targetDir);
    } else if (backupEntity == FileSystemEntityType.file) {
      final bytes = await File(backupPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        if (file.isFile) {
          final outFile = File(p.join(targetWorldFolderPath, file.name));
          outFile.createSync(recursive: true);
          outFile.writeAsBytesSync(file.content as List<int>);
        }
      }
    }
  }

  /// 删除备份
  Future<void> deleteBackup(String backupPath) async {
    final type = FileSystemEntity.typeSync(backupPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(backupPath).delete(recursive: true);
    } else if (type == FileSystemEntityType.file) {
      await File(backupPath).delete();
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    if (!destination.existsSync()) {
      destination.createSync(recursive: true);
    }
    for (final entity in source.listSync(recursive: false)) {
      if (entity is Directory) {
        final newDir = Directory(p.join(destination.path, p.basename(entity.path)));
        await _copyDirectory(entity, newDir);
      } else if (entity is File) {
        final newFile = File(p.join(destination.path, p.basename(entity.path)));
        await entity.copy(newFile.path);
      }
    }
  }
}
