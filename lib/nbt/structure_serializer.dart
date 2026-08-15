import 'dart:io';
import 'dart:typed_data';
import '../data/data_manager.dart';
import '../models/selection_model.dart';
import 'nbt_parser.dart';
import 'nbt_tags.dart';

/// .mcstructure 格式序列化与导出器
class StructureSerializer {
  /// 将 3D 方块数组构建为 Bedrock .mcstructure NBT
  static Uint8List exportToMcStructure({
    required int sizeX,
    required int sizeY,
    required int sizeZ,
    required List<String> blockNames,
    List<NbtCompound> entities = const [],
  }) {
    // 1. 构建方块调色板 (Palette)
    final paletteList = <NbtCompound>[];
    final blockToPaletteIndex = <String, int>{};

    for (final name in blockNames) {
      if (!blockToPaletteIndex.containsKey(name)) {
        blockToPaletteIndex[name] = paletteList.length;
        paletteList.add(NbtCompound({
          'name': NbtString(name.startsWith('minecraft:') ? name : 'minecraft:$name'),
          'states': NbtCompound({}),
          'version': NbtInt(17959425),
        }));
      }
    }

    // 2. 映射方块索引
    final indices = blockNames.map((name) => blockToPaletteIndex[name] ?? 0).toList();

    // 3. 构建 Compound
    final root = NbtCompound({
      'format_version': NbtInt(1),
      'size': NbtList(NbtTagType.intValue, [
        NbtInt(sizeX),
        NbtInt(sizeY),
        NbtInt(sizeZ),
      ]),
      'structure_world_origin': NbtList(NbtTagType.intValue, [
        NbtInt(0),
        NbtInt(0),
        NbtInt(0),
      ]),
      'structure': NbtCompound({
        'block_indices': NbtList(NbtTagType.list, [
          NbtList(NbtTagType.intValue, indices.map((i) => NbtInt(i)).toList()),
          NbtList(NbtTagType.intValue, List.filled(indices.length, NbtInt(-1))),
        ]),
        'entities': NbtList(NbtTagType.compound, entities),
        'palette': NbtCompound({
          'default': NbtCompound({
            'block_palette': NbtList(NbtTagType.compound, paletteList),
            'block_position_data': NbtCompound({}),
          }),
        }),
      }),
    });

    final writer = LittleEndianNbtWriter();
    return writer.writeRoot('', root);
  }

  /// 导出选区为 .mcstructure 文件
  static Future<void> exportSelectionToStructureFile({
    required SelectionModel selection,
    required DataManager dataManager,
    required String outputPath,
  }) async {
    final totalBlocks = selection.sizeX * selection.sizeY * selection.sizeZ;
    final blockList = List.filled(totalBlocks > 0 ? totalBlocks : 1, 'minecraft:stone');
    final bytes = exportToMcStructure(
      sizeX: selection.sizeX,
      sizeY: selection.sizeY,
      sizeZ: selection.sizeZ,
      blockNames: blockList,
    );
    await exportToFile(outputPath, bytes);
  }

  /// 保存结构到本地文件
  static Future<void> exportToFile(String filePath, Uint8List structureBytes) async {
    final file = File(filePath);
    await file.writeAsBytes(structureBytes, flush: true);
  }
}
