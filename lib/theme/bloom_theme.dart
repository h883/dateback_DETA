import 'package:flutter/material.dart';

/// "Warm Encounter" デザインシステムのダーク版トークン。
/// 下地を黒に統一し、テラコッタとミントのアクセントだけを残している。
///
/// 命名は元の Material 3 のロールを引き継いでいるが、ダークでは
/// `surfaceContainerLowest` が「黒の上に浮く紙のカード」を指す点に注意
/// （ライト版で純白のカードだったロールをそのまま踏襲している）。
abstract final class BloomColors {
  static const surface = Color(0xFF000000);
  static const surfaceDim = Color(0xFF000000);
  static const surfaceBright = Color(0xFF241F1E);

  /// 黒地に浮くカード面。数値は下に行くほど明るくなる。
  static const surfaceContainerLowest = Color(0xFF17120F);
  static const surfaceContainerLow = Color(0xFF121010);
  static const surfaceContainer = Color(0xFF1C1817);
  static const surfaceContainerHigh = Color(0xFF241F1D);
  static const surfaceContainerHighest = Color(0xFF2C2624);

  static const onSurface = Color(0xFFF3F0ED);
  static const onSurfaceVariant = Color(0xFFD6C1BB);
  static const inverseSurface = Color(0xFFF3F0ED);

  /// 写真の上に重ねる幕。テーマの明暗に関わらず常に黒。
  static const scrim = Color(0xFF000000);

  /// 幕の上に載る文字。常に白。
  static const onScrim = Color(0xFFFFFFFF);

  static const outline = Color(0xFFA08D87);
  static const outlineVariant = Color(0xFF52443F);

  static const primary = Color(0xFFFF8A6B);
  static const onPrimary = Color(0xFF5A0F00);
  static const primaryContainer = Color(0xFFFF6B4A);

  /// 最終ステップの CTA。黒地に沈まない程度に深いテラコッタで、
  /// 白文字を載せてもコントラストが保てる値にしている。
  static const primaryDeep = Color(0xFFC0391A);
  static const onPrimaryContainer = Color(0xFFFFFFFF);
  static const primaryFixed = Color(0xFF4E1409);
  static const primaryFixedDim = Color(0xFFFFB4A3);

  static const secondary = Color(0xFFB6B9CC);
  static const onSecondary = Color(0xFF2B2F44);
  static const secondaryContainer = Color(0xFF3F4358);

  static const tertiary = Color(0xFF4FDBCC);
  static const onTertiary = Color(0xFF00382F);
  static const tertiaryContainer = Color(0xFF00ADA0);
  static const tertiaryFixed = Color(0xFF70F8E8);
  static const tertiaryFixedDim = Color(0xFF4FDBCC);
  static const onTertiaryFixed = Color(0xFF00201D);

  static const error = Color(0xFFFFB4AB);
}

/// 角丸トークン。
abstract final class BloomRadius {
  static const sm = 4.0;
  static const base = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const pill = 9999.0;
}

/// 余白トークン。
abstract final class BloomSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 36.0;
  static const xxl = 56.0;
  static const margin = 20.0;
}

/// 日本語と混植するためのフォールバックスタック。
const _fontFallback = <String>[
  'Plus Jakarta Sans',
  'Hiragino Sans',
  'Hiragino Kaku Gothic ProN',
  'Noto Sans JP',
  'Yu Gothic',
];

TextStyle _t({
  required double size,
  required FontWeight weight,
  required double lineHeight,
  double letterSpacing = 0,
  Color color = BloomColors.onSurface,
}) {
  return TextStyle(
    fontSize: size,
    fontWeight: weight,
    height: lineHeight / size,
    letterSpacing: letterSpacing,
    color: color,
    fontFamilyFallback: _fontFallback,
  );
}

/// タイポグラフィトークン。
abstract final class BloomText {
  static final displayLg =
      _t(size: 40, weight: FontWeight.w700, lineHeight: 48, letterSpacing: -0.8);
  static final headlineLg =
      _t(size: 28, weight: FontWeight.w700, lineHeight: 36, letterSpacing: -0.28);
  static final headlineMd =
      _t(size: 22, weight: FontWeight.w600, lineHeight: 30, letterSpacing: -0.11);
  static final headlineSm =
      _t(size: 18, weight: FontWeight.w600, lineHeight: 26);
  static final bodyLg = _t(size: 16, weight: FontWeight.w400, lineHeight: 26);
  static final bodyMd = _t(size: 14, weight: FontWeight.w400, lineHeight: 22);
  static final bodySm = _t(size: 12, weight: FontWeight.w400, lineHeight: 18);
  static final labelLg =
      _t(size: 14, weight: FontWeight.w600, lineHeight: 20, letterSpacing: 0.14);
  static final labelMd =
      _t(size: 12, weight: FontWeight.w600, lineHeight: 16, letterSpacing: 0.24);
  static final labelSm =
      _t(size: 10, weight: FontWeight.w700, lineHeight: 14, letterSpacing: 0.4);
}

/// 影トークン。黒地では落ち影が沈むため、テラコッタの環境光で浮かせる。
abstract final class BloomShadow {
  static const memory = <BoxShadow>[
    BoxShadow(
      color: Color(0x2EFF6B4A),
      blurRadius: 36,
      spreadRadius: -6,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x66000000),
      blurRadius: 16,
      spreadRadius: -4,
      offset: Offset(0, 6),
    ),
  ];

  static const soft = <BoxShadow>[
    BoxShadow(
      color: Color(0x73000000),
      blurRadius: 16,
      spreadRadius: -2,
      offset: Offset(0, 6),
    ),
  ];

  static const subtle = <BoxShadow>[
    BoxShadow(
      color: Color(0x59000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];
}

ThemeData buildBloomTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: BloomColors.primary,
      onPrimary: BloomColors.onPrimary,
      primaryContainer: BloomColors.primaryContainer,
      onPrimaryContainer: BloomColors.onPrimaryContainer,
      secondary: BloomColors.secondary,
      onSecondary: BloomColors.onSecondary,
      secondaryContainer: BloomColors.secondaryContainer,
      tertiary: BloomColors.tertiary,
      onTertiary: BloomColors.onTertiary,
      tertiaryContainer: BloomColors.tertiaryContainer,
      error: BloomColors.error,
      surface: BloomColors.surface,
      onSurface: BloomColors.onSurface,
      onSurfaceVariant: BloomColors.onSurfaceVariant,
      outline: BloomColors.outline,
      outlineVariant: BloomColors.outlineVariant,
      inverseSurface: BloomColors.inverseSurface,
      scrim: BloomColors.scrim,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: BloomColors.surface,
    splashFactory: InkRipple.splashFactory,
    textTheme: base.textTheme.copyWith(
      displayLarge: BloomText.displayLg,
      headlineLarge: BloomText.headlineLg,
      headlineMedium: BloomText.headlineMd,
      headlineSmall: BloomText.headlineSm,
      bodyLarge: BloomText.bodyLg,
      bodyMedium: BloomText.bodyMd,
      bodySmall: BloomText.bodySm,
      labelLarge: BloomText.labelLg,
      labelMedium: BloomText.labelMd,
      labelSmall: BloomText.labelSm,
    ),
  );
}
