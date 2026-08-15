import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../leveldb/leveldb_reader.dart';
import '../leveldb/leveldb_writer.dart';
import '../models/app_settings.dart';
import '../models/chunk_key.dart';
import '../models/world_info.dart';
import '../nbt/nbt_parser.dart';
import '../nbt/nbt_tags.dart';
import '../services/backup_service.dart';
import '../services/entity_service.dart';
import '../services/storage_service.dart';
import '../render/gpu_tile_renderer.dart';
import 'chunk_cache_manager.dart';

/// 存档事务基类 (Undo/Redo)
abstract class ArchiveTransaction {
  void undo(DataManager manager);
  void redo(DataManager manager);
}

/// NBT 节点修改事务
class NbtModifyTransaction extends ArchiveTransaction {
  final String key;
  final List<String> path;
  final NbtTag oldTag;
  final NbtTag newTag;

  NbtModifyTransaction({
    required this.key,
    required this.path,
    required this.oldTag,
    required this.newTag,
  });

  @override
  void undo(DataManager manager) {
    manager.updateNbtAtPathDirectly(key, path, oldTag.clone());
  }

  @override
  void redo(DataManager manager) {
    manager.updateNbtAtPathDirectly(key, path, newTag.clone());
  }
}

/// NBT 节点新增事务
class NbtAddTagTransaction extends ArchiveTransaction {
  final String key;
  final List<String> parentPath;
  final String tagKey;
  final NbtTag tag;

  NbtAddTagTransaction({
    required this.key,
    required this.parentPath,
    required this.tagKey,
    required this.tag,
  });

  @override
  void undo(DataManager manager) {
    manager.deleteNbtAtPathDirectly(key, [...parentPath, tagKey]);
  }

  @override
  void redo(DataManager manager) {
    manager.addNbtAtPathDirectly(key, parentPath, tagKey, tag.clone());
  }
}

/// NBT 节点删除事务
class NbtDeleteTagTransaction extends ArchiveTransaction {
  final String key;
  final List<String> path;
  final NbtTag deletedTag;
  final int? listIndex;

  NbtDeleteTagTransaction({
    required this.key,
    required this.path,
    required this.deletedTag,
    this.listIndex,
  });

  @override
  void undo(DataManager manager) {
    final parentPath = path.sublist(0, path.length - 1);
    final lastSeg = path.last;
    manager.restoreDeletedNbtAtPath(key, parentPath, lastSeg, deletedTag.clone(), listIndex);
  }

  @override
  void redo(DataManager manager) {
    manager.deleteNbtAtPathDirectly(key, path);
  }
}

/// NBT 根节点替换事务 (导入 NBT 等)
class NbtReplaceRootTransaction extends ArchiveTransaction {
  final String key;
  final NbtCompound oldRoot;
  final NbtCompound newRoot;

  NbtReplaceRootTransaction({
    required this.key,
    required this.oldRoot,
    required this.newRoot,
  });

  @override
  void undo(DataManager manager) {
    manager.replaceNbtRootDirectly(key, oldRoot.clone());
  }

  @override
  void redo(DataManager manager) {
    manager.replaceNbtRootDirectly(key, newRoot.clone());
  }
}

/// 玩家传送事务
class PlayerTeleportTransaction extends ArchiveTransaction {
  final double oldX, oldY, oldZ;
  final int oldDim;
  final double newX, newY, newZ;
  final int newDim;

  PlayerTeleportTransaction({
    required this.oldX, required this.oldY, required this.oldZ, required this.oldDim,
    required this.newX, required this.newY, required this.newZ, required this.newDim,
  });

  @override
  void undo(DataManager manager) {
    manager.setPlayerPositionInternal(oldX, oldY, oldZ, oldDim);
  }

  @override
  void redo(DataManager manager) {
    manager.setPlayerPositionInternal(newX, newY, newZ, newDim);
  }
}

/// 后台 Isolate 读取请求与响应
class _IsolateLoadRequest {
  final String dbPath;
  _IsolateLoadRequest(this.dbPath);
}

class _IsolateLoadResponse {
  final Map<String, Uint8List> rawEntries;
  final Map<String, Uint8List> rawKeyMap;
  final Set<String> existingChunks;
  final String? error;
  _IsolateLoadResponse({required this.rawEntries, required this.rawKeyMap, required this.existingChunks, this.error});
}

