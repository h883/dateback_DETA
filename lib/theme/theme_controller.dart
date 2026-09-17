import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 表示テーマ設定(システム/ライト/ダーク)を保持し、`SharedPreferences` に
/// 永続化する。
///
/// 実際に選ばせる UI(設定ドロワーのインライン展開ホイール)は別フェーズで
/// 実装する。ここでは値の読み書きと `ChangeNotifier` としての通知だけを担う。
/// デフォルトは [ThemeMode.system](system-follow)。
class ThemeController extends ChangeNotifier {
  ThemeController._(this._mode);

  static const _prefsKey = 'theme_mode';

  ThemeMode _mode;

  ThemeMode get mode => _mode;

  /// 保存済みの値を読み込んで初期化する。値が無ければ [ThemeMode.system]。
  static Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ThemeController._(_decode(prefs.getString(_prefsKey)));
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _encode(mode));
  }

  static String _encode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static ThemeMode _decode(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
