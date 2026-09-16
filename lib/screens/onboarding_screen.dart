import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/bloom_theme.dart';
import '../widgets/bloom_logo.dart';
import 'login_screen.dart';

const _lockedPhotoUrl =
    'https://lh3.googleusercontent.com/aida-public/AB6AXuCH-RVDWCIzAFv5IWxXBj5GlMf7uj_aThU1L8r435NjIt-nlaCDEwf7-MSOeGcmbNrf2jhZQKkx0e0gaXTRlB7u29KBG8jcY6tafClGXNChmO2xwcxT3-A81icb_hHB7LUH02VoJwt_Z6vAsfLr3jKD1UA4aySUruaM0wSButbzQYkhsElWfY7k_0ipo6vBi9tXdNIoJJbzj4tc7Gj0KJ79fqPW4kslGlcXEAB91eMtQfljASAa-OfA';
const _unlockedPhotoUrl =
    'https://lh3.googleusercontent.com/aida-public/AB6AXuDcHroe37uZ5AaILcYSS9U9x-_rCqyPLqA1tPbuEKZM48looXAQ-zWledML3L2c84J_YSvaPmLQa8qe6gCosrVYowJ8ssr9UDjY0TqEpKQFtm2lT2dyerk7J2Knag_W50laD4S31hLraL_syI25zhxxhfusLKLu4ej9b4cNxjYGlrB__vvgtQUbyJ6rWx5_4dGhQW60FM46F53CBv4DIC7RwWwlNDJ5xDHAFuYONGb5O7rzG5E-1YmW';

