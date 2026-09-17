import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// アプリ設定ドロワー(Phase 9)のローカルトグル類をまとめる小さな store。
/// テーマ(system/light/dark)は既存の [ThemeController] をそのまま使う
/// ため、ここには含めない。
class SettingsStore extends ChangeNotifier {
  SettingsStore._(this._tiltToCameraEnabled, this._autoLocationEnabled);

  static const _tiltKey = 'settings_tilt_to_camera_enabled';
  static const _locationKey = 'settings_auto_location_enabled';

  bool _tiltToCameraEnabled;
  bool _autoLocationEnabled;

  /// 横向きでカメラを開く(Home 表示中の landscapeShutterRight 自動起動)。
  /// デフォルト ON。OFF でも右フリック・ボトムナビからの Camera 遷移は
  /// 変わらず使える([MainShell] 側で自動起動の分岐だけをこの値で見る)。
  bool get tiltToCameraEnabled => _tiltToCameraEnabled;

  /// 撮影地を自動で追加。B2(未実装)で実際の位置情報取得と組み合わせる
  /// 想定の設定値。今回は永続化して後から参照できる基盤だけを用意する。
  bool get autoLocationEnabled => _autoLocationEnabled;

  static Future<SettingsStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsStore._(
      prefs.getBool(_tiltKey) ?? true,
      prefs.getBool(_locationKey) ?? true,
    );
  }

  Future<void> setTiltToCameraEnabled(bool value) async {
    if (_tiltToCameraEnabled == value) return;
    _tiltToCameraEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tiltKey, value);
  }

  Future<void> setAutoLocationEnabled(bool value) async {
    if (_autoLocationEnabled == value) return;
    _autoLocationEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_locationKey, value);
  }
}
