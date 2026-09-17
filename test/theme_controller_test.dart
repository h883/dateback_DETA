import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sns_novahack/theme/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ThemeController', () {
    test('保存前は ThemeMode.system がデフォルト', () async {
      final controller = await ThemeController.load();
      expect(controller.mode, ThemeMode.system);
    });

    test('setMode で値が変わり、再読込後も保持される', () async {
      final controller = await ThemeController.load();
      await controller.setMode(ThemeMode.dark);
      expect(controller.mode, ThemeMode.dark);

      final reloaded = await ThemeController.load();
      expect(reloaded.mode, ThemeMode.dark);
    });

    test('light も保持される(system 以外の全モードを確認)', () async {
      final controller = await ThemeController.load();
      await controller.setMode(ThemeMode.light);

      final reloaded = await ThemeController.load();
      expect(reloaded.mode, ThemeMode.light);
    });

    test('同じ値を設定してもリスナーを無駄に呼ばない', () async {
      final controller = await ThemeController.load();
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      await controller.setMode(ThemeMode.system); // すでに system
      expect(notifyCount, 0);

      await controller.setMode(ThemeMode.dark);
      expect(notifyCount, 1);
    });
  });
}
