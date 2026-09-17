import 'package:flutter/material.dart';

import '../theme/bloom_theme.dart';

/// v15 の "dateback" ワードマーク(アクセントドット付き)。
/// Home・Profile など複数の画面ヘッダーで共通に使う。
class Wordmark extends StatelessWidget {
  const Wordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'dateback',
          style: BloomText.labelLg.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(width: 4),
        Container(
          width: 5,
          height: 5,
          margin: const EdgeInsets.only(bottom: 3),
          decoration:
              BoxDecoration(color: colors.primary, shape: BoxShape.circle),
        ),
      ],
    );
  }
}
