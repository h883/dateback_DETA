import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sns_novahack/settings/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsStore', () {
    test('保存前は両方デフォルトで ON', () async {
      final store = await SettingsStore.load();
      expect(store.tiltToCameraEnabled, isTrue);
      expect(store.autoLocationEnabled, isTrue);
    });

    test('setTiltToCameraEnabled で値が変わり、再読込後も保持される', () async {
      final store = await SettingsStore.load();
      await store.setTiltToCameraEnabled(false);
      expect(store.tiltToCameraEnabled, isFalse);

      final reloaded = await SettingsStore.load();
      expect(reloaded.tiltToCameraEnabled, isFalse);
      // 他方の設定には影響しない。
      expect(reloaded.autoLocationEnabled, isTrue);
    });

    test('setAutoLocationEnabled で値が変わり、再読込後も保持される', () async {
      final store = await SettingsStore.load();
      await store.setAutoLocationEnabled(false);
      expect(store.autoLocationEnabled, isFalse);

      final reloaded = await SettingsStore.load();
      expect(reloaded.autoLocationEnabled, isFalse);
    });

    test('同じ値を設定してもリスナーを無駄に呼ばない', () async {
      final store = await SettingsStore.load();
      var notifyCount = 0;
      store.addListener(() => notifyCount++);

      await store.setTiltToCameraEnabled(true); // すでに true
      expect(notifyCount, 0);

      await store.setTiltToCameraEnabled(false);
      expect(notifyCount, 1);
    });
  });
}
