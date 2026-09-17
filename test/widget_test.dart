import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sns_novahack/screens/tutorial_screen.dart';
import 'package:sns_novahack/theme/bloom_theme.dart';

/// AuthGate 経由の起動は Firebase の初期化を前提にしているので、
/// ここではチュートリアル画面だけを直接立ち上げて操作を確かめる。
Widget _app({bool replay = false, VoidCallback? onFinished}) => MaterialApp(
      theme: buildBloomTheme(),
      home: TutorialScreen(replay: replay, onFinished: onFinished ?? () {}),
    );

/// ページ内のデモは常時アニメーションしているため pumpAndSettle は使えない。
/// ページ遷移が終わるだけの時間を明示的に進める。
Future<void> _settlePage(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('チュートリアルは3ページを順に進む', (WidgetTester tester) async {
    await tester.pumpWidget(_app());
    await _settlePage(tester);

    // Page 1
    expect(find.text('友達と会って、写真を交換しよう'), findsOneWidget);
    expect(find.text('次へ'), findsOneWidget);

    // Page 2
    await tester.tap(find.text('次へ'));
    await _settlePage(tester);
    expect(find.text('上下にフリックして、友達の投稿を見よう'), findsOneWidget);

    // Page 3
    await tester.tap(find.text('次へ'));
    await _settlePage(tester);
    expect(find.text('右フリックか横向きで、すぐ撮ろう'), findsOneWidget);
    expect(find.text('はじめる'), findsOneWidget);
  });

  testWidgets('スキップで即座に完了コールバックが呼ばれる', (WidgetTester tester) async {
    var finished = false;
    await tester.pumpWidget(_app(onFinished: () => finished = true));
    await _settlePage(tester);

    await tester.tap(find.text('スキップ'));
    await _settlePage(tester);

    expect(finished, isTrue);
  });

  testWidgets('replay:true では最終ボタンが「閉じる」になる', (WidgetTester tester) async {
    await tester.pumpWidget(_app(replay: true));
    await _settlePage(tester);

    // 再生時はスキップではなく「閉じる」。
    expect(find.text('スキップ'), findsNothing);
    expect(find.text('閉じる'), findsOneWidget);

    await tester.tap(find.text('次へ'));
    await _settlePage(tester);
    await tester.tap(find.text('次へ'));
    await _settlePage(tester);

    // 最終ページでも「はじめる」ではなく「閉じる」のまま。
    expect(find.text('はじめる'), findsNothing);
    expect(find.text('閉じる'), findsWidgets);
  });
}