/// 存档核心数据管理器
class DataManager extends ChangeNotifier {
  String? _currentWorldPath;
  WorldInfo? _currentWorldInfo;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;
  bool _hasUnsavedChanges = false;

  // LevelDB 键值缓存 (Base64 Key -> Value, Base64 Key -> Raw Key Bytes)
  final Map<String, Uint8List> rawEntries = {};
  final Map<String, Uint8List> rawKeyMap = {};

  // 已生成的区块索引 ("dim:cx,cz")
  final Set<String> _existingChunks = {};

  // NBT 缓存 (Base64 Key / Logical Key -> NbtCompound)
  final Map<String, NbtCompound> _nbtCache = {};
  final Map<String, String> _nbtRootNames = {};

  // 撤销/重做栈
  final List<ArchiveTransaction> _undoStack = [];
  final List<ArchiveTransaction> _redoStack = [];

  // 玩家状态
  double _playerX = 0;
  double _playerY = 64;
  double _playerZ = 0;
  int _playerDimension = 0;

  // 最后修改的高亮跟踪
  String? _lastModifiedKey;
  String _lastModifiedType = ''; // 'edit' | 'undo' | 'redo' | 'paste'

  // Getters
  String? get currentWorldPath => _currentWorldPath;
  WorldInfo? get currentWorldInfo => _currentWorldInfo;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;
  bool get hasUnsavedChanges => _hasUnsavedChanges;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  double get playerX => _playerX;
  double get playerY => _playerY;
  double get playerZ => _playerZ;
  int get playerDimension => _playerDimension;

  String? get lastModifiedKey => _lastModifiedKey;
  String get lastModifiedType => _lastModifiedType;

  Set<String> get existingChunks => _existingChunks;

  /// 通知数据更新并标记未保存修改
  void notifyDataChanged() {
    _hasUnsavedChanges = true;
    EntityService().invalidateCache();
    notifyListeners();
  }

  /// 获取指定维度所有已生成区块的外接矩形边界
  Map<String, int>? getWorldBounds(int dimension) {
    int? minCx, maxCx, minCz, maxCz;
    int count = 0;
    for (final chunkStr in _existingChunks) {
      final parts = chunkStr.split(':');
      if (parts.length == 2 && int.tryParse(parts[0]) == dimension) {
        final coords = parts[1].split(',');
        if (coords.length == 2) {
          final cx = int.tryParse(coords[0]);
          final cz = int.tryParse(coords[1]);
          if (cx != null && cz != null) {
            count++;
            minCx = minCx == null ? cx : (cx < minCx ? cx : minCx);
            maxCx = maxCx == null ? cx : (cx > maxCx ? cx : maxCx);
            minCz = minCz == null ? cz : (cz < minCz ? cz : minCz);
            maxCz = maxCz == null ? cz : (cz > maxCz ? cz : maxCz);
          }
        }
      }
    }
    if (minCx != null && maxCx != null && minCz != null && maxCz != null) {
      return {
        'minCx': minCx,
        'maxCx': maxCx,
        'minCz': minCz,
        'maxCz': maxCz,
        'totalChunks': count,
      };
    }
    return null;
  }

  /// 判断指定维度和区块坐标是否已在数据库中生成
  bool hasChunk(int cx, int cz, int dim) {
    return _existingChunks.contains('$dim:$cx,$cz');
  }

  // ─── 存档加载与解析 ───

  /// 加载指定路径的 Minecraft 存档
  Future<bool> loadWorld(String worldFolderPath) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 1. 清空旧数据与缓存
      closeWorld(preserveLoadingState: true);

      _currentWorldPath = worldFolderPath;
      _currentWorldInfo = await StorageService().parseWorldInfo(worldFolderPath);

      // 自动备份
      if (AppSettings().autoBackupOnOpen) {
        try {
          await BackupService().createSnapshotBackup(worldFolderPath);
        } catch (_) {}
      }

      // 2. 读取 level.dat
      final levelDatFile = File(p.join(worldFolderPath, 'level.dat'));
      if (levelDatFile.existsSync()) {
        final bytes = await levelDatFile.readAsBytes();
        final parser = LittleEndianNbtParser();
        final root = parser.parseLevelDat(bytes);
        _nbtCache['level.dat'] = root;
        _nbtRootNames['level.dat'] = '';
        _parsePlayerPosition(root);
      }

