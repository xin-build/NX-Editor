import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/data/data_manager.dart';
import 'package:flutter_app/nbt/nbt_parser.dart';
import 'package:flutter_app/nbt/nbt_tags.dart';
import 'package:flutter_app/services/entity_service.dart';

void main() {
  group('EntityService & Radar Test', () {
    test('Parse actorprefix entity and classify correctly', () {
      final dm = DataManager();

      // 构建一个 actorprefix 实体
      final entityNbt = NbtCompound({
        'identifier': NbtString('minecraft:zombie'),
        'CustomName': NbtString('狂暴僵尸王'),
        'Pos': NbtList(NbtTagType.float, [NbtFloat(100.5), NbtFloat(65.0), NbtFloat(-200.5)]),
        'Rotation': NbtList(NbtTagType.float, [NbtFloat(90.0), NbtFloat(0.0)]),
        'Health': NbtFloat(50.0),
        'DimensionId': NbtInt(0),
        'Invulnerable': NbtByte(1),
        'NoAI': NbtByte(0),
      });

      final writer = LittleEndianNbtWriter();
      final valBytes = writer.writeRoot('', entityNbt);

      // actorprefix (11B) + 8B uid
      final rawKey = Uint8List.fromList([
        0x61, 0x63, 0x74, 0x6f, 0x72, 0x70, 0x72, 0x65, 0x66, 0x69, 0x78,
        1, 2, 3, 4, 5, 6, 7, 8,
      ]);
      final b64Key = base64Encode(rawKey);

      dm.rawKeyMap[b64Key] = rawKey;
      dm.rawEntries[b64Key] = valBytes;

      final entities = EntityService().parseAllEntities(dm);
      expect(entities.length, 1);

      final ent = entities.first;
      expect(ent.identifier, 'minecraft:zombie');
      expect(ent.name, '狂暴僵尸王 (Zombie)');
      expect(ent.x, 100.5);
      expect(ent.y, 65.0);
      expect(ent.z, -200.5);
      expect(ent.health, 50.0);
      expect(ent.category, EntityCategory.hostile);
      expect(ent.iconAssetPath, 'assrts/images/entity/zombie.png');
    });
  });
}
