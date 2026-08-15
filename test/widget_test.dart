import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_app/data/data_manager.dart';
import 'package:flutter_app/main.dart';
import 'package:flutter_app/models/app_settings.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppSettings()),
          ChangeNotifierProvider(create: (_) => DataManager()),
        ],
        child: const MinecraftEditorApp(),
      ),
    );
    expect(find.byType(MinecraftEditorApp), findsOneWidget);
  });
}