      // 3. 读取 LevelDB 数据 (Isolate 多线程)
      final dbDir = Directory(p.join(worldFolderPath, 'db'));
      if (dbDir.existsSync()) {
        final response = await compute(_isolateLoadDb, _IsolateLoadRequest(dbDir.path));
        if (response.error != null) {
          _error = response.error;
        } else {
          rawEntries.addAll(response.rawEntries);
          rawKeyMap.addAll(response.rawKeyMap);
          _existingChunks.clear();
          _existingChunks.addAll(response.existingChunks);
        }
      }

      // 4. 解析 ~local_player (若存在)
      const localPlayerKey = '~local_player';
      final localPlayerBase64 = base64Encode(utf8.encode(localPlayerKey));
      if (rawEntries.containsKey(localPlayerBase64)) {
        try {
          final parser = LittleEndianNbtParser();
          final parsed = parser.parse(rawEntries[localPlayerBase64]!);
          _nbtCache[localPlayerKey] = parsed.value;
          _nbtRootNames[localPlayerKey] = parsed.key;
          _parsePlayerPositionFromLocalPlayer(parsed.value);
        } catch (_) {}
      }

      _isLoading = false;
      notifyListeners();

      // 异步触发玩家周围 Region 大单面瓦片预加载 (实现零延迟开图)
      GpuTileRenderer().preloadNearbyRegions(this, _playerX, _playerZ, _playerDimension);

