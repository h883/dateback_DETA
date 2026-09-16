import 'package:flutter_test/flutter_test.dart';

import 'package:sns_novahack/main.dart';

/// STEP 2 のレーダーは常時アニメーションしているため pumpAndSettle は使えない。
/// ページ遷移が終わるだけの時間を明示的に進める。
Future<void> _settlePage(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('チュートリアルは3ステップを順に進み、最後にログインへ遷移できる',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BloomApp());

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

    // ログイン画面へ
    await tester.tap(find.text('はじめる（ログインへ進む）'));
    await _settlePage(tester);
    expect(find.text('Googleアカウントで続ける'), findsOneWidget);
    expect(find.text('対面BLE暗号化セーフティ'), findsOneWidget);
  });

  testWidgets('スキップで最終ステップまで飛べる', (WidgetTester tester) async {
    await tester.pumpWidget(const BloomApp());

    await tester.tap(find.text('スキップ'));
    await _settlePage(tester);

    expect(find.text('思い出がひらく'), findsOneWidget);
  });
}
