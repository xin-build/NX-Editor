import 'dart:typed_data';
import '../nbt/nbt_parser.dart';
import '../nbt/nbt_tags.dart';

/// 矿物与空洞（矿洞）查找算法引擎
class AdvancedAnalysisEngine {
  /// 1. 矿洞查找（地下大范围空洞检测算法）
  static List<List<int>> findCaves({
    required Map<String, Uint8List> rawEntries,
    required Map<String, Uint8List> rawKeyMap,
    required int dimension,
    required int minY,
    required int maxY,
    int minCaveVolume = 100,
  }) {
    final List<List<int>> caveCoordinates = [];

    // 遍历所有 SubChunk (tag 47) 寻找大范围空气连通域
    rawEntries.forEach((keyStr, value) {
      final keyBytes = rawKeyMap[keyStr];
      if (keyBytes == null) return;
      final parsed = _parseChunkKey(keyBytes);
      if (parsed == null || parsed.dim != dimension || parsed.tag != 47) return;
      final subY = parsed.sub ?? 0;
      final yBase = subY * 16;
      if (yBase > maxY || yBase + 15 < minY) return;

      // 解析 SubChunk 调色板
      final topBlocks = _parseSubChunkTopBlocks(value);
      if (topBlocks == null) return;

      // 统计该 SubChunk 内空气方块数量，若大面积连续空气则记录
      int airCount = 0;
      for (int z = 0; z < 16; z++) {
        for (int x = 0; x < 16; x++) {
          final idx = z * 16 + x;
          if (idx < topBlocks.length &&
              (topBlocks[idx] == 'minecraft:air' ||
                  topBlocks[idx] == 'minecraft:cave_air')) {
            airCount++;
          }
        }
      }
      if (airCount > 200) {
        caveCoordinates.add([
          parsed.cx * 16 + 8,
          yBase + 8,
          parsed.cz * 16 + 8,
        ]);
      }
    });

    return caveCoordinates;
  }

  /// 2. 矿物/特定方块全局查找
  static List<List<int>> findBlocks({
    required Map<String, Uint8List> rawEntries,
    required Map<String, Uint8List> rawKeyMap,
    required int dimension,
    required String targetBlockId,
    required int minY,
    required int maxY,
  }) {
    final List<List<int>> foundCoordinates = [];

    rawEntries.forEach((keyStr, value) {
      final keyBytes = rawKeyMap[keyStr];
      if (keyBytes == null) return;
      final parsed = _parseChunkKey(keyBytes);
      if (parsed == null || parsed.dim != dimension || parsed.tag != 47) return;
      final subY = parsed.sub ?? 0;
      final yBase = subY * 16;
      if (yBase + 15 < minY || yBase > maxY) return;

      try {
        final parser = LittleEndianNbtParser(value);
        final result = parser.parse();
        final root = result.value;

        // 新版格式：sections list
        final sections = root.value['sections'];
        Iterable<NbtCompound> sectionList;
        if (sections is NbtList) {
          sectionList = sections.value.whereType<NbtCompound>();
        } else {
          return;
        }

        for (final section in sectionList) {
          final palette = section.value['block_palette'];
          if (palette is! NbtList || palette.elementType != NbtTagType.compound) {
            continue;
          }
          final blockData = section.value['block_data'];
          if (blockData is! NbtIntArray && blockData is! NbtByteArray) {
            continue;
          }

          // 检查 palette 是否包含目标方块
          int targetIdx = -1;
          for (int i = 0; i < palette.value.length; i++) {
            final entry = palette.value[i];
            if (entry is NbtCompound) {
              final name = entry.value['name'];
              if (name is NbtString && name.value == targetBlockId) {
                targetIdx = i;
                break;
              }
            }
          }
          if (targetIdx < 0) continue;

          // 解码方块索引，定位目标方块坐标
          final bitsPerBlock = _bitsNeeded(palette.value.length);
          final blocksPerWord = 32 ~/ bitsPerBlock;
          final mask = (1 << bitsPerBlock) - 1;

          for (int ty = 0; ty < 16; ty++) {
            final y = yBase + ty;
            if (y < minY || y > maxY) continue;
            for (int tz = 0; tz < 16; tz++) {
              for (int tx = 0; tx < 16; tx++) {
                final subIdx = ty * 256 + tz * 16 + tx;
                final wordIdx = subIdx ~/ blocksPerWord;
                final bitOffset = (subIdx % blocksPerWord) * bitsPerBlock;
                late final int paletteIdx;
                if (blockData is NbtIntArray &&
                    wordIdx < blockData.value.length) {
                  paletteIdx = (blockData.value[wordIdx] >> bitOffset) & mask;
                } else if (blockData is NbtByteArray &&
                    wordIdx < blockData.value.length) {
                  paletteIdx = (blockData.value[wordIdx] >> bitOffset) & mask;
                } else {
                  continue;
                }
                if (paletteIdx == targetIdx) {
                  foundCoordinates.add([
                    parsed.cx * 16 + tx,
                    y,
                    parsed.cz * 16 + tz,
                  ]);
                }
              }
            }
          }
        }
      } catch (_) {}
    });

    return foundCoordinates;
  }

