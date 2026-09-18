import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sns_novahack/device/app_permissions.dart';
import 'package:sns_novahack/screens/consent_permission_screen.dart';
import 'package:sns_novahack/theme/bloom_theme.dart';

/// 各 kind の現況(granted/permanentlyDenied)を保持しつつ、request() の
/// 呼び出しを記録する。request() はすぐには解決させず、[resolve] を呼ぶ
/// まで pending のままにする(=OS 確認ダイアログが出ている間、という想定)。
/// これにより「自動 request が1回だけ発火するか」「次の step の自動
/// request が意図せず連鎖しないか」を1 step ずつ検証できる。
class _FakePermissions {
  _FakePermissions({Set<AppPermissionKind> granted = const {}}) {
    for (final kind in granted) {
      _status[kind] = (granted: true, permanentlyDenied: false);
    }
  }

  final Map<AppPermissionKind, PermissionReadout> _status = {
    for (final kind in AppPermissionKind.values)
      kind: (granted: false, permanentlyDenied: false),
  };

  final List<AppPermissionKind> requestCalls = [];
  final Map<AppPermissionKind, Completer<PermissionReadout>> _pending = {};

  Future<PermissionReadout> read(AppPermissionKind kind) async => _status[kind]!;

  Future<PermissionReadout> request(AppPermissionKind kind) {
    requestCalls.add(kind);
    final completer = Completer<PermissionReadout>();
    _pending[kind] = completer;
    return completer.future;
  }

  void resolve(
    AppPermissionKind kind, {
    required bool granted,
    bool permanentlyDenied = false,
  }) {
    final readout = (granted: granted, permanentlyDenied: permanentlyDenied);
    _status[kind] = readout;
    _pending.remove(kind)!.complete(readout);
  }
}

Widget _app(_FakePermissions fake, {VoidCallback? onNext}) => MaterialApp(
      theme: buildBloomTheme(),
      home: ConsentPermissionScreen(
        onNext: onNext ?? () {},
        debugRead: fake.read,
        debugRequest: fake.request,
        autoRequestDelay: Duration.zero,
      ),
    );

/// 現在 step の説明を「request 中」の見た目まで進める。current step の
/// 自動 request が pending の間は [CircularProgressIndicator] が回り
/// 続ける(=常にフレームを要求し続ける)ため、`pumpAndSettle()` は使えない
/// (settle しないままタイムアウトする)。代わりに、初回描画 →
/// postFrameCallback → 遅延ゼロの自動 request 発火、を確実に踏むだけの
/// 決まった回数だけ pump する。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
}

