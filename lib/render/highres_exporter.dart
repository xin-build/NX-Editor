import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../data/data_manager.dart';
import '../models/app_settings.dart';
import '../models/selection_model.dart';
import 'gpu_tile_renderer.dart';

/// 高清地图导出器 (Picer)
class HighResExporter {
  /// 导出选区或全地图为高清 PNG 图片
  static Future<File> exportMapToPng({
    required SelectionModel selection,
    required DataManager dataManager,
    required MapLayerMode layerMode,
    required String targetFilePath,
    double pixelsPerBlock = 4.0, // 每个方块渲染像素数
    void Function(double progress)? onProgress,
  }) async {
    final totalWidth = (selection.sizeX * pixelsPerBlock).round();
    final totalHeight = (selection.sizeZ * pixelsPerBlock).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, totalWidth.toDouble(), totalHeight.toDouble()));

    // 绘制深色背景
    final bgPaint = Paint()..color = const Color(0xFF1E222B);
    canvas.drawRect(Rect.fromLTWH(0, 0, totalWidth.toDouble(), totalHeight.toDouble()), bgPaint);

    final renderer = GpuTileRenderer();
    final tilePaint = Paint();

    int totalChunks = selection.totalChunks;
    int renderedChunks = 0;

    final minBlockX = selection.minX;
    final minBlockZ = selection.minZ;

    for (int cx = selection.minChunkX; cx <= selection.maxChunkX; cx++) {
      for (int cz = selection.minChunkZ; cz <= selection.maxChunkZ; cz++) {
        final chunkOriginX = cx * 16;
        final chunkOriginZ = cz * 16;

        final destLeft = (chunkOriginX - minBlockX) * pixelsPerBlock;
        final destTop = (chunkOriginZ - minBlockZ) * pixelsPerBlock;
        final destSize = 16 * pixelsPerBlock;

        final destRect = Rect.fromLTWH(destLeft, destTop, destSize, destSize);

        renderer.drawChunkTile(
          canvas: canvas,
          chunkX: cx,
          chunkZ: cz,
          dimension: selection.dimension,
          layerMode: layerMode,
          destRect: destRect,
          dataManager: dataManager,
          paint: tilePaint,
        );

        renderedChunks++;
        onProgress?.call(renderedChunks / totalChunks);
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(totalWidth, totalHeight);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      throw Exception('生成 PNG 图片数据失败');
    }

    final file = File(targetFilePath);
    await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    return file;
  }
}
