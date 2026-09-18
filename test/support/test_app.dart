import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sns_novahack/theme/bloom_theme.dart';

/// 画面 widget test 用の共通ラッパー。
///
/// 固定の dark テーマ前提にしないため、[brightness] を指定できるように
/// しておく(デフォルトは system 追従ではなく明示的に dark にして、
/// 既存のテーマ実装(buildBloomTheme)をそのまま使う)。
Widget wrapWithApp(
  Widget child, {
  Brightness brightness = Brightness.dark,
}) {
  return MaterialApp(
    theme: buildBloomTheme(brightness: brightness),
    home: child,
  );
}

/// デフォルトの test surface(800x600 論理px)は、実機の縦長画面より
/// 縮んでいるため、画面いっぱいに縦に積む画面(Home の投稿カード、
/// Post Viewer など)で本来出ない RenderFlex overflow を誤検出することが
/// ある。対象の screen/widget 実装は変更せず、テスト側のビューポートを
/// スマホ相当の縦長サイズにして本来の見た目で検証する。
void useTallTestSurface() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final view = binding.platformDispatcher.views.first;
  view.physicalSize = const Size(1080, 2280);
  view.devicePixelRatio = 3.0;
  addTearDown(view.resetPhysicalSize);
  addTearDown(view.resetDevicePixelRatio);
}
