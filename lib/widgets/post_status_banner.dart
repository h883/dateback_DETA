import 'package:flutter/material.dart';

import '../theme/bloom_theme.dart';

/// v15 の `.status-banner`。投稿の成功/失敗を Home のボトムナビ直上に
/// 短時間だけ知らせる。通常操作を大きく邪魔しない、控えめな見た目にする。
class PostStatusBanner extends StatelessWidget {
  const PostStatusBanner({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.fromLTRB(13, 8, 8, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(BloomRadius.lg),
        boxShadow: [
          BoxShadow(
            color: colors.scrim.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: BloomText.labelLg.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onAction,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: colors.onSurface,
                borderRadius: BorderRadius.circular(BloomRadius.pill),
              ),
              child: Text(
                actionLabel,
                style: BloomText.labelSm.copyWith(
                  color: colors.surface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
