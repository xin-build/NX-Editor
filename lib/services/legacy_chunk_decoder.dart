import 'dart:typed_data';
import '../nbt/nbt_parser.dart';
import '../nbt/nbt_tags.dart';

/// 低版本 / 经典版本 (PE 0.11 - 0.14 & Bedrock 0.14 - 1.17) 区块与数据解码器
class LegacyChunkDecoder {
  /// 解码旧版 2D 生态群系与高度图 (Tag 45 Data2D: 256B Biome + 512B HeightMap)
  static Map<String, dynamic> decodeData2D(Uint8List data) {
    final biomes = Uint8List(256);
    final heights = Uint16List(256);

    if (data.length >= 256) {
      biomes.setRange(0, 256, data.sublist(0, 256));
    }

    if (data.length >= 768) {
      final bd = ByteData.sublistView(data, 256, 768);
      for (int i = 0; i < 256; i++) {
        heights[i] = bd.getUint16(i * 2, Endian.little);
      }
    } else if (data.length >= 512) {
      // 某些早期版本只有 512 字节高度图
      final bd = ByteData.sublistView(data, 0, 512);
      for (int i = 0; i < 256; i++) {
        heights[i] = bd.getUint16(i * 2, Endian.little);
      }
    }

    return {
      'biomes': biomes,
      'heights': heights,
    };
  }

  /// 解码旧版无调色板/早期 SubChunk (Tag 48 或 Version 1~7 SubChunk)
  static List<String>? decodeLegacySubChunk(Uint8List data) {
    if (data.isEmpty) return null;

    final version = data[0];

    // Version 1 ~ 7 (无签名 Y 索引，默认从下往上)
    if (version >= 1 && version <= 7) {
      int offset = 2;

      // 遍历 Block Storage
      if (offset < data.length) {
        final header = data[offset++];
        final bitsPerBlock = header >> 1;
        final isPalette = (header & 1) == 0;

        if (isPalette && bitsPerBlock > 0) {
          final blocksPerWord = 32 ~/ bitsPerBlock;
          final wordCount = (4096 + blocksPerWord - 1) ~/ blocksPerWord;

          final indices = List.filled(4096, 0);
          final bd = ByteData.sublistView(data);
          int index = 0;

          for (int w = 0; w < wordCount && (offset + w * 4 + 4) <= data.length; w++) {
            final word = bd.getUint32(offset + w * 4, Endian.little);
            for (int b = 0; b < blocksPerWord && index < 4096; b++) {
              indices[index++] = (word >> (b * bitsPerBlock)) & ((1 << bitsPerBlock) - 1);
            }
          }
          offset += wordCount * 4;

          // 读取 Palette
          if (offset + 4 <= data.length) {
            final paletteSize = bd.getUint32(offset, Endian.little);
            offset += 4;

            final paletteNames = <String>[];
            final parser = LittleEndianNbtParser();

            for (int p = 0; p < paletteSize && offset < data.length; p++) {
              try {
                final tag = parser.parseFromBuffer(data.sublist(offset));
                if (tag is NbtCompound && tag.value.containsKey('name')) {
                  final nameTag = tag.value['name'];
                  if (nameTag is NbtString) {
                    paletteNames.add(nameTag.value);
                  } else {
                    paletteNames.add('minecraft:stone');
                  }
                } else {
                  paletteNames.add('minecraft:stone');
                }
                // 推进 offset
                offset += parser.bytesRead;
              } catch (_) {
                break;
              }
            }

            if (paletteNames.isNotEmpty) {
              return indices.map((idx) => idx < paletteNames.length ? paletteNames[idx] : 'minecraft:air').toList();
            }
          }
        }
      }
    } else if (version == 0 && data.length >= 4096) {
      // 远古版本直接 4096 字节 Block ID
      final result = <String>[];
      for (int i = 1; i <= 4096 && i < data.length; i++) {
        final id = data[i];
        result.add(id == 0 ? 'minecraft:air' : 'minecraft:stone');
      }
      return result;
    }

    return null;
  }

  /// 解码旧版嵌入在区块中的实体列表 (Tag 50 Entity)
  static List<NbtCompound> decodeLegacyEntities(Uint8List data) {
    final entities = <NbtCompound>[];
    if (data.isEmpty) return entities;

    int offset = 0;
    final parser = LittleEndianNbtParser();

    while (offset < data.length) {
      try {
        final tag = parser.parseFromBuffer(data.sublist(offset));
        if (tag is NbtCompound) {
          entities.add(tag);
        }
        if (parser.bytesRead <= 0) break;
        offset += parser.bytesRead;
      } catch (_) {
        break;
      }
    }

    return entities;
  }
}