/// チュートリアル（3ステップ）画面。
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _totalSteps = 3;

  final _controller = PageController();
  int _step = 0;

  bool get _isLastStep => _step == _totalSteps - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    _controller.animateToPage(
      step,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPrimaryAction() {
    if (_isLastStep) {
      _openLogin();
    } else {
      _goToStep(_step + 1);
    }
  }

  void _openLogin() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BloomColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: BloomSpace.margin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const SizedBox(height: BloomSpace.xs),
              const _SloganChip(),
              const SizedBox(height: BloomSpace.md),
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (index) => setState(() => _step = index),
                  children: const [
                    _PostSlide(),
                    _EncounterSlide(),
                    _BloomSlide(),
                  ],
                ),
              ),
              const SizedBox(height: BloomSpace.md),
              _dots(),
              const SizedBox(height: BloomSpace.lg),
              _primaryButton(),
              const SizedBox(height: BloomSpace.sm),
              _loginEntry(),
              const SizedBox(height: BloomSpace.md),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BloomSpace.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: BloomColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(BloomRadius.md),
                  boxShadow: BloomShadow.subtle,
                ),
                padding: const EdgeInsets.all(2),
                child: const BloomLogo(size: 32),
              ),
              const SizedBox(width: BloomSpace.sm),
              Text('Bloom', style: BloomText.headlineSm),
            ],
          ),
          TextButton(
            onPressed: () => _goToStep(_totalSteps - 1),
            style: TextButton.styleFrom(
              foregroundColor: BloomColors.secondary,
              padding: const EdgeInsets.symmetric(
                horizontal: BloomSpace.sm,
                vertical: BloomSpace.xs,
              ),
              shape: const StadiumBorder(),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'スキップ',
              style: BloomText.labelMd.copyWith(color: BloomColors.secondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_totalSteps, (index) {
        final isActive = index == _step;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: GestureDetector(
            onTap: () => _goToStep(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              width: isActive ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: isActive
                    ? BloomColors.primary
                    : BloomColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(BloomRadius.pill),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _primaryButton() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BloomRadius.pill),
        boxShadow: BloomShadow.memory,
      ),
      child: FilledButton(
        onPressed: _onPrimaryAction,
        style: FilledButton.styleFrom(
          backgroundColor: _isLastStep
              ? BloomColors.primaryDeep
              : BloomColors.primaryContainer,
          foregroundColor: BloomColors.onPrimaryContainer,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: const StadiumBorder(),
          animationDuration: const Duration(milliseconds: 200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _isLastStep ? 'はじめる（ログインへ進む）' : '次へ',
              style: BloomText.labelLg.copyWith(
                color: BloomColors.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: BloomSpace.sm),
            Icon(
              _isLastStep ? Icons.auto_awesome : Icons.arrow_forward,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _loginEntry() {
    return Center(
      child: TextButton(
        onPressed: _openLogin,
        style: TextButton.styleFrom(
          foregroundColor: BloomColors.secondary,
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(
            horizontal: BloomSpace.sm,
            vertical: BloomSpace.xs,
          ),
        ),
        child: Text(
          'すでにアカウントをお持ちの方はこちら',
          style: BloomText.bodySm.copyWith(color: BloomColors.secondary),
        ),
      ),
    );
  }
}

class _SloganChip extends StatelessWidget {
  const _SloganChip();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: BloomColors.primaryFixed,
          borderRadius: BorderRadius.circular(BloomRadius.pill),
        ),
        child: Text(
          '会った分だけ、思い出がひらく',
          style: BloomText.labelSm.copyWith(
            color: BloomColors.primary,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}

/// 各スライド共通のレイアウト（カード + 見出し + 説明）。
class _SlideScaffold extends StatelessWidget {
  const _SlideScaffold({
    required this.card,
    required this.title,
    required this.description,
  });

  final Widget card;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    // 余白があれば中央寄せ、足りなければスクロールさせる。
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 310),
                child: AspectRatio(aspectRatio: 4 / 5, child: card),
              ),
              const SizedBox(height: BloomSpace.lg),
              Text(
                title,
                style: BloomText.headlineMd,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: BloomSpace.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  description,
                  style: BloomText.bodyMd.copyWith(color: BloomColors.secondary),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 白い「印画紙」カード。
class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.child, this.padding = 12});

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: BloomColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(BloomRadius.lg),
        boxShadow: BloomShadow.memory,
      ),
      child: child,
    );
  }
}

/// ネットワーク画像。取得できない場合は暖色グラデーションにフォールバックする。
class _MemoryPhoto extends StatelessWidget {
  const _MemoryPhoto({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const _PhotoPlaceholder(),
      errorBuilder: (context, error, stackTrace) => const _PhotoPlaceholder(),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A1412),
            Color(0xFF33201A),
            Color(0xFF1F1714),
          ],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

/// STEP 1: 投稿しよう
class _PostSlide extends StatelessWidget {
  const _PostSlide();

  @override
  Widget build(BuildContext context) {
    return _SlideScaffold(
      title: '投稿しよう',
      description: '日常の写真や動画を自由に残せます。今はまだ、あなただけの秘密。',
      card: _MemoryCard(
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(BloomRadius.md),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: BloomColors.surfaceContainerHigh),
                    const _MemoryPhoto(url: _lockedPhotoUrl),
                    // 施錠状態：ぼかし + インディゴのベール
                    BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                      child: Container(
                        color: BloomColors.scrim.withValues(alpha: 0.45),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(
                                color: BloomColors.surfaceContainerLowest,
                                shape: BoxShape.circle,
                                boxShadow: BloomShadow.soft,
                              ),
                              child: const Icon(
                                Icons.lock,
                                color: BloomColors.primary,
                                size: 24,
                              ),
                            ),
                            const SizedBox(height: BloomSpace.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: BloomColors.scrim.withValues(alpha: 0.65),
                                borderRadius:
                                    BorderRadius.circular(BloomRadius.pill),
                              ),
                              child: Text(
                                'カプセルに保管中',
                                style: BloomText.labelSm.copyWith(
                                  color: BloomColors.onScrim,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: BloomSpace.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                        color: BloomColors.secondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'きょうの記録',
                        style: BloomText.labelSm
                            .copyWith(color: BloomColors.secondary),
                      ),
                    ],
                  ),
                  Text(
                    '非公開・未開封',
                    style:
                        BloomText.labelSm.copyWith(color: BloomColors.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// STEP 2: 友達と会おう
class _EncounterSlide extends StatefulWidget {
  const _EncounterSlide();

  @override
  State<_EncounterSlide> createState() => _EncounterSlideState();
}

class _EncounterSlideState extends State<_EncounterSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SlideScaffold(
      title: '友達と会おう',
      description: '近くにいるフレンドをアプリが見つけます。リアルで出会うだけでOK。',
      card: _MemoryCard(
        padding: BloomSpace.md,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(BloomRadius.md),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // レーダーの同心円
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final t = _pulse.value;
                  return Container(
                    width: 256 * (0.6 + 0.4 * t),
                    height: 256 * (0.6 + 0.4 * t),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: BloomColors.secondaryContainer
                          .withValues(alpha: 0.25 * (1 - t)),
                    ),
                  );
                },
              ),
              Container(
                width: 192,
                height: 192,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: BloomColors.tertiaryFixed.withValues(alpha: 0.12),
                ),
              ),
              Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: BloomColors.tertiaryFixed.withValues(alpha: 0.18),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _ProximityNode(
                        label: 'あなた',
                        ringColor: BloomColors.primaryContainer,
                        icon: Icons.face,
                        iconColor: BloomColors.primary,
                      ),
                      const SizedBox(width: BloomSpace.lg),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(
                              color: BloomColors.tertiary,
                              shape: BoxShape.circle,
                              boxShadow: BloomShadow.subtle,
                            ),
                            child: FadeTransition(
                              opacity: Tween<double>(begin: 0.45, end: 1.0)
                                  .animate(CurvedAnimation(
                                parent: _pulse,
                                curve: Curves.easeInOut,
                              )),
                              child: const Icon(
                                Icons.bluetooth_searching,
                                size: 18,
                                color: BloomColors.onTertiary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'すれ違い中',
                            style: BloomText.labelSm
                                .copyWith(color: BloomColors.tertiary),
                          ),
                        ],
                      ),
                      const SizedBox(width: BloomSpace.lg),
                      const _ProximityNode(
                        label: 'フレンド',
                        ringColor: BloomColors.tertiaryContainer,
                        icon: Icons.favorite,
                        iconColor: BloomColors.tertiary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: BloomColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(BloomRadius.pill),
                      boxShadow: BloomShadow.subtle,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FadeTransition(
                          opacity:
                              Tween<double>(begin: 1.0, end: 0.2).animate(_pulse),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: BloomColors.tertiaryContainer,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '近接ビーコンを自動検出',
                          style: BloomText.labelSm
                              .copyWith(color: BloomColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProximityNode extends StatelessWidget {
  const _ProximityNode({
    required this.label,
    required this.ringColor,
    required this.icon,
    required this.iconColor,
  });

  final String label;
  final Color ringColor;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: ringColor,
            shape: BoxShape.circle,
            boxShadow: BloomShadow.soft,
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: BloomColors.surfaceContainerLowest,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: BloomText.labelSm),
      ],
    );
  }
}

/// STEP 3: 思い出がひらく
class _BloomSlide extends StatelessWidget {
  const _BloomSlide();

  @override
  Widget build(BuildContext context) {
    return _SlideScaffold(
      title: '思い出がひらく',
      description: '会った時点までの投稿がお互いに見られるようになります。',
      card: _MemoryCard(
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(BloomRadius.md),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: BloomColors.surfaceContainerHigh),
                    const _MemoryPhoto(url: _unlockedPhotoUrl),
                    // 開花バッジ
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: BloomColors.primaryContainer,
                          borderRadius: BorderRadius.circular(BloomRadius.pill),
                          boxShadow: BloomShadow.subtle,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.local_florist,
                              size: 12,
                              color: BloomColors.onPrimary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '開花完了',
                              style: BloomText.labelSm
                                  .copyWith(color: BloomColors.onPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 解除した場所と日時
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              BloomColors.scrim.withValues(alpha: 0.8),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '渋谷・代官山にて解除',
                              style: BloomText.labelSm.copyWith(
                                color: BloomColors.onScrim,
                              ),
                            ),
                            Text(
                              '2025.04.12 15:30',
                              style: BloomText.labelSm.copyWith(
                                color: BloomColors.onScrim.withValues(alpha: 0.75),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: BloomSpace.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.lock_open,
                        size: 16,
                        color: BloomColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'お互いの写真が開通',
                        style:
                            BloomText.labelSm.copyWith(color: BloomColors.primary),
                      ),
                    ],
                  ),
                  Text(
                    '共有済み',
                    style: BloomText.labelSm.copyWith(
                      color: BloomColors.secondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
