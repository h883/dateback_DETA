import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sns_novahack/screens/consent_permission_screen.dart';
import 'package:sns_novahack/theme/bloom_theme.dart';

Widget _app(VoidCallback onNext) => MaterialApp(
      theme: buildBloomTheme(),
      home: ConsentPermissionScreen(onNext: onNext),
    );

void main() {
  testWidgets('4つの permission 行を表示し、個別の「許可」ボタンは無い', (tester) async {
    await tester.pumpWidget(_app(() {}));
    await tester.pump();

    expect(find.text('カメラ'), findsOneWidget);
    expect(find.text('Bluetooth'), findsOneWidget);
    expect(find.text('位置情報'), findsOneWidget);
    expect(find.text('通知'), findsOneWidget);

    // 各行に個別の「許可」ボタンを並べるUIは削除されている。
    expect(find.text('許可'), findsNothing);

    // まとめて許可する主要アクションは1つだけ。
    expect(find.text('権限をまとめて許可する'), findsOneWidget);
  });

  testWidgets('permission が未取得(プラグイン未接続)でも lamp は gray として描画される', (tester) async {
    await tester.pumpWidget(_app(() {}));
    await tester.pump();

    // テスト環境には OS permission プラグインの実装が無いため、
    // AppPermissions.read は例外を握りつぶして「未許可」を返す。
    // その結果、初期状態のラベルは「未許可」(gray)になるはず。
    expect(find.text('未許可'), findsNWidgets(4));
  });

  testWidgets('optional permission を1つも許可していなくても「次へ」で進める', (tester) async {
    var nextCalled = false;
    await tester.pumpWidget(_app(() => nextCalled = true));
    await tester.pump();

    await tester.tap(find.text('次へ'));
    await tester.pump();

    expect(nextCalled, isTrue);
  });
}
