import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/data/data_manager.dart';
import 'package:flutter_app/nbt/nbt_clipboard.dart';
import 'package:flutter_app/nbt/nbt_parser.dart';
import 'package:flutter_app/nbt/nbt_tags.dart';

void main() {
  group('NBT Editor & Clipboard Tests', () {
    test('NbtTagType metadata helper tests', () {
      expect(NbtTagType.getTypeName(NbtTagType.byte), 'TAG_Byte');
      expect(NbtTagType.getTypeChineseName(NbtTagType.compound), 'Compound (复合字典结构)');
      expect(NbtTagType.getTypeBadge(NbtTagType.string), 'STR');
      expect(NbtTagType.getTypeBadge(NbtTagType.list), '[ ]');
      expect(NbtTagType.getTypeBadge(NbtTagType.compound), '{ }');
    });

    test('NbtClipboard copy, clone, and clear', () {
      final clipboard = NbtClipboard();
      clipboard.clear();
      expect(clipboard.hasItem, false);

      final originalCompound = NbtCompound({
        'LevelName': NbtString('Test World'),
        'GameType': NbtInt(1),
        'Pos': NbtList(NbtTagType.double, [NbtDouble(10.5), NbtDouble(64.0), NbtDouble(-20.5)]),
      });

      clipboard.copy('LevelData', originalCompound, sourceKey: 'level.dat', sourcePath: ['Data']);
      expect(clipboard.hasItem, true);
      expect(clipboard.name, 'LevelData');
      expect(clipboard.type, NbtTagType.compound);

      // Verify that tag getter returns a deep clone
      final cloned = clipboard.tag as NbtCompound;
      expect(cloned.value['LevelName']?.toJson(), 'Test World');

      // Modifying cloned copy does not affect clipboard's stored copy
      (cloned.value['LevelName'] as NbtString).value = 'Modified';
      expect((clipboard.tag as NbtCompound).value['LevelName']?.toJson(), 'Test World');

      clipboard.clear();
      expect(clipboard.hasItem, false);
      expect(clipboard.tag, null);
    });

    test('DataManager NBT Add, Delete, and Undo/Redo transactions', () {
      final dm = DataManager();
      const testKey = 'test_entry';
      final root = NbtCompound({
        'Score': NbtInt(100),
        'Inventory': NbtList(NbtTagType.string, [NbtString('apple'), NbtString('bread')]),
        'Nested': NbtCompound({
          'SubKey': NbtString('Initial'),
        }),
      });

      dm.nbtCache[testKey] = root;

      // 1. Add tag to Compound
      dm.commitNbtAddition(testKey, [], 'ExtraTag', NbtString('Hello World'));
      expect(root.value.containsKey('ExtraTag'), true);
      expect(root.value['ExtraTag']?.toJson(), 'Hello World');

      // 2. Undo addition
      dm.undo();
      expect(root.value.containsKey('ExtraTag'), false);

      // 3. Redo addition
      dm.redo();
      expect(root.value.containsKey('ExtraTag'), true);

      // 4. Delete tag from Compound
      final toDelete = root.value['ExtraTag']!;
      dm.commitNbtDeletion(testKey, ['ExtraTag'], toDelete);
      expect(root.value.containsKey('ExtraTag'), false);

      // 5. Undo deletion
      dm.undo();
      expect(root.value.containsKey('ExtraTag'), true);
      expect(root.value['ExtraTag']?.toJson(), 'Hello World');

      // 6. Add tag to nested Compound
      dm.commitNbtAddition(testKey, ['Nested'], 'SubTag2', NbtInt(42));
      final nested = root.value['Nested'] as NbtCompound;
      expect(nested.value['SubTag2']?.toJson(), 42);

      // 7. Delete nested tag and undo
      final nestedToDelete = nested.value['SubTag2']!;
      dm.commitNbtDeletion(testKey, ['Nested', 'SubTag2'], nestedToDelete);
      expect(nested.value.containsKey('SubTag2'), false);
      dm.undo();
      expect(nested.value.containsKey('SubTag2'), true);
      expect(nested.value['SubTag2']?.toJson(), 42);
    });

    test('LittleEndianNbtParser.parseAnyNbt handles direct and header-prefixed NBT', () {
      final root = NbtCompound({
        'Author': NbtString('Minecrafter'),
        'Count': NbtInt(99),
      });

      final writer = LittleEndianNbtWriter();
      final rawBytes = writer.writeRoot('Root', root);

      // Direct NBT bytes
      final parsed1 = LittleEndianNbtParser.parseAnyNbt(rawBytes);
      expect(parsed1.key, 'Root');
      expect(parsed1.value.value['Author']?.toJson(), 'Minecrafter');
      expect(parsed1.value.value['Count']?.toJson(), 99);

      // Bedrock level.dat header prefixed bytes (version 4-byte + length 4-byte)
      final headerBytes = Uint8List(8 + rawBytes.length);
      final byteData = ByteData.sublistView(headerBytes);
      byteData.setInt32(0, 10, Endian.little);
      byteData.setInt32(4, rawBytes.length, Endian.little);
      headerBytes.setRange(8, 8 + rawBytes.length, rawBytes);

      final parsed2 = LittleEndianNbtParser.parseAnyNbt(headerBytes);
      expect(parsed2.value.value['Author']?.toJson(), 'Minecrafter');
    });
  });
}
