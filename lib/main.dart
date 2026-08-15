import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'data/data_manager.dart';
import 'models/app_settings.dart';
import 'screens/world_list_screen.dart';
import 'services/storage_service.dart';
import 'utils/game_data_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 加载游戏基础数据 (生物群系、材质颜色)
  GameDataService().loadAll();

  // 2. 加载用户全局设置与持久化
  await StorageService().loadSettings();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: AppSettings()),
        ChangeNotifierProvider(create: (_) => DataManager()),
      ],
      child: const MinecraftEditorApp(),
    ),
  );
}

class MinecraftEditorApp extends StatelessWidget {
  const MinecraftEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();

    return MaterialApp(
      title: 'Minecraft BE 存档编辑器',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode.mode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF2E7D32),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 1,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF4CAF50),
        scaffoldBackgroundColor: const Color(0xFF14161D),
        cardTheme: const CardThemeData(
          color: Color(0xFF1E222B),
          elevation: 2,
        ),
      ),
      home: const WorldListScreen(),
    );
  }
}
