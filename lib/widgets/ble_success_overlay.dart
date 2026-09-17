import 'package:flutter/material.dart';

import '../theme/bloom_theme.dart';

/// v15 の BLE 交換成功カード。
///
/// 近接イベントが成立しただけでは出さない。新しく閲覧可能になった投稿が
/// 1件以上増えたときだけ、呼び出し側（MainShell）が表示を判断する。
class BleSuccessOverlay extends StatefulWidget {
  const BleSuccessOverlay({
    super.key,
    required this.peerName,
    required this.newPostCount,
  });

  final String peerName;
  final int newPostCount;

  @override
  State<BleSuccessOverlay> createState() => _BleSuccessOverlayState();
}

class _BleSuccessOverlayState extends State<BleSuccessOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IgnorePointer(
      child: Container(
        color: colors.scrim.withValues(alpha: 0.52),
        alignment: Alignment.center,
        child: Container(
          width: 240,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(BloomRadius.lg),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 54,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final t = Curves.easeOutCubic.transform(_controller.value);
                    final dx = 44 * t;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.translate(
                          offset: Offset(-24 + dx, 0),
                          child: _MeetDot(color: colors.onSurface),
                        ),
                        Transform.translate(
                          offset: Offset(24 - dx, 0),
                          child: _MeetDot(color: colors.onSurface),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${widget.peerName}と交換しました',
                style: BloomText.labelLg.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 5),
              Text(
                '新しい投稿が${widget.newPostCount}件増えました',
                style: BloomText.labelSm.copyWith(color: colors.secondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeetDot extends StatelessWidget {
  const _MeetDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
    );
  }
}
