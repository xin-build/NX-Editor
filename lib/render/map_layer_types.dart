import 'package:flutter/material.dart';

/// 渲染图层类型与配置
class MapLayerConfig {
  final String name;
  final String description;
  final IconData icon;
  final bool is3D;
  final bool supportsSlicing;

  const MapLayerConfig({
    required this.name,
    required this.description,
    required this.icon,
    this.is3D = false,
    this.supportsSlicing = false,
  });

  /// 高度图颜色映射 (从 -64 到 320)
  static Color heightToColor(int height) {
    final normalized = ((height + 64) / 384.0).clamp(0.0, 1.0);

    if (normalized < 0.2) {
      return Color.lerp(const Color(0xFF0D1B2A), const Color(0xFF1B263B), normalized / 0.2)!;
    } else if (normalized < 0.4) {
      return Color.lerp(const Color(0xFF1B263B), const Color(0xFF0077B6), (normalized - 0.2) / 0.2)!;
    } else if (normalized < 0.6) {
      return Color.lerp(const Color(0xFF2D6A4F), const Color(0xFF95D5B2), (normalized - 0.4) / 0.2)!;
    } else if (normalized < 0.8) {
      return Color.lerp(const Color(0xFFDDA15E), const Color(0xFFBC6C25), (normalized - 0.6) / 0.2)!;
    } else {
      return Color.lerp(const Color(0xFFD8E2DC), const Color(0xFFFFFFFF), (normalized - 0.8) / 0.2)!;
    }
  }

