import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sns_novahack/screens/onboarding_screen.dart';
import 'package:sns_novahack/theme/bloom_theme.dart';

/// BloomApp 本体は Firebase の初期化を前提にしているので、
/// ここではチュートリアル画面だけを直接立ち上げて操作を確かめる。
Widget _app() => MaterialApp(
      theme: buildBloomTheme(),
      home: const OnboardingScreen(),
    );

/// STEP 2 のレーダーは常時アニメーションしているため pumpAndSettle は使えない。
/// ページ遷移が終わるだけの時間を明示的に進める。
Future<void> _settlePage(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('チュートリアルは3ステップを順に進む', (WidgetTester tester) async {
    await tester.pumpWidget(_app());

    // STEP 1
    expect(find.text('投稿しよう'), findsOneWidget);
    expect(find.text('次へ'), findsOneWidget);

    // STEP 2
    await tester.tap(find.text('次へ'));
    await _settlePage(tester);
    expect(find.text('友達と会おう'), findsOneWidget);

    // STEP 3
    await tester.tap(find.text('次へ'));
    await _settlePage(tester);
    expect(find.text('思い出がひらく'), findsOneWidget);
    expect(find.text('はじめる（ログインへ進む）'), findsOneWidget);
  });

  testWidgets('スキップで最終ステップまで飛べる', (WidgetTester tester) async {
    await tester.pumpWidget(_app());

    await tester.tap(find.text('スキップ'));
    await _settlePage(tester);

    expect(find.text('思い出がひらく'), findsOneWidget);
  });
}
