import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sns_novahack/screens/settings_drawer.dart';
import 'package:sns_novahack/settings/settings_store.dart';
import 'package:sns_novahack/theme/theme_controller.dart';

import 'support/test_app.dart';

/// 設定ドロワー(ハンバーガー導線)側のログアウト経路を確認する。
/// Own Profile の本文からログアウトを取り除いても、設定側の導線は
/// 残っていることを保証する回帰テスト(タスク仕様 3)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Settingsドロワーにはログアウト行があり、確認して押すとonSignOutが呼ばれる',
      (tester) async {
    final themeController = await ThemeController.load();
    final settingsStore = await SettingsStore.load();
    var signedOut = false;

    await tester.pumpWidget(
      wrapWithApp(
        Scaffold(
          endDrawer: SettingsDrawer(
            themeController: themeController,
            settingsStore: settingsStore,
            onSignOut: () => signedOut = true,
            onToast: (_) {},
          ),
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Scaffold.of(context).openEndDrawer(),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final logoutRow = find.text('ログアウト');
    expect(logoutRow, findsOneWidget);

    await tester.tap(logoutRow);
    await tester.pumpAndSettle();

    // 確認ダイアログが出る。
    expect(find.text('ログアウトしますか？'), findsOneWidget);
    await tester.tap(find.text('ログアウト').last);
    await tester.pumpAndSettle();

    expect(signedOut, isTrue);
  });
}
