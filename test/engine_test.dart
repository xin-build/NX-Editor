import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/leveldb/leveldb_writer.dart';
import 'package:flutter_app/leveldb/leveldb_reader.dart';
import 'package:flutter_app/models/chunk_key.dart';
import 'package:flutter_app/nbt/nbt_parser.dart';
import 'package:flutter_app/nbt/nbt_tags.dart';
import 'package:flutter_app/nbt/structure_serializer.dart';

void main() {
  group('NBT & LevelDB Engines Test', () {
    test('LittleEndianNbtParser and Writer round-trip', () {
      final root = NbtCompound({
        'LevelName': NbtString('测试世界'),
        'RandomSeed': NbtLong(1234567890),
        'GameType': NbtInt(1),
        'Difficulty': NbtInt(2),
        'Pos': NbtList(NbtTagType.float, [NbtFloat(100.5), NbtFloat(64.0), NbtFloat(-200.5)]),
      });

      final writer = LittleEndianNbtWriter();
      final bytes = writer.writeLevelDat(root);

      final parser = LittleEndianNbtParser();
      final parsed = parser.parseLevelDat(bytes);

      expect((parsed.value['LevelName'] as NbtString).value, '测试世界');
      expect((parsed.value['RandomSeed'] as NbtLong).value, 1234567890);
      expect((parsed.value['GameType'] as NbtInt).value, 1);
    });

    test('BELevelDBWriter and BELevelDBReader round-trip', () {
      final key1 = Uint8List.fromList([1, 2, 3, 4]);
      final val1 = Uint8List.fromList([10, 20, 30, 40]);
      final key2 = Uint8List.fromList([5, 6, 7, 8]);
      final val2 = Uint8List.fromList([50, 60, 70, 80]);

      final sstableBytes = BELevelDBWriter.buildSSTable({
        key1: val1,
        key2: val2,
      });

      expect(sstableBytes.length, greaterThan(48));

      final reader = BELevelDBReader(sstableBytes);
      final readEntries = reader.readAllEntries();

      expect(readEntries.length, 2);
    });

    test('ChunkKey parse and build round-trip', () {
      final key = ParsedChunkKey.buildKey(10, -5, 0, ChunkTag.subChunk, subChunkY: 3);
      final parsed = ParsedChunkKey.parse(key);

      expect(parsed, isNotNull);
      expect(parsed!.chunkX, 10);
      expect(parsed.chunkZ, -5);
      expect(parsed.dimension, 0);
      expect(parsed.tag, ChunkTag.subChunk);
      expect(parsed.subChunkY, 3);
    });

    test('StructureSerializer export', () {
      final bytes = StructureSerializer.exportToMcStructure(
        sizeX: 2,
        sizeY: 2,
        sizeZ: 2,
        blockNames: [
          'minecraft:stone', 'minecraft:stone',
          'minecraft:stone', 'minecraft:stone',
          'minecraft:air', 'minecraft:air',
          'minecraft:air', 'minecraft:air',
        ],
      );

      expect(bytes.length, greaterThan(0));
    });
  });
}
