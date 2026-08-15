import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 游戏素材图标 GPU 纹理缓存服务 (用于在地图画布上硬件直绘生物与方块实体真实图标)
class AssetIconCache {
  static final AssetIconCache _instance = AssetIconCache._internal();
  factory AssetIconCache() => _instance;
  AssetIconCache._internal();

  final Map<String, ui.Image> _imageMap = {};
  final Set<String> _loadingKeys = {};

  /// 获取实体图标 GPU Image (若未加载则异步加载并触发回调)
  ui.Image? getEntityIcon(String identifier, {VoidCallback? onReady}) {
    final clean = identifier.replaceAll('minecraft:', '').toLowerCase();
    final path = 'assrts/images/entity/$clean.png';
    return _getImage(path, onReady);
  }

  /// 获取方块图标 GPU Image (全面覆盖自定义超平坦方块与方块实体)
  ui.Image? getBlockIcon(String blockId, {VoidCallback? onReady}) {
    final clean = blockId.replaceAll('minecraft:', '').toLowerCase();
    String fileName = '$clean.png';

    if (clean == 'grass' || clean == 'grass_block') {
      fileName = 'grass_block.png';
    } else if (clean == 'grass_path' || clean == 'dirt_path') {
      fileName = 'grass_path.png';
    } else if (clean == 'dirt') {
      fileName = 'dirt.png';
    } else if (clean == 'bedrock') {
      fileName = 'bedrock.png';
    } else if (clean == 'sand') {
      fileName = 'sand.png';
    } else if (clean == 'stone') {
      fileName = 'stone.png';
    } else if (clean == 'tnt') {
      fileName = 'tnt.png';
    } else if (clean == 'obsidian') {
      fileName = 'obsidian.png';
    } else if (clean == 'cobblestone') {
      fileName = 'cobblestone.png';
    } else if (clean == 'glass') {
      fileName = 'glass.png';
    } else if (clean == 'water') {
      fileName = 'flowing_water.png';
    } else if (clean == 'lava') {
      fileName = 'lava.gif';
    } else if (clean.contains('chest')) {
      fileName = 'chest.png';
    } else if (clean.contains('spawner')) {
      fileName = 'mob_spawner.png';
    } else if (clean.contains('command')) {
      fileName = 'command_block.png';
    } else if (clean.contains('barrel')) {
      fileName = 'barrel.png';
    } else if (clean.contains('shulker')) {
      fileName = 'black_shulker_box.png';
    } else if (clean.contains('furnace')) {
      fileName = 'furnace.png';
    } else if (clean.contains('blast')) {
      fileName = 'blast_furnace.png';
    } else if (clean.contains('smoker')) {
      fileName = 'lit_smoker.png';
    } else if (clean.contains('hopper')) {
      fileName = 'hopper.png';
    } else if (clean.contains('dropper')) {
      fileName = 'dropper.png';
    } else if (clean.contains('dispenser')) {
      fileName = 'dispenser.png';
    } else if (clean.contains('enchant')) {
      fileName = 'enchanting_table.png';
    } else if (clean.contains('beacon')) {
      fileName = 'beacon.png';
    } else if (clean.contains('conduit')) {
      fileName = 'conduit.png';
    } else if (clean.contains('sensor')) {
      fileName = 'daylight_detector.png';
    } else if (clean.contains('campfire')) {
      fileName = 'campfire.gif';
    }

    final path = 'assrts/images/block/$fileName';
    return _getImage(path, onReady);
  }

  ui.Image? _getImage(String assetPath, VoidCallback? onReady) {
    if (_imageMap.containsKey(assetPath)) {
      return _imageMap[assetPath];
    }

    if (_loadingKeys.contains(assetPath)) return null;
    _loadingKeys.add(assetPath);

    _loadAssetImage(assetPath).then((img) {
      if (img != null) {
        _imageMap[assetPath] = img;
        onReady?.call();
      }
    }).whenComplete(() {
      _loadingKeys.remove(assetPath);
    });

    return null;
  }

  Future<ui.Image?> _loadAssetImage(String path) async {
    try {
      final byteData = await rootBundle.load(path);
      final bytes = Uint8List.view(byteData.buffer);
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, (img) {
        completer.complete(img);
      });
      return await completer.future;
    } catch (_) {
      return null;
    }
  }
}
