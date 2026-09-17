import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/bloom_api.dart';
import 'screens/auth_gate.dart';
import 'settings/settings_store.dart';
import 'theme/bloom_theme.dart';
import 'theme/theme_controller.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // アプリは縦画面固定。横に倒したときの撮影画面への移動は
  // 画面の回転ではなく TiltWatcher（加速度センサー）で扱う。
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // システムバーのアイコン色は実際に適用されるテーマの明暗に追従させたいので、
  // ここでは固定せず BloomApp 側で Theme.of(context).brightness を見て
  // AnnotatedRegion で都度反映する（OS のライト/ダーク切替にも追従する）。

  final themeController = await ThemeController.load();
  final settingsStore = await SettingsStore.load();
  runApp(
    BloomApp(themeController: themeController, settingsStore: settingsStore),
  );
}

class BloomApp extends StatelessWidget {
  const BloomApp({
    super.key,
    required this.themeController,
    required this.settingsStore,
  });

  final ThemeController themeController;
  final SettingsStore settingsStore;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'dateback',
          debugShowCheckedModeBanner: false,
          theme: buildBloomTheme(brightness: Brightness.light),
          darkTheme: buildBloomTheme(),
          themeMode: themeController.mode,
          builder: (context, child) {
            final brightness = Theme.of(context).brightness;
            final isDark = brightness == Brightness.dark;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness:
                    isDark ? Brightness.light : Brightness.dark,
                statusBarBrightness: brightness,
                systemNavigationBarColor:
                    Theme.of(context).scaffoldBackgroundColor,
                systemNavigationBarIconBrightness:
                    isDark ? Brightness.light : Brightness.dark,
              ),
              child: child!,
            );
          },
          home: AuthGate(
            api: BloomApi(baseUrl: BloomApi.defaultBaseUrl),
            themeController: themeController,
            settingsStore: settingsStore,
          ),
        );
      },
    );
  }
}
