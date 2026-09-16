import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Bloom のアプリアイコン。
/// 寄り添う2つのハート（すれ違い）と、その中心でひらく蓮の花（思い出）を描く。
class BloomLogo extends StatelessWidget {
  const BloomLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _BloomLogoPainter()),
    );
  }
}

class _BloomLogoPainter extends CustomPainter {
  static const _coral = Color(0xFFFF6B4A);
  static const _amber = Color(0xFFFFB067);

  /// 単位正方形に収まるハート。
  Path _heart(Rect rect) {
    final w = rect.width;
    final h = rect.height;
    double x(double t) => rect.left + t * w;
    double y(double t) => rect.top + t * h;

    return Path()
      ..moveTo(x(0.5), y(1.0))
      ..cubicTo(x(-0.16), y(0.56), x(0.08), y(-0.02), x(0.5), y(0.30))
      ..cubicTo(x(0.92), y(-0.02), x(1.16), y(0.56), x(0.5), y(1.0))
      ..close();
  }

  void _drawHeart(
    Canvas canvas,
    Rect rect,
    Color color,
    double turns,
  ) {
    final center = rect.center;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(turns);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawPath(_heart(rect), Paint()..color = color..isAntiAlias = true);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);

    // 左：コーラルのハート（あなた）
    _drawHeart(
      canvas,
      Rect.fromCenter(
        center: c.translate(-s * 0.13, s * 0.01),
        width: s * 0.72,
        height: s * 0.74,
      ),
      _coral,
      -0.22,
    );

    // 右：アンバーのハート（フレンド）
    _drawHeart(
      canvas,
      Rect.fromCenter(
        center: c.translate(s * 0.15, -s * 0.02),
        width: s * 0.62,
        height: s * 0.64,
      ),
      _amber,
      0.24,
    );

    // 中央：ひらく花
    final petal = Paint()
      ..color = Colors.white.withValues(alpha: 0.88)
      ..isAntiAlias = true;
    const petalCount = 5;
    final petalDistance = s * 0.115;
    for (var i = 0; i < petalCount; i++) {
      final angle = -math.pi / 2 + i * (2 * math.pi / petalCount);
      final petalCenter = c.translate(
        math.cos(angle) * petalDistance,
        math.sin(angle) * petalDistance + s * 0.02,
      );
      canvas.save();
      canvas.translate(petalCenter.dx, petalCenter.dy);
      canvas.rotate(angle + math.pi / 2);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: s * 0.15, height: s * 0.24),
        petal,
      );
      canvas.restore();
    }
    canvas.drawCircle(
      c.translate(0, s * 0.02),
      s * 0.075,
      Paint()..color = Colors.white..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