  /// 生物群系颜色映射 (严格 100% 对齐 assrts/data/biomes.json 官方 ID 表)
  static Color biomeToColor(int biomeId) {
    switch (biomeId) {
      // 0 ~ 9
      case 0: return const Color(0xFF002B49); // 海洋 (ocean)
      case 1: return const Color(0xFF84CC16); // 平原 (plains)
      case 2: return const Color(0xFFEAB308); // 沙漠 (desert)
      case 3: return const Color(0xFF4B6B46); // 风袭丘陵 (extreme_hills)
      case 4: return const Color(0xFF15803D); // 森林 (forest)
      case 5: return const Color(0xFF047857); // 针叶林 (taiga)
      case 6: return const Color(0xFF3F6212); // 沼泽 (swampland)
      case 7: return const Color(0xFF0077B6); // 河流 (river)
      case 8: return const Color(0xFF7F1D1D); // 下界荒地 (hell / nether_wastes)
      case 9: return const Color(0xFFFEF08A); // 末地 (the_end)

      // 10 ~ 19
      case 10: return const Color(0xFF90E0EF); // 冻洋（旧版） (legacy_frozen_ocean)
      case 11: return const Color(0xFFA2D2FF); // 冻河 (frozen_river)
      case 12: return const Color(0xFFE2E8F0); // 雪原 (ice_plains)
      case 13: return const Color(0xFFCBD5E1); // 雪山 (ice_mountains)
      case 14: return const Color(0xFFA855F7); // 蘑菇岛 (mushroom_island)
      case 15: return const Color(0xFF9333EA); // 蘑菇岛岸 (mushroom_island_shore)
      case 16: return const Color(0xFFFDE68A); // 沙滩 (beach)
      case 17: return const Color(0xFFCA8A04); // 沙漠丘陵 (desert_hills)
      case 18: return const Color(0xFF166534); // 繁茂的丘陵 (forest_hills)
      case 19: return const Color(0xFF065F46); // 针叶林丘陵 (taiga_hills)

      // 20 ~ 29
      case 20: return const Color(0xFF364E35); // 山地边缘 (extreme_hills_edge)
      case 21: return const Color(0xFF22C55E); // 丛林 (jungle)
      case 22: return const Color(0xFF16A34A); // 丛林丘陵 (jungle_hills)
      case 23: return const Color(0xFF15803D); // 稀疏丛林 (jungle_edge)
      case 24: return const Color(0xFF001F35); // 深海 (deep_ocean)
      case 25: return const Color(0xFF94A3B8); // 石岸 (stone_beach)
      case 26: return const Color(0xFFE2E8F0); // 积雪沙滩 (cold_beach)
      case 27: return const Color(0xFF65A30D); // 桦木森林 (birch_forest)
      case 28: return const Color(0xFF4D7C0F); // 桦木森林丘陵 (birch_forest_hills)
      case 29: return const Color(0xFF14532D); // 黑森林 (roofed_forest)

      // 30 ~ 39
      case 30: return const Color(0xFFA7F3D0); // 积雪针叶林 (cold_taiga)
      case 31: return const Color(0xFF6EE7B7); // 积雪的针叶林丘陵 (cold_taiga_hills)
      case 32: return const Color(0xFF064E3B); // 原始松木针叶林 (mega_taiga)
      case 33: return const Color(0xFF022C22); // 巨型针叶林丘陵 (mega_taiga_hills)
      case 34: return const Color(0xFF3B5E38); // 风袭森林 (extreme_hills_plus_trees)
      case 35: return const Color(0xFFD97706); // 热带草原 (savanna)
      case 36: return const Color(0xFFB45309); // 热带高原 (savanna_plateau)
      case 37: return const Color(0xFFEA580C); // 恶地 (mesa)
      case 38: return const Color(0xFFC2410C); // 繁茂的恶地高原 (mesa_plateau_stone)
      case 39: return const Color(0xFF9A3412); // 恶地高原 (mesa_plateau)

      // 40 ~ 49 (海洋与竹林)
      case 40: return const Color(0xFF0077B6); // 暖水海洋 (warm_ocean)
      case 41: return const Color(0xFF00B4D8); // 暖水深海 (deep_warm_ocean)
      case 42: return const Color(0xFF48CAE4); // 温水海洋 (lukewarm_ocean)
      case 43: return const Color(0xFF005F73); // 温水深海 (deep_lukewarm_ocean)
      case 44: return const Color(0xFF0096C7); // 冷水海洋 (cold_ocean)
      case 45: return const Color(0xFF023E8A); // 冷水深海 (deep_cold_ocean)
      case 46: return const Color(0xFF90E0EF); // 冻洋 (frozen_ocean)
      case 47: return const Color(0xFF64B5F6); // 冰冻深海 (deep_frozen_ocean)
      case 48: return const Color(0xFF15803D); // 竹林 (bamboo_jungle)
      case 49: return const Color(0xFF166534); // 竹林丘陵 (bamboo_jungle_hills)

      // 129 ~ 167 (变种群系)
      case 129: return const Color(0xFFFACC15); // 向日葵平原 (sunflower_plains)
      case 130: return const Color(0xFFEAB308); // 沙漠湖泊 (desert_mutated)
      case 131: return const Color(0xFF386641); // 风袭沙砾丘陵 (extreme_hills_mutated)
      case 132: return const Color(0xFFF472B6); // 繁花森林 (flower_forest)
      case 133: return const Color(0xFF047857); // 针叶林山地 (taiga_mutated)
      case 134: return const Color(0xFF365314); // 沼泽丘陵 (swampland_mutated)
      case 140: return const Color(0xFFE0E7FF); // 冰刺之地 (ice_plains_spikes)
      case 149: return const Color(0xFF4ADE80); // 丛林变种 (jungle_mutated)
      case 151: return const Color(0xFF16A34A); // 丛林边缘变种 (jungle_edge_mutated)
      case 155: return const Color(0xFF3F6212); // 原始桦木森林 (birch_forest_mutated)
      case 156: return const Color(0xFF365314); // 高大桦木丘陵 (birch_forest_hills_mutated)
      case 157: return const Color(0xFF052E16); // 黑森林丘陵 (roofed_forest_mutated)
      case 158: return const Color(0xFF86EFAC); // 积雪的针叶林山地 (cold_taiga_mutated)
      case 160: return const Color(0xFF064E3B); // 原始云杉针叶林 (redwood_taiga_mutated)
      case 161: return const Color(0xFF022C22); // 巨型云杉针叶林丘陵 (redwood_taiga_hills_mutated)
      case 162: return const Color(0xFF386641); // 沙砾山地+ (extreme_hills_plus_trees_mutated)
      case 163: return const Color(0xFF92400E); // 风袭热带草原 (savanna_mutated)
      case 164: return const Color(0xFF78350F); // 破碎的热带高原 (savanna_plateau_mutated)
      case 165: return const Color(0xFF7C2D12); // 风蚀恶地 (mesa_bryce)
      case 166: return const Color(0xFF9A3412); // 繁茂的恶地高原变种 (mesa_plateau_stone_mutated)
      case 167: return const Color(0xFF7C2D12); // 恶地高原变种 (mesa_plateau_mutated)

      // 178 ~ 181 (下界 1.16+ 官方 ID)
      case 178: return const Color(0xFF451A03); // 灵魂沙峡谷 (soulsand_valley)
      case 179: return const Color(0xFF991B1B); // 绯红森林 (crimson_forest)
      case 180: return const Color(0xFF0F766E); // 诡异森林 (warped_forest)
      case 181: return const Color(0xFF334155); // 玄武岩三角洲 (basalt_deltas)

      // 182 ~ 194 (山地、洞穴、新群系 1.18 - 1.21+)
      case 182: return const Color(0xFFE2E8F0); // 尖峭山峰 (jagged_peaks)
      case 183: return const Color(0xFFF8FAFC); // 冰封山峰 (frozen_peaks)
      case 184: return const Color(0xFFCBD5E1); // 积雪山坡 (snowy_slopes)
      case 185: return const Color(0xFFCBD5E1); // 雪林 (grove)
      case 186: return const Color(0xFF84CC16); // 草甸 (meadow)
      case 187: return const Color(0xFF10B981); // 繁茂洞穴 (lush_caves)
      case 188: return const Color(0xFF78716C); // 溶洞 (dripstone_caves)
      case 189: return const Color(0xFF64748B); // 裸岩山峰 (stony_peaks)
      case 190: return const Color(0xFF0F172A); // 深暗之域 (deep_dark)
      case 191: return const Color(0xFF4D7C0F); // 红树林沼泽 (mangrove_swamp)
      case 192: return const Color(0xFFF43F5E); // 樱花树林 (cherry_grove)
      case 193: return const Color(0xFF8B8C89); // 苍白之园 (pale_garden)
      case 194: return const Color(0xFFEAB308); // 硫黄洞穴 (sulfur_caves)

      default:
        final hue = (biomeId * 137.5) % 360;
        return HSVColor.fromAHSV(1.0, hue, 0.65, 0.75).toColor();
    }
  }
}