  /// 解析 SubChunk 顶层方块（简化版）
  static List<String>? _parseSubChunkTopBlocks(Uint8List data) {
    try {
      final parser = LittleEndianNbtParser(data);
      final result = parser.parse();
      final root = result.value;
      final sections = root.value['sections'];
      if (sections is! NbtList || sections.value.isEmpty) return null;
      final topBlocks = <String>[];

      for (final section in sections.value) {
        if (section is! NbtCompound) continue;
        final palette = section.value['block_palette'];
        if (palette is! NbtList) continue;
        final blockData = section.value['block_data'];
        if (blockData is! NbtIntArray && blockData is! NbtByteArray) continue;

        final names = <String>[];
        for (final e in palette.value) {
          if (e is NbtCompound) {
            final n = e.value['name'];
            names.add(n is NbtString ? n.value : 'minecraft:air');
          } else {
            names.add('minecraft:air');
          }
        }
        if (names.isEmpty) continue;

        final bp = _bitsNeeded(names.length);
        final bw = 32 ~/ bp;
        final mask = (1 << bp) - 1;

        for (int z = 0; z < 16; z++) {
          for (int x = 0; x < 16; x++) {
            final si = 15 * 256 + z * 16 + x; // 最高层
            final wi = si ~/ bw;
            final bo = (si % bw) * bp;
            late final int pi;
            if (blockData is NbtIntArray && wi < blockData.value.length) {
              pi = (blockData.value[wi] >> bo) & mask;
            } else if (blockData is NbtByteArray &&
                wi < blockData.value.length) {
              pi = (blockData.value[wi] >> bo) & mask;
            } else {
              topBlocks.add('minecraft:air');
              continue;
            }
            topBlocks.add(pi < names.length ? names[pi] : 'minecraft:air');
          }
        }
        break; // 只解析第一个 section
      }
      return topBlocks;
    } catch (_) {
      return null;
    }
  }

  static _ParsedChunkKey? _parseChunkKey(Uint8List key) {
    if (key.length < 9) return null;
    int signedByte(int v) => (v & 0x80) != 0 ? v - 256 : v;
    final bd = ByteData.sublistView(key);
    final cx = bd.getInt32(0, Endian.little);
    final cz = bd.getInt32(4, Endian.little);
    if (key.length == 9) {
      return _ParsedChunkKey(cx, cz, 0, key[8], null);
    }
    if (key.length == 10) {
      return _ParsedChunkKey(cx, cz, 0, key[8], signedByte(key[9]));
    }
    if (key.length == 13) {
      return _ParsedChunkKey(
        cx,
        cz,
        bd.getInt32(8, Endian.little),
        key[12],
        null,
      );
    }
    if (key.length == 14) {
      return _ParsedChunkKey(
        cx,
        cz,
        bd.getInt32(8, Endian.little),
        key[12],
        signedByte(key[13]),
      );
    }
    return null;
  }

  static int _bitsNeeded(int size) {
    if (size <= 1) return 1;
    if (size <= 2) return 1;
    if (size <= 4) return 2;
    if (size <= 8) return 3;
    if (size <= 16) return 4;
    if (size <= 32) return 5;
    if (size <= 64) return 6;
    if (size <= 128) return 7;
    if (size <= 256) return 8;
    return 16;
  }
}

class _ParsedChunkKey {
  final int cx, cz, dim, tag;
  final int? sub;
  _ParsedChunkKey(this.cx, this.cz, this.dim, this.tag, this.sub);
}
