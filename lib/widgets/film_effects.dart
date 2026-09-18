import 'dart:math' as math;

import 'package:flutter/material.dart';

/// [FilmGate] をどちらの辺に沿って表示するか。
///
/// 通常の(portrait のまま表示する)再生では [left] が正しい見た目。
/// tilt-to-camera 中の Camera ライブプレビューだけは、映像内容に
/// `previewQuarterTurnsForTilt` 相当の表示専用回転がかかる一方
/// [Film8mmEffects] 自身のオーバーレイはその回転の**外側**にあるため、
/// 何も指定しないと物理的に見た目の辺がズレる。呼び出し側
/// ([PostTab])がその場合だけ [top] を指定して補正する。
enum FilmGateEdge { left, top }

/// 8mm の演出(フィルムゲート・控えめなグレイン・ごく小さなジッター)。
///
/// Camera のライブプレビューと、dateback 内で8mm投稿をフルサイズ再生する
/// どの表示(Home・投稿ビューアー・ログ一覧)からも同じ実装を使う。
/// MP4 ファイル自体には焼き込まない(重い再エンコードが要るため)。
/// Profile グリッドの小さいサムネイル(`playVideo:false`)では使わない想定。
class Film8mmEffects extends StatefulWidget {
  const Film8mmEffects({
    super.key,
    required this.active,
    required this.child,
    this.gateEdge = FilmGateEdge.left,
  });

  final bool active;
  final Widget child;

  /// 既定は [FilmGateEdge.left](従来どおりの見た目)。他の呼び出し元
  /// (Home・投稿ビューアー・ログ一覧・下書きプレビュー)はこの引数を
  /// 渡さないため、挙動は変わらない。
  final FilmGateEdge gateEdge;

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
          FilmGate(edge: widget.gateEdge),
        ],
      ),
    );
  }
}

/// フィルムゲート表現(暗い縁 + アクセント縁のノッチ)。[edge] に沿って表示する。
class FilmGate extends StatelessWidget {
  const FilmGate({super.key, this.edge = FilmGateEdge.left});

  final FilmGateEdge edge;

  @override
  Widget build(BuildContext context) {
    final isLeft = edge == FilmGateEdge.left;
    return IgnorePointer(
      child: Stack(
        children: [
          isLeft
              ? const Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 11,
                  child: ColoredBox(color: Color(0xE6020202)),
                )
              : const Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  height: 11,
                  child: ColoredBox(color: Color(0xE6020202)),
                ),
          isLeft
              ? Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(child: _GateNotch(edge: edge)),
                )
              : Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  child: Center(child: _GateNotch(edge: edge)),
                ),
        ],
      ),
    );
  }
}

class _GateNotch extends StatelessWidget {
  const _GateNotch({required this.edge});

  final FilmGateEdge edge;

  @override
  Widget build(BuildContext context) {
    final isLeft = edge == FilmGateEdge.left;
    return Container(
      width: isLeft ? 30 : 84,
      height: isLeft ? 84 : 30,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xCCEF7B52), width: 2),
        borderRadius: isLeft
            ? const BorderRadius.horizontal(right: Radius.circular(16))
            : const BorderRadius.vertical(bottom: Radius.circular(16)),
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
