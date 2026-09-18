import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// 初回セットアップ画面(Consent/Permission)で扱う4種類の OS permission。
enum AppPermissionKind { camera, bluetooth, location, notification }

/// Permission 画面の各行に出す「lamp」の状態。
enum LampState {
  /// 未許可 / 未要求。
  gray,

  /// OS 側で実際に Granted になっている。
  green,

  /// Denied (要求済みで拒否された、または恒久的に拒否されている)。
  /// 控えめな warning 色として扱う。
  warn,
}

/// [status]/[permanentlyDenied]/[requestedOnce] から lamp の色を決める
/// 純粋関数(unit test しやすいようロジックだけを切り出してある)。
///
/// - Granted → green。
/// - 恒久的に拒否、またはこの画面から一度でも要求して denied だった → warn。
/// - まだ一度も要求していない denied(初期状態) → gray
///   (「未許可 / 未要求」であって、拒否されたわけではないため)。
///
/// UI 上のボタンを押した事実そのものではなく、[granted] という実際の OS
/// permission status を source of truth にする。
LampState lampStateFor({
  required bool granted,
  required bool permanentlyDenied,
  required bool requestedOnce,
}) {
  if (granted) return LampState.green;
  if (permanentlyDenied || requestedOnce) return LampState.warn;
  return LampState.gray;
}

/// ある permission の現況。[granted]/[permanentlyDenied] は
/// [lampStateFor] へそのまま渡せる形にしてある。
typedef PermissionReadout = ({bool granted, bool permanentlyDenied});

/// OS permission の読み取り・要求をまとめる窓口。
///
/// - [isGranted]/[read] は要求を一切行わない「現況の読み取り専用」。
///   Consent/Permission 画面より後で permission の有無を見る側
///   ([BleProximityService] の起動判定、Camera の lazy-init 判定など)は
///   必ずこちらだけを使い、`.request()` は絶対に呼ばない
///   (=後から勝手に OS permission dialog を出さない)。
/// - [request] は初回 Consent/Permission 画面だけが呼ぶ。
abstract final class AppPermissions {
  static Future<bool> isGranted(AppPermissionKind kind) async =>
      (await read(kind)).granted;

  static Future<PermissionReadout> read(AppPermissionKind kind) async {
    try {
      switch (kind) {
        case AppPermissionKind.camera:
          return _readout(await Permission.camera.status);
        case AppPermissionKind.bluetooth:
          return await _readBluetooth();
        case AppPermissionKind.location:
          return _readout(await Permission.locationWhenInUse.status);
        case AppPermissionKind.notification:
          // Android 13 (API 33) 未満は runtime permission が存在せず、
          // permission_handler はここで自動的に granted を返す
          // (=「不要な OS では Granted/Not required 相当」を満たす)。
          return _readout(await Permission.notification.status);
      }
    } catch (_) {
      // この端末・この OS では問い合わせ自体に失敗した。要求はせず
      // 「未許可」として扱う。
      return (granted: false, permanentlyDenied: false);
    }
  }

  /// Consent/Permission 画面からのみ呼ぶこと。実際に OS の許可ダイアログを
  /// 表示する可能性がある。
  static Future<PermissionReadout> request(AppPermissionKind kind) async {
    try {
      switch (kind) {
        case AppPermissionKind.camera:
          return _readout(await Permission.camera.request());
        case AppPermissionKind.bluetooth:
          return await _requestBluetooth();
        case AppPermissionKind.location:
          return _readout(await Permission.locationWhenInUse.request());
        case AppPermissionKind.notification:
          return _readout(await Permission.notification.request());
      }
    } catch (_) {
      return (granted: false, permanentlyDenied: false);
    }
  }

  /// 仕様書 5.5: Android 12+ はスキャン/アドバタイズが個別権限、12未満は
  /// 位置情報が要る。ここでは scan/advertise が揃っているかどうかを
  /// 実質的なゲートとする([BleProximityService] の判定と揃えている)。
  /// 12未満の端末ではこの2つは OS 側で自動的に granted 扱いになる。
  ///
  /// iOS には `bluetoothScan`/`bluetoothAdvertise`/`bluetoothConnect` が
  /// 実装されておらず、常に非 granted を返してしまう。iOS では
  /// CoreBluetooth 用の `Permission.bluetooth` のみを見る。
  static Future<PermissionReadout> _readBluetooth() async {
    if (Platform.isIOS) {
      return _readout(await Permission.bluetooth.status);
    }
    final scan = await Permission.bluetoothScan.status;
    final advertise = await Permission.bluetoothAdvertise.status;
    return (
      granted: scan.isGranted && advertise.isGranted,
      permanentlyDenied: scan.isPermanentlyDenied || advertise.isPermanentlyDenied,
    );
  }

  static Future<PermissionReadout> _requestBluetooth() async {
    if (Platform.isIOS) {
      return _readout(await Permission.bluetooth.request());
    }
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      // Android 12 未満はこれが実質的な Bluetooth 検知の可否を握る。
      Permission.locationWhenInUse,
    ].request();
    final scan = statuses[Permission.bluetoothScan];
    final advertise = statuses[Permission.bluetoothAdvertise];
    return (
      granted: scan?.isGranted == true && advertise?.isGranted == true,
      permanentlyDenied:
          scan?.isPermanentlyDenied == true || advertise?.isPermanentlyDenied == true,
    );
  }

  static PermissionReadout _readout(PermissionStatus status) => (
        granted: status.isGranted,
        permanentlyDenied: status.isPermanentlyDenied,
      );

  /// Denied 済み permission の「設定を開く」導線用。OS の設定アプリを開く
  /// だけで、permission dialog を自動で再 request することはしない。
  static Future<void> openSettings() async {
    try {
      await openAppSettings();
    } catch (_) {
      // 設定アプリを開けない端末では何もしない。
    }
  }
}
