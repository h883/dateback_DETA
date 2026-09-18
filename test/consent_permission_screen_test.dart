import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sns_novahack/device/app_permissions.dart';
import 'package:sns_novahack/screens/consent_permission_screen.dart';
import 'package:sns_novahack/theme/bloom_theme.dart';

Future<PermissionReadout> _neverGranted(AppPermissionKind _) async =>
    (granted: false, permanentlyDenied: false);

Widget _app({
  required VoidCallback onNext,
  required Future<PermissionReadout> Function(AppPermissionKind) read,
  Future<PermissionReadout> Function(AppPermissionKind)? request,
}) =>
    MaterialApp(
      theme: buildBloomTheme(),
      home: ConsentPermissionScreen(
        onNext: onNext,
        debugRead: read,
        debugRequest: request ?? _neverGranted,
      ),
    );

void main() {
  testWidgets('最初は Camera だけが current step として表示される', (tester) async {
    await tester.pumpWidget(_app(onNext: () {}, read: _neverGranted));
    await tester.pumpAndSettle();

    expect(find.text('カメラ'), findsOneWidget);
    expect(find.text('カメラを許可する'), findsOneWidget);

    // 未来の step はまだ画面に出ない。
    expect(find.text('Bluetooth'), findsNothing);
    expect(find.text('位置情報'), findsNothing);
    expect(find.text('通知'), findsNothing);

    // まとめて連続 request する旧 UI は残っていない。
    expect(find.text('権限をまとめて許可する'), findsNothing);
  });

  testWidgets('Camera を許可(granted)すると Bluetooth step へ進む', (tester) async {
    final granted = <AppPermissionKind>{};
    await tester.pumpWidget(_app(
      onNext: () {},
      read: (kind) async =>
          (granted: granted.contains(kind), permanentlyDenied: false),
      request: (kind) async {
        granted.add(kind);
        return (granted: true, permanentlyDenied: false);
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('カメラを許可する'));
    await tester.pumpAndSettle();

    // Camera は完了済みとして上に残り、green lamp(許可済み)になる。
    expect(find.text('カメラ'), findsOneWidget);
    expect(find.text('許可済み'), findsOneWidget);

    // 次は Bluetooth が current。Location/Notification はまだ出ない。
    expect(find.text('Bluetoothを許可する'), findsOneWidget);
    expect(find.text('位置情報'), findsNothing);
    expect(find.text('通知'), findsNothing);
  });

  testWidgets('Camera を拒否(denied)しても Bluetooth step へ進む', (tester) async {
    await tester.pumpWidget(_app(
      onNext: () {},
      read: _neverGranted,
      request: _neverGranted,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('カメラを許可する'));
    await tester.pumpAndSettle();

    // flow は止まらず、Camera は warning lamp(許可されず)で完了扱いになる。
    expect(find.text('許可されず'), findsOneWidget);
    expect(find.text('Bluetoothを許可する'), findsOneWidget);
  });

  testWidgets('既に Camera/Bluetooth が Granted なら最初の未許可 step(Location)へ飛ぶ',
      (tester) async {
    const alreadyGranted = {
      AppPermissionKind.camera,
      AppPermissionKind.bluetooth,
    };
    await tester.pumpWidget(_app(
      onNext: () {},
      read: (kind) async =>
          (granted: alreadyGranted.contains(kind), permanentlyDenied: false),
    ));
    await tester.pumpAndSettle();

    expect(find.text('位置情報を許可する'), findsOneWidget);
    // Camera/Bluetooth は完了済みとして上に表示されている。
    expect(find.text('カメラ'), findsOneWidget);
    expect(find.text('Bluetooth'), findsOneWidget);
    // Notification はまだ未来の step なので出ない。
    expect(find.text('通知'), findsNothing);
  });

  testWidgets('全 permission が既に Granted なら「次へ」だけになる', (tester) async {
    await tester.pumpWidget(_app(
      onNext: () {},
      read: (_) async => (granted: true, permanentlyDenied: false),
    ));
    await tester.pumpAndSettle();

    expect(find.text('次へ'), findsOneWidget);
    expect(find.text('カメラを許可する'), findsNothing);
    expect(find.text('Bluetoothを許可する'), findsNothing);
    expect(find.text('位置情報を許可する'), findsNothing);
    expect(find.text('通知を許可する'), findsNothing);
  });

  testWidgets('「次へ」で onNext が呼ばれる', (tester) async {
    var nextCalled = false;
    await tester.pumpWidget(_app(
      onNext: () => nextCalled = true,
      read: (_) async => (granted: true, permanentlyDenied: false),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('次へ'));
    await tester.pump();

    expect(nextCalled, isTrue);
  });
}
