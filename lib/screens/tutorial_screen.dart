import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/bloom_theme.dart';
import '../widgets/wordmark.dart';

class _TutorialPage {
  const _TutorialPage({required this.title, required this.copy, required this.visual});

  final String title;
  final String copy;
  final Widget visual;
}

/// dateback v15 の3ステップチュートリアル。
///
/// 初回起動専用にベタ書きしない。[replay] が true なら「使い方」からの
/// 再生として最終ボタンが「閉じる」になる(Phase 9 の設定ドロワーからの
/// 呼び出しを想定。ドロワー自体は今回実装しない)。[onFinished] は
/// 「スキップ/最終ボタン」どちらでも呼ばれ、以降の遷移(初回なら永続化して
/// Home へ、再生ならただ閉じるだけ)は呼び出し側が決める。
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({
    super.key,
    required this.onFinished,
    this.replay = false,
  });

  final VoidCallback onFinished;
  final bool replay;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _pages = const [
    _TutorialPage(
      title: '友達と会って、写真を交換しよう',
      copy: '会った時間までの投稿が交換されます。',
      visual: _MeetDemo(),
    ),
    _TutorialPage(
      title: '上下にフリックして、友達の投稿を見よう',
      copy: '写真をタップすると、前の投稿に進めます。',
      visual: _BrowseDemo(),
    ),
    _TutorialPage(
      title: '右フリックか横向きで、すぐ撮ろう',
      copy: '右フリックか、スマホを左に倒してカメラを開こう。',
      visual: _CameraDemo(),
    ),
  ];

  int _step = 0;

  bool get _isLast => _step == _pages.length - 1;

  void _next() {
    if (_isLast) {
      widget.onFinished();
    } else {
      setState(() => _step++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final page = _pages[_step];

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Wordmark(),
                  TextButton(
                    onPressed: widget.onFinished,
                    child: Text(
                      widget.replay ? '閉じる' : 'スキップ',
                      style: BloomText.labelMd
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < _pages.length; i++) ...[
                          Container(
                            width: 20,
                            height: 3,
                            decoration: BoxDecoration(
                              color: i == _step
                                  ? colors.onSurface
                                  : colors.outlineVariant,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          if (i != _pages.length - 1) const SizedBox(width: 5),
                        ],
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      page.title,
                      style: BloomText.headlineMd.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      page.copy,
                      style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 220,
                      width: double.infinity,
                      child: Center(child: page.visual),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _next,
                  style: TextButton.styleFrom(
                    backgroundColor: colors.onSurface,
                    foregroundColor: colors.surface,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    _isLast ? (widget.replay ? '閉じる' : 'はじめる') : '次へ',
                    style: BloomText.labelSm.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Page 1

/// BLE 交換のアニメーション。文字は使わず、線でも結ばない。2つの円の輪郭が
/// 深く重なり、重なっている間は両方の輪郭が見え続ける。重なった状態を
/// 少し保持し、その間に淡い 3:2 写真カードが数枚出てくる。円が離れるまで
/// 写真カードは残る。
class _MeetDemo extends StatefulWidget {
  const _MeetDemo();

  @override
  State<_MeetDemo> createState() => _MeetDemoState();
}

class _MeetDemoState extends State<_MeetDemo> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 4800))
        ..repeat();

  static double _approach(double t) {
    if (t < 0.12) return 0;
    if (t < 0.28) return (t - 0.12) / 0.16;
    if (t < 0.70) return 1;
    if (t < 0.88) return 1 - (t - 0.70) / 0.18;
    return 0;
  }

  static double _photoOpacity(double t, double appearAt) {
    const disappearAt = 0.70;
    const fade = 0.09;
    if (t < appearAt) return 0;
    if (t < appearAt + fade) return (t - appearAt) / fade;
    if (t < disappearAt) return 1;
    if (t < disappearAt + fade) return 1 - (t - disappearAt) / fade;
    return 0;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final approach = _approach(t);
        final dx = 62 * approach;
        return SizedBox(
          width: 260,
          height: 190,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                bottom: 34,
                left: 32,
                child: _PhotoCard(
                  opacity: _photoOpacity(t, 0.27),
                  colors: const [Color(0xFFF5D7DF), Color(0xFFD9E8F5)],
                ),
              ),
              Positioned(
                bottom: 22,
                child: _PhotoCard(
                  opacity: _photoOpacity(t, 0.31),
                  colors: const [Color(0xFFD8EEDF), Color(0xFFF3E3BD)],
                ),
              ),
              Positioned(
                bottom: 34,
                right: 32,
                child: _PhotoCard(
                  opacity: _photoOpacity(t, 0.35),
                  colors: const [Color(0xFFDDD8F5), Color(0xFFF2D7C8)],
                ),
              ),
              Transform.translate(
                offset: Offset(-58 + dx, 0),
                child: const _OutlineCircle(),
              ),
              Transform.translate(
                offset: Offset(58 - dx, 0),
                child: const _OutlineCircle(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OutlineCircle extends StatelessWidget {
  const _OutlineCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.onSurface, width: 1.8),
      ),
    );
  }
}

/// 3:2 の淡い写真カード。ライトテーマでも暗くならない固定の淡色を使う
/// (サンプル写真という性質上、テーマに関わらず明るい色で見せる)。
class _PhotoCard extends StatelessWidget {
  const _PhotoCard({required this.opacity, required this.colors});

  final double opacity;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: 58,
        height: 39,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 4)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Page 2

/// Home のフィードを上下にフリックする様子。「スクロール」ではなくフリック
/// 動作として、Momo → Haru → Yuna(上フリック2回)→ Haru → Momo(下フリック
/// 2回)→ Momo を2回タップして日付表記を切り替える、を繰り返す。
class _BrowseDemo extends StatefulWidget {
  const _BrowseDemo();

  @override
  State<_BrowseDemo> createState() => _BrowseDemoState();
}

class _BrowseDemoState extends State<_BrowseDemo> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 11))
        ..repeat();

  static const _cardHeight = 108.0;
  static const _momoDates = ["'26 9 17", "'26 9 12", "'26 9 03"];

  static double _ramp(double t, double a, double b, double from, double to) {
    final f = ((t - a) / (b - a)).clamp(0.0, 1.0);
    return from + (to - from) * f;
  }

  static double _trackIndex(double t) {
    if (t < 0.07) return 0;
    if (t < 0.14) return _ramp(t, 0.07, 0.14, 0, 1);
    if (t < 0.20) return 1;
    if (t < 0.27) return _ramp(t, 0.20, 0.27, 1, 2);
    if (t < 0.34) return 2;
    if (t < 0.41) return _ramp(t, 0.34, 0.41, 2, 1);
    if (t < 0.48) return 1;
    if (t < 0.55) return _ramp(t, 0.48, 0.55, 1, 0);
    return 0;
  }

  static int _momoDateIndex(double t) {
    if (t < 0.69) return 0;
    if (t < 0.83) return 1;
    return 2;
  }

  static bool _in(double t, double a, double b) => t >= a && t < b;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final index = _trackIndex(t);
        final dateIndex = _momoDateIndex(t);
        final flickUp = _in(t, 0.05, 0.13) || _in(t, 0.18, 0.26);
        final flickDown = _in(t, 0.32, 0.40) || _in(t, 0.46, 0.54);
        final tap = _in(t, 0.63, 0.68) || _in(t, 0.77, 0.82);

        return SizedBox(
          width: 200,
          height: _cardHeight + 24,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                width: 200,
                height: _cardHeight,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  border: Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: colors.scrim.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: OverflowBox(
                  minHeight: 0,
                  maxHeight: double.infinity,
                  alignment: Alignment.topCenter,
                  child: Transform.translate(
                    offset: Offset(0, -index * _cardHeight),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FriendMiniCard(
                          name: 'Momo',
                          date: _momoDates[dateIndex],
                          height: _cardHeight,
                          colors: const [Color(0xFFDCE9F4), Color(0xFFF2D9CF)],
                        ),
                        _FriendMiniCard(
                          name: 'Haru',
                          date: "'26 9 17",
                          height: _cardHeight,
                          colors: const [Color(0xFFD9EEE4), Color(0xFFF3E4BD)],
                        ),
                        _FriendMiniCard(
                          name: 'Yuna',
                          date: "'26 9 16",
                          height: _cardHeight,
                          colors: const [Color(0xFFE5DCF4), Color(0xFFF2D5DE)],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (flickUp)
                Positioned(
                  right: 10,
                  top: _cardHeight * 0.30,
                  child: _GestureDot(color: colors.primary),
                ),
              if (flickDown)
                Positioned(
                  right: 10,
                  top: _cardHeight * 0.62,
                  child: _GestureDot(color: colors.primary),
                ),
              if (tap)
                Positioned(
                  left: 74,
                  top: _cardHeight * 0.55,
                  child: _GestureDot(color: colors.primary, filled: true),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FriendMiniCard extends StatelessWidget {
  const _FriendMiniCard({
    required this.name,
    required this.date,
    required this.height,
    required this.colors,
  });

  final String name;
  final String date;
  final double height;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: height,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.outlineVariant,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                name,
                style: BloomText.labelSm.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.colors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors,
                    ),
                  ),
                ),
                Positioned(
                  right: 6,
                  bottom: 5,
                  child: Text(
                    date,
                    style: const TextStyle(
                      color: Color(0xFFEF7B52),
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GestureDot extends StatelessWidget {
  const _GestureDot({required this.color, this.filled = false});

  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color.withValues(alpha: 0.25) : Colors.transparent,
        border: Border.all(color: color, width: 1.4),
      ),
    );
  }
}

// ---------------------------------------------------------------- Page 3

/// 右フリック/横向きでカメラへ入る様子。
///
/// 前半(0-50%): portrait の Home → 右フリック → phone body は portrait の
/// ままで画面内容だけ Camera に切り替わる → その後 body 自体が左へ(CCW)
/// 90°回転する。
/// 後半(50-100%): portrait Home へリセット → body が左へ(CCW)90°回転 →
/// その結果として Camera が自動的に開く(内容切り替えが回転の後に来る)。
///
/// シャッターは portrait 状態での下辺に描き、body ごと回転させることで
/// 結果的に右側へ来るようにする(特別な位置合わせをしていない)。
class _CameraDemo extends StatefulWidget {
  const _CameraDemo();

  @override
  State<_CameraDemo> createState() => _CameraDemoState();
}

class _CameraDemoState extends State<_CameraDemo> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 9800))
        ..repeat();

  static double _ramp(double t, double a, double b, double from, double to) {
    final f = ((t - a) / (b - a)).clamp(0.0, 1.0);
    return from + (to - from) * f;
  }

  /// 0 = portrait, 1 = CCW 90°回転しきった状態。
  static double _rotation(double t) {
    if (t < 0.30) return 0;
    if (t < 0.40) return _ramp(t, 0.30, 0.40, 0, 1);
    if (t < 0.50) return 1;
    if (t < 0.56) return _ramp(t, 0.50, 0.56, 1, 0);
    if (t < 0.62) return 0;
    if (t < 0.75) return _ramp(t, 0.62, 0.75, 0, 1);
    if (t < 0.90) return 1;
    return _ramp(t, 0.90, 1.0, 1, 0);
  }

  /// Camera 内容の不透明度。前半は回転より先に切り替わり、後半は回転の後。
  static double _cameraOpacity(double t) {
    if (t < 0.12) return 0;
    if (t < 0.18) return _ramp(t, 0.12, 0.18, 0, 1);
    if (t < 0.56) return 1;
    if (t < 0.62) return 0;
    if (t < 0.75) return 0; // 後半: 回転が終わるまで内容は Home のまま。
    if (t < 0.80) return _ramp(t, 0.75, 0.80, 0, 1);
    if (t < 0.96) return 1;
    return _ramp(t, 0.96, 1.0, 1, 0);
  }

  static bool _flickHintVisible(double t) => t >= 0.03 && t < 0.11;

  static bool _tiltHintVisible(double t) =>
      (t >= 0.28 && t < 0.40) || (t >= 0.60 && t < 0.75);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final rotation = _rotation(t);
        final cameraOpacity = _cameraOpacity(t);

        return SizedBox(
          width: 260,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_tiltHintVisible(t))
                Positioned(
                  top: 26,
                  child: Text(
                    '↶',
                    style: TextStyle(fontSize: 26, color: colors.primary),
                  ),
                ),
              Transform.rotate(
                angle: -rotation * (math.pi / 2),
                child: _MiniPhoneBody(cameraOpacity: cameraOpacity),
              ),
              if (_flickHintVisible(t))
                Positioned(
                  right: 40,
                  child: _GestureDot(color: colors.primary),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// portrait 前提の見た目の携帯本体。シャッターは下辺に置く
/// (親の Transform.rotate で全体を回すと、結果的に右辺へ来る)。
class _MiniPhoneBody extends StatelessWidget {
  const _MiniPhoneBody({required this.cameraOpacity});

  final double cameraOpacity;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 84,
      height: 142,
      padding: const EdgeInsets.fromLTRB(7, 14, 7, 20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant, width: 1.4),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.scrim.withValues(alpha: 0.2),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Home 画面(下地。カメラが被さっていく)。
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  children: [
                    Container(
                      height: 5,
                      width: 30,
                      decoration: BoxDecoration(
                        color: colors.outlineVariant,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFDCE7F1), Color(0xFFEFD8C8)],
                          ),
                          borderRadius: BorderRadius.all(Radius.circular(6)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Camera 画面(内容だけが被さって切り替わる)。
          Opacity(
            opacity: cameraOpacity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF16171A),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          // シャッター(portrait の下辺中央)。回転しても body に固定のまま。
          Positioned(
            left: 0,
            right: 0,
            bottom: -14,
            child: Center(
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: cameraOpacity),
                  border: Border.all(color: colors.onSurface, width: 1.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