void main() {
  testWidgets(
      'Camera step 表示後、CTA なしで Camera の自動 request が1回だけ scheduleされる',
      (tester) async {
    final fake = _FakePermissions();
    await tester.pumpWidget(_app(fake));
    await _settle(tester);

    // 現在 step の説明(icon/title/理由)が見えている。
    expect(find.text('カメラ'), findsOneWidget);
    expect(find.text('写真・8mm動画を撮影します'), findsOneWidget);
    expect(find.text('1 / 4'), findsOneWidget);

    // ユーザーが押す CTA ボタンは存在しない。
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('カメラを許可する'), findsNothing);

    // 自動で OS 確認が1回だけ発火している。
    expect(fake.requestCalls, [AppPermissionKind.camera]);
    expect(find.text('OSの確認を表示しています…'), findsOneWidget);

    // 何度 pump してもダイアログ結果が返るまでは再発火しない。
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(fake.requestCalls, [AppPermissionKind.camera]);
  });

  testWidgets('Camera の結果(granted)後、自動的に Bluetooth step へ進む', (tester) async {
    final fake = _FakePermissions();
    await tester.pumpWidget(_app(fake));
    await _settle(tester);
    expect(fake.requestCalls, [AppPermissionKind.camera]);

    fake.resolve(AppPermissionKind.camera, granted: true);
    await _settle(tester);

    // Camera は完了済みとして上に残り green lamp になる。
    expect(find.text('カメラ'), findsOneWidget);
    expect(find.text('許可済み'), findsOneWidget);

    // Bluetooth が新たな current step として自動的に request されている。
    expect(fake.requestCalls, [AppPermissionKind.camera, AppPermissionKind.bluetooth]);
    expect(find.text('Bluetooth'), findsOneWidget);
    expect(find.text('位置情報'), findsNothing);
    expect(find.text('通知'), findsNothing);
  });

  testWidgets('Denied でも自動的に次 step へ進み、同じダイアログは再表示しない', (tester) async {
    final fake = _FakePermissions();
    await tester.pumpWidget(_app(fake));
    await _settle(tester);

    fake.resolve(AppPermissionKind.camera, granted: false);
    await _settle(tester);

    // flow は止まらず、Camera は warning lamp(許可されず)で完了扱いになる。
    expect(find.text('許可されず'), findsOneWidget);
    // Bluetooth へ進み、そちらの自動 request が1回だけ発火している。
    expect(fake.requestCalls, [AppPermissionKind.camera, AppPermissionKind.bluetooth]);
  });

  testWidgets('resume しても Denied な permission を再 request しない', (tester) async {
    final fake = _FakePermissions();
    await tester.pumpWidget(_app(fake));
    await _settle(tester);

    fake.resolve(AppPermissionKind.camera, granted: false);
    await _settle(tester);
    expect(fake.requestCalls, [AppPermissionKind.camera, AppPermissionKind.bluetooth]);

    // Settings アプリから戻ってきた場合などを模した resume イベント。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);

    // status の再読込だけが起き、Camera(denied 済み)は再 request されない。
    expect(fake.requestCalls, [AppPermissionKind.camera, AppPermissionKind.bluetooth]);
    expect(find.text('許可されず'), findsOneWidget);
  });

  testWidgets(
      'Camera/Bluetooth が既に Granted なら Location step から始まり、明示的に request される',
      (tester) async {
    final fake = _FakePermissions(
      granted: {AppPermissionKind.camera, AppPermissionKind.bluetooth},
    );
    await tester.pumpWidget(_app(fake));
    await _settle(tester);

    expect(find.text('位置情報'), findsOneWidget);
    expect(find.text('カメラ'), findsOneWidget);
    expect(find.text('Bluetooth'), findsOneWidget);
    expect(find.text('通知'), findsNothing);

    // Bluetooth の副作用で granted になっていない以上、Location は
    // 「推測でスキップ」されず、必ず明示的に request される。
    expect(fake.requestCalls, [AppPermissionKind.location]);
  });

  testWidgets(
      'Bluetooth の副作用で Location が既に Granted なら OS dialog なしで自動完了する',
      (tester) async {
    final fake = _FakePermissions(
      granted: {
        AppPermissionKind.camera,
        AppPermissionKind.bluetooth,
        AppPermissionKind.location,
      },
    );
    await tester.pumpWidget(_app(fake));
    await _settle(tester);

    // Location は一度も request されずに green として完了している。
    expect(fake.requestCalls, isNot(contains(AppPermissionKind.location)));
    expect(find.text('位置情報'), findsOneWidget);
    expect(find.text('通知'), findsOneWidget);
    expect(fake.requestCalls, [AppPermissionKind.notification]);
  });

  testWidgets('全 permission が既に Granted なら「次へ」だけになり、request は一切呼ばれない',
      (tester) async {
    final fake = _FakePermissions(granted: AppPermissionKind.values.toSet());
    var nextCalled = false;
    await tester.pumpWidget(_app(fake, onNext: () => nextCalled = true));
    await _settle(tester);

    expect(find.text('次へ'), findsOneWidget);
    expect(fake.requestCalls, isEmpty);
    expect(find.text('OSの確認を表示しています…'), findsNothing);
    expect(find.text('まもなくOSの確認が表示されます'), findsNothing);

    await tester.tap(find.text('次へ'));
    await tester.pump();
    expect(nextCalled, isTrue);
  });

  testWidgets('全 step 完了前は「次へ」が表示されない', (tester) async {
    final fake = _FakePermissions();
    await tester.pumpWidget(_app(fake));
    await _settle(tester);

    expect(find.text('次へ'), findsNothing);
  });
}
