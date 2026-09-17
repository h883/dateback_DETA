import 'package:shared_preferences/shared_preferences.dart';

/// 初回チュートリアルを完了済みかどうかの永続化。
///
/// Firebase Auth の uid ごとに保存する(同じ端末を複数の Google アカウントで
/// 使う場合、別アカウントでログインしたときに Consent/Tutorial を
/// 飛ばしてしまわないように)。次回同じアカウントで起動したときだけ
/// チュートリアルを飛ばすためのヘルパー。
abstract final class TutorialCompletion {
  static String _key(String uid) => 'tutorial_completed_$uid';

  static Future<bool> isCompleted(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(uid)) ?? false;
  }

  static Future<void> markCompleted(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(uid), true);
  }
}
