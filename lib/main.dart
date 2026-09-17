import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/bloom_api.dart';
import 'screens/auth_gate.dart';
import 'theme/bloom_theme.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // アプリは縦画面固定。横に倒したときの撮影画面への移動は
  // 画面の回転ではなく TiltWatcher（加速度センサー）で扱う。
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // 黒背景に合わせてステータスバーとナビゲーションバーのアイコンを白にする。
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: BloomColors.surface,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const BloomApp());
}

class BloomApp extends StatelessWidget {
  const BloomApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = buildBloomTheme();
    return MaterialApp(
      title: 'Bloom',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      home: AuthGate(api: BloomApi(baseUrl: BloomApi.defaultBaseUrl)),
    );
  }
}
