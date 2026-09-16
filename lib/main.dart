import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/onboarding_screen.dart';
import 'theme/bloom_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: const OnboardingScreen(),
    );
  }
}