      return true;
    } catch (e) {
      _error = '加载存档失败: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Isolate 后台加载 LevelDB 所有 .ldb 文件 (并预建区块索引加速)
  static _IsolateLoadResponse _isolateLoadDb(_IsolateLoadRequest request) {
    try {
      final dbDir = Directory(request.dbPath);
      final ldbFiles = dbDir.listSync().whereType<File>().where((f) => f.path.endsWith('.ldb') || p.basename(f.path).startsWith('0')).toList();

      final entries = <String, Uint8List>{};
      final keyMap = <String, Uint8List>{};
      final existingChunks = <String>{};

      for (final file in ldbFiles) {
        try {
          final bytes = file.readAsBytesSync();
          final reader = BELevelDBReader(bytes);
          final userMap = reader.readAllEntries();
          for (final e in userMap.entries) {
            final base64Key = base64Encode(e.key);
            entries[base64Key] = e.value;
            keyMap[base64Key] = e.key;

            final parsed = ParsedChunkKey.parse(e.key);
            if (parsed != null) {
              existingChunks.add('${parsed.dimension}:${parsed.chunkX},${parsed.chunkZ}');
            }
          }
        } catch (_) {}
      }

      return _IsolateLoadResponse(rawEntries: entries, rawKeyMap: keyMap, existingChunks: existingChunks);
    } catch (e) {
      return _IsolateLoadResponse(rawEntries: {}, rawKeyMap: {}, existingChunks: {}, error: e.toString());
    }
  }

  void _parsePlayerPosition(NbtCompound levelDat) {
    try {
      if (levelDat.value.containsKey('Player')) {
        final player = levelDat.value['Player'];
        if (player is NbtCompound && player.value.containsKey('Pos')) {
          final pos = player.value['Pos'];
          if (pos is NbtList && pos.value.length >= 3) {
            _playerX = (pos.value[0] as NbtFloat).value.toDouble();
            _playerY = (pos.value[1] as NbtFloat).value.toDouble();
            _playerZ = (pos.value[2] as NbtFloat).value.toDouble();
          }
          if (player.value.containsKey('DimensionId')) {
            _playerDimension = (player.value['DimensionId'] as NbtInt).value;
          }
        }
      }
    } catch (_) {}
  }

  void _parsePlayerPositionFromLocalPlayer(NbtCompound playerNbt) {
    try {
      if (playerNbt.value.containsKey('Pos')) {
        final pos = playerNbt.value['Pos'];
        if (pos is NbtList && pos.value.length >= 3) {
          _playerX = (pos.value[0] as NbtFloat).value.toDouble();
          _playerY = (pos.value[1] as NbtFloat).value.toDouble();
          _playerZ = (pos.value[2] as NbtFloat).value.toDouble();
        }
      }
      if (playerNbt.value.containsKey('DimensionId')) {
        _playerDimension = (playerNbt.value['DimensionId'] as NbtInt).value;
      }
    } catch (_) {}
  }

  // ─── 存档写回与保存 ───

  /// 保存所有修改到本地文件 (level.dat + LevelDB .ldb)
  Future<bool> saveChanges() async {
    if (_currentWorldPath == null) {
      _error = '未打开任何有效存档目录';
      notifyListeners();
      return false;
    }
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      // 1. 写回 level.dat 与 level.dat_old
      if (_nbtCache.containsKey('level.dat')) {
        final levelDatFile = File(p.join(_currentWorldPath!, 'level.dat'));
        final levelDatOldFile = File(p.join(_currentWorldPath!, 'level.dat_old'));
        final writer = LittleEndianNbtWriter();
        final bytes = writer.writeLevelDat(_nbtCache['level.dat']!);
        await levelDatFile.writeAsBytes(bytes, flush: true);
        try {
          await levelDatOldFile.writeAsBytes(bytes, flush: true);
        } catch (_) {}
      }

      // 2. 将 NBT 缓存中已修改的条目同步回 rawEntries
      final nbtWriter = LittleEndianNbtWriter();
      for (final e in _nbtCache.entries) {
        if (e.key == 'level.dat') continue;
        final rootName = _nbtRootNames[e.key] ?? '';
        final serialized = nbtWriter.writeRoot(rootName, e.value);

        // 如果是特殊键 (~local_player 等)
        if (e.key.startsWith('~') || e.key.contains(':')) {
          final b64 = base64Encode(utf8.encode(e.key));
          rawEntries[b64] = serialized;
          rawKeyMap[b64] = Uint8List.fromList(utf8.encode(e.key));
        } else {
          // 直接 base64 键
          rawEntries[e.key] = serialized;
        }
      }

      // 3. 构建并写回 LevelDB .ldb 文件
      final dbDir = Directory(p.join(_currentWorldPath!, 'db'));
      if (!dbDir.existsSync()) {
        dbDir.createSync(recursive: true);
      }

      final entriesToWrite = <Uint8List, Uint8List>{};
      for (final entry in rawEntries.entries) {
        final rawKey = rawKeyMap[entry.key] ?? base64Decode(entry.key);
        entriesToWrite[rawKey] = entry.value;
      }

      // 将所有数据整合写入现有的最新 .ldb 文件或 000004.ldb
      String targetLdbName = '000004.ldb';
      if (dbDir.existsSync()) {
        final existingLdbs = dbDir.listSync().whereType<File>().where((f) => f.path.endsWith('.ldb')).map((f) => p.basename(f.path)).toList();
        if (existingLdbs.isNotEmpty) {
          existingLdbs.sort();
          targetLdbName = existingLdbs.last;
        }
      }

      final ldbTarget = p.join(dbDir.path, targetLdbName);
      await BELevelDBWriter.saveToLdbFile(ldbTarget, entriesToWrite);

      _hasUnsavedChanges = false;
      _undoStack.clear();
      _redoStack.clear();
      _isSaving = false;
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = '保存存档失败: $e';
      _isSaving = false;
      notifyListeners();
      return false;
    }
  }

  // ─── 玩家操作 ───

  /// 传送玩家到指定位置
  void teleportPlayer(double x, double y, double z, int dimension) {
    final tx = PlayerTeleportTransaction(
      oldX: _playerX, oldY: _playerY, oldZ: _playerZ, oldDim: _playerDimension,
      newX: x, newY: y, newZ: z, newDim: dimension,
    );
    executeTransaction(tx);
  }

  void setPlayerPositionInternal(double x, double y, double z, int dimension) {
    _playerX = x;
    _playerY = y;
    _playerZ = z;
    _playerDimension = dimension;

    // 更新 level.dat NBT
    if (_nbtCache.containsKey('level.dat')) {
      final root = _nbtCache['level.dat']!;
      if (root.value.containsKey('Player') && root.value['Player'] is NbtCompound) {
        final pComp = root.value['Player'] as NbtCompound;
        pComp.value['Pos'] = NbtList(NbtTagType.float, [NbtFloat(x), NbtFloat(y), NbtFloat(z)]);
        pComp.value['DimensionId'] = NbtInt(dimension);
      }
    }

    // 更新 ~local_player NBT
    if (_nbtCache.containsKey('~local_player')) {
      final pComp = _nbtCache['~local_player']!;
      pComp.value['Pos'] = NbtList(NbtTagType.float, [NbtFloat(x), NbtFloat(y), NbtFloat(z)]);
      pComp.value['DimensionId'] = NbtInt(dimension);
    }

    _hasUnsavedChanges = true;
    notifyListeners();
  }

  // ─── NBT 树编辑与事务操作 ───

  /// 获取或解析 NBT Compound
  NbtCompound? getNbtCompound(String key) {
    if (_nbtCache.containsKey(key)) {
      return _nbtCache[key];
    }
    // 尝试从 rawEntries 解析 (无论 key 是 base64 还是 utf-8 字符串)
    Uint8List? rawBytes = rawEntries[key];
    if (rawBytes == null) {
      final b64 = base64Encode(utf8.encode(key));
      rawBytes = rawEntries[b64];
    }

    if (rawBytes != null) {
      try {
        final parser = LittleEndianNbtParser();
        final parsed = parser.parse(rawBytes);
        _nbtCache[key] = parsed.value;
        _nbtRootNames[key] = parsed.key;
        return parsed.value;
      } catch (_) {}
    }
    return null;
  }

  Map<String, NbtCompound> get nbtCache => _nbtCache;

  /// 提交 NBT 节点修改事务
  void commitNbtModification(String key, List<String> path, NbtTag oldTag, NbtTag newTag) {
    final tx = NbtModifyTransaction(key: key, path: path, oldTag: oldTag, newTag: newTag);
    executeTransaction(tx);
    _lastModifiedKey = key;
    _lastModifiedType = 'edit';
    notifyListeners();
  }

  /// 提交 NBT 节点新增事务
  void commitNbtAddition(String key, List<String> parentPath, String tagKey, NbtTag tag) {
    final tx = NbtAddTagTransaction(key: key, parentPath: parentPath, tagKey: tagKey, tag: tag);
    executeTransaction(tx);
    _lastModifiedKey = key;
    _lastModifiedType = 'add';
    notifyListeners();
  }

  /// 提交 NBT 节点删除事务
  void commitNbtDeletion(String key, List<String> path, NbtTag deletedTag, [int? listIndex]) {
    final tx = NbtDeleteTagTransaction(key: key, path: path, deletedTag: deletedTag, listIndex: listIndex);
    executeTransaction(tx);
    _lastModifiedKey = key;
    _lastModifiedType = 'delete';
    notifyListeners();
  }

  /// 提交 NBT 根节点替换事务 (导入 NBT 等)
  void commitNbtReplaceRoot(String key, NbtCompound oldRoot, NbtCompound newRoot) {
    final tx = NbtReplaceRootTransaction(key: key, oldRoot: oldRoot, newRoot: newRoot);
    executeTransaction(tx);
    _lastModifiedKey = key;
    _lastModifiedType = 'import';
    notifyListeners();
  }

  void executeTransaction(ArchiveTransaction tx) {
    tx.redo(this);
    _undoStack.add(tx);
    _redoStack.clear();
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void undo() {
    if (_undoStack.isNotEmpty) {
      final tx = _undoStack.removeLast();
      tx.undo(this);
      _redoStack.add(tx);
      _hasUnsavedChanges = _undoStack.isNotEmpty;
      _lastModifiedType = 'undo';
      notifyListeners();
    }
  }

  void redo() {
    if (_redoStack.isNotEmpty) {
      final tx = _redoStack.removeLast();
      tx.redo(this);
      _undoStack.add(tx);
      _hasUnsavedChanges = true;
      _lastModifiedType = 'redo';
      notifyListeners();
    }
  }

  void updateNbtAtPathDirectly(String key, List<String> path, NbtTag newTag) {
    final compound = getNbtCompound(key);
    if (compound == null) return;

    if (path.isEmpty) {
      if (newTag is NbtCompound) {
        _nbtCache[key] = newTag;
      }
    } else {
      NbtTag current = compound;
      for (int i = 0; i < path.length - 1; i++) {
        final seg = path[i];
        if (current is NbtCompound) {
          current = current.value[seg]!;
        } else if (current is NbtList) {
          final idx = int.parse(seg);
          current = current.value[idx];
        }
      }

      final lastSeg = path.last;
      if (current is NbtCompound) {
        current.value[lastSeg] = newTag;
      } else if (current is NbtList) {
        final idx = int.parse(lastSeg);
        current.value[idx] = newTag;
      }
    }

    _syncNbtBytes(key, compound);
    _hasUnsavedChanges = true;
  }

  void addNbtAtPathDirectly(String key, List<String> parentPath, String tagKey, NbtTag tag) {
    final compound = getNbtCompound(key);
    if (compound == null) return;

    NbtTag current = compound;
    for (int i = 0; i < parentPath.length; i++) {
      final seg = parentPath[i];
      if (current is NbtCompound) {
        current = current.value[seg]!;
      } else if (current is NbtList) {
        current = current.value[int.parse(seg)];
      }
    }

    if (current is NbtCompound) {
      current.value[tagKey] = tag;
    } else if (current is NbtList) {
      current.value.add(tag);
    }

    _syncNbtBytes(key, compound);
    _hasUnsavedChanges = true;
  }

  void deleteNbtAtPathDirectly(String key, List<String> path) {
    if (path.isEmpty) return;
    final compound = getNbtCompound(key);
    if (compound == null) return;

    NbtTag current = compound;
    for (int i = 0; i < path.length - 1; i++) {
      final seg = path[i];
      if (current is NbtCompound) {
        current = current.value[seg]!;
      } else if (current is NbtList) {
        current = current.value[int.parse(seg)];
      }
    }

    final last = path.last;
    if (current is NbtCompound) {
      current.value.remove(last);
    } else if (current is NbtList) {
      current.value.removeAt(int.parse(last));
    }

    _syncNbtBytes(key, compound);
    _hasUnsavedChanges = true;
  }

  void restoreDeletedNbtAtPath(String key, List<String> parentPath, String tagKey, NbtTag tag, int? listIndex) {
    final compound = getNbtCompound(key);
    if (compound == null) return;

    NbtTag current = compound;
    for (int i = 0; i < parentPath.length; i++) {
      final seg = parentPath[i];
      if (current is NbtCompound) {
        current = current.value[seg]!;
      } else if (current is NbtList) {
        current = current.value[int.parse(seg)];
      }
    }

    if (current is NbtCompound) {
      current.value[tagKey] = tag;
    } else if (current is NbtList) {
      if (listIndex != null && listIndex >= 0 && listIndex <= current.value.length) {
        current.value.insert(listIndex, tag);
      } else {
        current.value.add(tag);
      }
    }

    _syncNbtBytes(key, compound);
    _hasUnsavedChanges = true;
  }

  void replaceNbtRootDirectly(String key, NbtCompound newRoot) {
    _nbtCache[key] = newRoot;
    _syncNbtBytes(key, newRoot);
    _hasUnsavedChanges = true;
  }

  void _syncNbtBytes(String key, NbtCompound compound) {
    if (key != 'level.dat') {
      try {
        final rootName = _nbtRootNames[key] ?? '';
        final writer = LittleEndianNbtWriter();
        final bytes = writer.writeRoot(rootName, _nbtCache[key] ?? compound);
        if (rawEntries.containsKey(key)) {
          rawEntries[key] = bytes;
        } else {
          final b64 = base64Encode(utf8.encode(key));
          if (rawEntries.containsKey(b64)) {
            rawEntries[b64] = bytes;
          }
        }
      } catch (_) {}
    }
  }

  // ─── 数据库查询与分类 ───

  /// 获取全部分类数据库条目 (用于全功能 NBT 编辑器分类浏览)
  Map<String, List<MapEntry<String, String>>> getCategorizedDbKeys() {
    final categories = <String, List<MapEntry<String, String>>>{
      '世界核心数据': [
        const MapEntry('level.dat', '世界核心参数 (level.dat)'),
        const MapEntry('~local_player', '本地玩家 (~local_player)'),
        const MapEntry('AutonomousEntities', '自动实体数据 (AutonomousEntities)'),
        const MapEntry('scoreboard', '计分板 (scoreboard)'),
        const MapEntry('mobevents', '生物事件 (mobevents)'),
        const MapEntry('WorldClocks', '世界时钟 (WorldClocks)'),
        const MapEntry('POSTRACKDB', '位置追踪库 (POSTRACKDB)'),
      ],
      '多人游戏玩家': [],
      '生物与实体': [],
      '方块实体': [],
      '维度与全局': [
        const MapEntry('Overworld', '主世界全局 (Overworld)'),
        const MapEntry('NetherData', '下界数据 (NetherData)'),
        const MapEntry('TheEndData', '末地数据 (TheEndData)'),
        const MapEntry('biome_data', '群系全局数据 (biome_data)'),
      ],
      '村庄与聚集地': [],
      '结构模板': [],
      '地图画卷': [],
      '所有原始键': [],
    };

    for (final e in rawKeyMap.entries) {
      final base64Key = e.key;
      final rawKey = e.value;
      String? utf8Name;
      try {
        utf8Name = utf8.decode(rawKey, allowMalformed: false);
      } catch (_) {}

      // 检查 actorprefix 实体
      if (rawKey.length >= 19 && _hasActorPrefixBytes(rawKey)) {
        categories['生物与实体']!.add(MapEntry(base64Key, '实体 (actorprefix)'));
      }

      final parsed = ParsedChunkKey.parse(rawKey);
      if (parsed != null) {
        if (parsed.tag == ChunkTag.blockEntity || parsed.tag == ChunkTag.data2DLegacy) {
          categories['方块实体']!.add(MapEntry(base64Key, '方块实体 [${parsed.chunkX}, ${parsed.chunkZ}]'));
        } else if (parsed.tag == ChunkTag.entity) {
          categories['生物与实体']!.add(MapEntry(base64Key, '区块实体列表 [${parsed.chunkX}, ${parsed.chunkZ}]'));
        }
      }

      if (utf8Name != null) {
        if (utf8Name.startsWith('player_') || utf8Name.startsWith('player_server_')) {
          categories['多人游戏玩家']!.add(MapEntry(base64Key, utf8Name));
        } else if (utf8Name.startsWith('VILLAGE_')) {
          categories['村庄与聚集地']!.add(MapEntry(base64Key, utf8Name));
        } else if (utf8Name.startsWith('structuretemplate_')) {
          categories['结构模板']!.add(MapEntry(base64Key, utf8Name));
        } else if (utf8Name.startsWith('map_')) {
          categories['地图画卷']!.add(MapEntry(base64Key, utf8Name));
        }
      }

      // 所有原始键
      final displayKey = utf8Name ?? parsed?.toString() ?? 'Key[${rawKey.length}B]';
      categories['所有原始键']!.add(MapEntry(base64Key, displayKey));
    }

    return categories;
  }

  /// 搜索包含指定前缀的二进制键
  List<Uint8List> findKeysWithPrefix(Uint8List prefix) {
    final result = <Uint8List>[];
    for (final rawKey in rawKeyMap.values) {
      if (rawKey.length >= prefix.length) {
        bool match = true;
        for (int i = 0; i < prefix.length; i++) {
          if (rawKey[i] != prefix[i]) {
            match = false;
            break;
          }
        }
        if (match) result.add(rawKey);
      }
    }
    return result;
  }

  /// 获取多人游戏玩家键列表
  List<String> getNetworkPlayerKeys() {
    final result = <String>[];
    for (final e in rawKeyMap.entries) {
      try {
        final str = utf8.decode(e.value, allowMalformed: false);
        if (str.startsWith('player_') || str.startsWith('player_server_')) {
          result.add(str);
        }
      } catch (_) {}
    }
    return result;
  }

  bool _hasActorPrefixBytes(Uint8List key) {
    const prefix = [0x61, 0x63, 0x74, 0x6f, 0x72, 0x70, 0x72, 0x65, 0x66, 0x69, 0x78];
    if (key.length < prefix.length) return false;
    for (int i = 0; i < prefix.length; i++) {
      if (key[i] != prefix[i]) return false;
    }
    return true;
  }

  /// 关闭存档
  void closeWorld({bool preserveLoadingState = false}) {
    _currentWorldPath = null;
    _currentWorldInfo = null;
    if (!preserveLoadingState) {
      _isLoading = false;
    }
    _error = null;
    _hasUnsavedChanges = false;
    rawEntries.clear();
    rawKeyMap.clear();
    _existingChunks.clear();
    _nbtCache.clear();
    _nbtRootNames.clear();
    _undoStack.clear();
    _redoStack.clear();
    _lastModifiedKey = null;
    _lastModifiedType = '';
    ChunkCacheManager().clearAll();
    EntityService().invalidateCache();
    if (!preserveLoadingState) {
      notifyListeners();
    }
  }
}
