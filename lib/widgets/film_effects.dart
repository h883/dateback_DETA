import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 8mm の演出(フィルムゲート・控えめなグレイン・ごく小さなジッター)。
///
/// Camera のライブプレビューと、dateback 内で8mm投稿をフルサイズ再生する
/// どの表示(Home・投稿ビューアー・ログ一覧)からも同じ実装を使う。
/// MP4 ファイル自体には焼き込まない(重い再エンコードが要るため)。
/// Profile グリッドの小さいサムネイル(`playVideo:false`)では使わない想定。
class Film8mmEffects extends StatefulWidget {
  const Film8mmEffects({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<Film8mmEffects> createState() => _Film8mmEffectsState();
}

class _Film8mmEffectsState extends State<Film8mmEffects>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final offset = Offset(
          math.sin(_controller.value * math.pi * 2) * 0.6,
          math.cos(_controller.value * math.pi * 2 * 1.3) * 0.5,
        );
        return Transform.translate(offset: offset, child: child);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          const GrainOverlay(),
          const FilmGate(),
        ],
      ),
    );
  }
}

/// 左側のフィルムゲート表現(暗い縁 + アクセント縁のノッチ)。
class FilmGate extends StatelessWidget {
  const FilmGate({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 11,
            child: ColoredBox(color: Color(0xE6020202)),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(child: _GateNotch()),
          ),
        ],
      ),
    );
  }
}

class _GateNotch extends StatelessWidget {
  const _GateNotch();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 84,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xCCEF7B52), width: 2),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
      ),
    );
  }
}

/// 控えめな粒子(グレイン)。固定パターンで静的に重ねるだけの軽量実装。
class GrainOverlay extends StatelessWidget {
  const GrainOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: CustomPaint(painter: _GrainPainter(), size: Size.infinite),
    );
  }
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(7);
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (var i = 0; i < 70; i++) {
      final dx = random.nextDouble() * size.width;
      final dy = random.nextDouble() * size.height;
      canvas.drawCircle(Offset(dx, dy), 0.7, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GrainPainter oldDelegate) => false;
}
