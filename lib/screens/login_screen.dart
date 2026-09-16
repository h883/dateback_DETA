import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/bloom_theme.dart';
import '../widgets/bloom_logo.dart';
import '../widgets/google_logo.dart';

/// ログイン画面（Google アカウント連携）。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    // TODO(auth): 実際の Google 認証と Bloom ノードへの接続をここで行う。
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: BloomColors.scrim.withValues(alpha: 0.6),
      builder: (_) => const _ConnectingDialog(
        message: 'Googleアカウントで安全にログインしています...',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BloomColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            BloomSpace.margin,
            BloomSpace.md,
            BloomSpace.margin,
            40,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _brandBlock(),
                  const SizedBox(height: 32),
                  _googleButton(),
                  const SizedBox(height: 48),
                  const _BleSafetyNote(),
                  const SizedBox(height: BloomSpace.md),
                  const _TermsNote(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _brandBlock() {
    return Stack(
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      children: [
        // 背景の暖かいにじみ
        Positioned(
          top: -48,
          child: _GlowBlob(
            size: 300,
            color: BloomColors.primaryContainer.withValues(alpha: 0.18),
          ),
        ),
        Positioned(
          top: 32,
          right: -8,
          child: _GlowBlob(
            size: 200,
            color: BloomColors.tertiaryFixedDim.withValues(alpha: 0.10),
          ),
        ),
        Column(
          children: [
            _statusBadge(),
            const SizedBox(height: BloomSpace.lg),
            _appIcon(),
            const SizedBox(height: BloomSpace.lg),
            Text('Bloom', style: BloomText.headlineLg),
            const SizedBox(height: 4),
            Text(
              '会った分だけ、思い出がひらく',
              style: BloomText.headlineSm.copyWith(color: BloomColors.primary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: BloomSpace.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                'すれ違いから始まる、オフライン発想のリアルタイム記憶カプセル',
                style: BloomText.bodySm
                    .copyWith(color: BloomColors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: BloomColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(BloomRadius.pill),
        boxShadow: BloomShadow.subtle,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 1.0, end: 0.35).animate(_pulse),
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: BloomColors.tertiary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'NOVAHACK 2026 接続準備完了',
            style: BloomText.labelSm.copyWith(
              color: BloomColors.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _appIcon() {
    return SizedBox(
      width: 128,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          _GlowBlob(
            size: 128,
            color: BloomColors.primaryContainer.withValues(alpha: 0.22),
          ),
          Container(
            width: 112,
            height: 112,
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: BloomColors.surfaceContainerLowest,
              shape: BoxShape.circle,
              boxShadow: BloomShadow.soft,
            ),
            child: const BloomLogo(size: 96),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: BloomColors.tertiary,
                shape: BoxShape.circle,
                boxShadow: BloomShadow.subtle,
              ),
              child: const Icon(
                Icons.lock_open,
                size: 18,
                color: BloomColors.onTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _googleButton() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BloomRadius.pill),
        boxShadow: BloomShadow.soft,
      ),
      child: FilledButton(
        onPressed: _signInWithGoogle,
        style: FilledButton.styleFrom(
          backgroundColor: BloomColors.surfaceContainerLowest,
          foregroundColor: BloomColors.onSurface,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: StadiumBorder(
            side: BorderSide(
              color: BloomColors.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const GoogleLogo(size: 24),
            const SizedBox(width: 12),
            Text(
              'Googleアカウントで続ける',
              style: BloomText.labelLg.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// BLE の安心設計についての説明カード。
class _BleSafetyNote extends StatelessWidget {
  const _BleSafetyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BloomSpace.md),
      decoration: BoxDecoration(
        color: BloomColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(BloomRadius.lg),
        boxShadow: BloomShadow.subtle,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: BloomColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(BloomRadius.base),
              boxShadow: BloomShadow.subtle,
            ),
            child: const Icon(
              Icons.bluetooth_searching,
              size: 20,
              color: BloomColors.tertiary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '対面BLE暗号化セーフティ',
                        style: BloomText.labelMd,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: BloomColors.tertiaryFixed,
                        borderRadius: BorderRadius.circular(BloomRadius.sm),
                      ),
                      child: Text(
                        '安心設計',
                        style: BloomText.labelSm
                            .copyWith(color: BloomColors.onTertiaryFixed),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Bluetooth (BLE) を使用して、対面時にのみ投稿の鍵がひらきます。'
                  '位置情報が常時共有されることはありません。',
                  style: BloomText.bodySm
                      .copyWith(color: BloomColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 利用規約・プライバシーポリシーの同意文。
class _TermsNote extends StatelessWidget {
  const _TermsNote();

  @override
  Widget build(BuildContext context) {
    final link = BloomText.bodySm.copyWith(
      color: BloomColors.secondary,
      decoration: TextDecoration.underline,
      decorationColor: BloomColors.secondary,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BloomSpace.md),
      child: Text.rich(
        TextSpan(
          style: BloomText.bodySm.copyWith(color: BloomColors.secondary),
          children: [
            TextSpan(text: '利用規約', style: link),
            const TextSpan(text: ' および '),
            TextSpan(text: 'プライバシーポリシー', style: link),
            const TextSpan(text: ' に同意の上ログインしてください'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// 認証連携中のモーダル。
class _ConnectingDialog extends StatefulWidget {
  const _ConnectingDialog({required this.message});

  final String message;

  @override
  State<_ConnectingDialog> createState() => _ConnectingDialogState();
}

class _ConnectingDialogState extends State<_ConnectingDialog> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Dialog(
        backgroundColor: BloomColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BloomRadius.lg),
        ),
        insetPadding: const EdgeInsets.all(BloomSpace.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.all(BloomSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: BloomColors.primaryFixed,
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: BloomColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('認証連携中', style: BloomText.headlineSm),
                const SizedBox(height: 4),
                Text(
                  widget.message,
                  style: BloomText.bodySm
                      .copyWith(color: BloomColors.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: BloomSpace.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(BloomRadius.pill),
                  child: const LinearProgressIndicator(
                    minHeight: 6,
                    color: BloomColors.primary,
                    backgroundColor: BloomColors.surfaceContainerHigh,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ぼかした色の玉（Tailwind の blur-3xl 相当の環境光）。
/// 縁が完全な透明に溶けるよう、単色ではなく放射状グラデーションで描く。
class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}
