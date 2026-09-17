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

  /// いいねの赤（モックの --red）。
  static const heart = Color(0xFFEA5B62);

  static const error = Color(0xFFFFB4AB);
}

/// "Warm Encounter" デザインシステムのライト版トークン。
/// v15 モック（dateback_quiet_analog_mock_v15.html）の `[data-theme="light"]`
/// トークンに合わせている。ロール名は [BloomColors] と対応させてあるので、
/// 個別の画面で `BloomColors.xxx` を `context.colors.xxx` に置き換えるだけで
/// テーマ追従になる。
abstract final class BloomColorsLight {
  static const surface = Color(0xFFF4F1EA);
  static const surfaceDim = Color(0xFFF4F1EA);
  static const surfaceBright = Color(0xFFFFFFFF);

  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFEBE7DF);
  static const surfaceContainer = Color(0xFFE3DFD7);
  static const surfaceContainerHigh = Color(0xFFD9D5CD);
  static const surfaceContainerHighest = Color(0xFFCEC9BF);

  static const onSurface = Color(0xFF1A1918);
  static const onSurfaceVariant = Color(0xFF6F6B65);
  static const inverseSurface = Color(0xFF1A1918);

  /// 写真の上に重ねる幕。テーマの明暗に関わらず常に黒（ダーク版と同じ）。
  static const scrim = Color(0xFF000000);
  static const onScrim = Color(0xFFFFFFFF);

  static const outline = Color(0xFF8D8880);
  static const outlineVariant = Color(0xFFCEC9BF);

  static const primary = Color(0xFFDF6F49);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFDF6F49);

  static const primaryDeep = Color(0xFFC05A38);
  static const onPrimaryContainer = Color(0xFFFFFFFF);
  static const primaryFixed = Color(0xFFF6E4DB);
  static const primaryFixedDim = Color(0xFFDF6F49);

  static const secondary = Color(0xFF6F6B65);
  static const onSecondary = Color(0xFFFFFFFF);
  static const secondaryContainer = Color(0xFFE3DFD7);

  static const tertiary = Color(0xFF00998C);
  static const onTertiary = Color(0xFFFFFFFF);
  static const tertiaryContainer = Color(0xFF00ADA0);
  static const tertiaryFixed = Color(0xFFDFF7F3);
  static const tertiaryFixedDim = Color(0xFF00998C);
  static const onTertiaryFixed = Color(0xFF00201D);

  /// いいねの赤は明暗で変えない（モックも共通の --red 相当）。
  static const heart = Color(0xFFEA5B62);

  static const error = Color(0xFFB9564E);
}

/// [BloomColors]・[BloomColorsLight] をテーマ経由で切り替えるための
/// ThemeExtension。個々のロールは static const では明暗を持てないため、
/// 実行時に解決する必要がある箇所だけこちらを使う。
///
/// 移行は画面単位で進める想定。まだ `BloomColors.xxx` を直接参照している
/// 画面はダーク固定のまま表示されるが、既存の見た目を壊すものではない。
class BloomColorsExt extends ThemeExtension<BloomColorsExt> {
  const BloomColorsExt({
    required this.surface,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.inverseSurface,
    required this.scrim,
    required this.onScrim,
    required this.outline,
    required this.outlineVariant,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.primaryDeep,
    required this.onPrimaryContainer,
    required this.primaryFixed,
    required this.primaryFixedDim,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.tertiaryFixed,
    required this.tertiaryFixedDim,
    required this.onTertiaryFixed,
    required this.heart,
    required this.error,
  });

  final Color surface;
  final Color surfaceDim;
  final Color surfaceBright;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color inverseSurface;
  final Color scrim;
  final Color onScrim;
  final Color outline;
  final Color outlineVariant;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color primaryDeep;
  final Color onPrimaryContainer;
  final Color primaryFixed;
  final Color primaryFixedDim;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color tertiaryFixed;
  final Color tertiaryFixedDim;
  final Color onTertiaryFixed;
  final Color heart;
  final Color error;

  static const dark = BloomColorsExt(
    surface: BloomColors.surface,
    surfaceDim: BloomColors.surfaceDim,
    surfaceBright: BloomColors.surfaceBright,
    surfaceContainerLowest: BloomColors.surfaceContainerLowest,
    surfaceContainerLow: BloomColors.surfaceContainerLow,
    surfaceContainer: BloomColors.surfaceContainer,
    surfaceContainerHigh: BloomColors.surfaceContainerHigh,
    surfaceContainerHighest: BloomColors.surfaceContainerHighest,
    onSurface: BloomColors.onSurface,
    onSurfaceVariant: BloomColors.onSurfaceVariant,
    inverseSurface: BloomColors.inverseSurface,
    scrim: BloomColors.scrim,
    onScrim: BloomColors.onScrim,
    outline: BloomColors.outline,
    outlineVariant: BloomColors.outlineVariant,
    primary: BloomColors.primary,
    onPrimary: BloomColors.onPrimary,
    primaryContainer: BloomColors.primaryContainer,
    primaryDeep: BloomColors.primaryDeep,
    onPrimaryContainer: BloomColors.onPrimaryContainer,
    primaryFixed: BloomColors.primaryFixed,
    primaryFixedDim: BloomColors.primaryFixedDim,
    secondary: BloomColors.secondary,
    onSecondary: BloomColors.onSecondary,
    secondaryContainer: BloomColors.secondaryContainer,
    tertiary: BloomColors.tertiary,
    onTertiary: BloomColors.onTertiary,
    tertiaryContainer: BloomColors.tertiaryContainer,
    tertiaryFixed: BloomColors.tertiaryFixed,
    tertiaryFixedDim: BloomColors.tertiaryFixedDim,
    onTertiaryFixed: BloomColors.onTertiaryFixed,
    heart: BloomColors.heart,
    error: BloomColors.error,
  );

  static const light = BloomColorsExt(
    surface: BloomColorsLight.surface,
    surfaceDim: BloomColorsLight.surfaceDim,
    surfaceBright: BloomColorsLight.surfaceBright,
    surfaceContainerLowest: BloomColorsLight.surfaceContainerLowest,
    surfaceContainerLow: BloomColorsLight.surfaceContainerLow,
    surfaceContainer: BloomColorsLight.surfaceContainer,
    surfaceContainerHigh: BloomColorsLight.surfaceContainerHigh,
    surfaceContainerHighest: BloomColorsLight.surfaceContainerHighest,
    onSurface: BloomColorsLight.onSurface,
    onSurfaceVariant: BloomColorsLight.onSurfaceVariant,
    inverseSurface: BloomColorsLight.inverseSurface,
    scrim: BloomColorsLight.scrim,
    onScrim: BloomColorsLight.onScrim,
    outline: BloomColorsLight.outline,
    outlineVariant: BloomColorsLight.outlineVariant,
    primary: BloomColorsLight.primary,
    onPrimary: BloomColorsLight.onPrimary,
    primaryContainer: BloomColorsLight.primaryContainer,
    primaryDeep: BloomColorsLight.primaryDeep,
    onPrimaryContainer: BloomColorsLight.onPrimaryContainer,
    primaryFixed: BloomColorsLight.primaryFixed,
    primaryFixedDim: BloomColorsLight.primaryFixedDim,
    secondary: BloomColorsLight.secondary,
    onSecondary: BloomColorsLight.onSecondary,
    secondaryContainer: BloomColorsLight.secondaryContainer,
    tertiary: BloomColorsLight.tertiary,
    onTertiary: BloomColorsLight.onTertiary,
    tertiaryContainer: BloomColorsLight.tertiaryContainer,
    tertiaryFixed: BloomColorsLight.tertiaryFixed,
    tertiaryFixedDim: BloomColorsLight.tertiaryFixedDim,
    onTertiaryFixed: BloomColorsLight.onTertiaryFixed,
    heart: BloomColorsLight.heart,
    error: BloomColorsLight.error,
  );

  @override
  BloomColorsExt copyWith({
    Color? surface,
    Color? surfaceDim,
    Color? surfaceBright,
    Color? surfaceContainerLowest,
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? inverseSurface,
    Color? scrim,
    Color? onScrim,
    Color? outline,
    Color? outlineVariant,
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? primaryDeep,
    Color? onPrimaryContainer,
    Color? primaryFixed,
    Color? primaryFixedDim,
    Color? secondary,
    Color? onSecondary,
    Color? secondaryContainer,
    Color? tertiary,
    Color? onTertiary,
    Color? tertiaryContainer,
    Color? tertiaryFixed,
    Color? tertiaryFixedDim,
    Color? onTertiaryFixed,
    Color? heart,
    Color? error,
  }) {
    return BloomColorsExt(
      surface: surface ?? this.surface,
      surfaceDim: surfaceDim ?? this.surfaceDim,
      surfaceBright: surfaceBright ?? this.surfaceBright,
      surfaceContainerLowest:
          surfaceContainerLowest ?? this.surfaceContainerLowest,
      surfaceContainerLow: surfaceContainerLow ?? this.surfaceContainerLow,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
      surfaceContainerHighest:
          surfaceContainerHighest ?? this.surfaceContainerHighest,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
      inverseSurface: inverseSurface ?? this.inverseSurface,
      scrim: scrim ?? this.scrim,
      onScrim: onScrim ?? this.onScrim,
      outline: outline ?? this.outline,
      outlineVariant: outlineVariant ?? this.outlineVariant,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      primaryDeep: primaryDeep ?? this.primaryDeep,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      primaryFixed: primaryFixed ?? this.primaryFixed,
      primaryFixedDim: primaryFixedDim ?? this.primaryFixedDim,
      secondary: secondary ?? this.secondary,
      onSecondary: onSecondary ?? this.onSecondary,
      secondaryContainer: secondaryContainer ?? this.secondaryContainer,
      tertiary: tertiary ?? this.tertiary,
      onTertiary: onTertiary ?? this.onTertiary,
      tertiaryContainer: tertiaryContainer ?? this.tertiaryContainer,
      tertiaryFixed: tertiaryFixed ?? this.tertiaryFixed,
      tertiaryFixedDim: tertiaryFixedDim ?? this.tertiaryFixedDim,
      onTertiaryFixed: onTertiaryFixed ?? this.onTertiaryFixed,
      heart: heart ?? this.heart,
      error: error ?? this.error,
    );
  }

  @override
  BloomColorsExt lerp(ThemeExtension<BloomColorsExt>? other, double t) {
    if (other is! BloomColorsExt) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return BloomColorsExt(
      surface: c(surface, other.surface),
      surfaceDim: c(surfaceDim, other.surfaceDim),
      surfaceBright: c(surfaceBright, other.surfaceBright),
      surfaceContainerLowest:
          c(surfaceContainerLowest, other.surfaceContainerLowest),
      surfaceContainerLow: c(surfaceContainerLow, other.surfaceContainerLow),
      surfaceContainer: c(surfaceContainer, other.surfaceContainer),
      surfaceContainerHigh:
          c(surfaceContainerHigh, other.surfaceContainerHigh),
      surfaceContainerHighest:
          c(surfaceContainerHighest, other.surfaceContainerHighest),
      onSurface: c(onSurface, other.onSurface),
      onSurfaceVariant: c(onSurfaceVariant, other.onSurfaceVariant),
      inverseSurface: c(inverseSurface, other.inverseSurface),
      scrim: c(scrim, other.scrim),
      onScrim: c(onScrim, other.onScrim),
      outline: c(outline, other.outline),
      outlineVariant: c(outlineVariant, other.outlineVariant),
      primary: c(primary, other.primary),
      onPrimary: c(onPrimary, other.onPrimary),
      primaryContainer: c(primaryContainer, other.primaryContainer),
      primaryDeep: c(primaryDeep, other.primaryDeep),
      onPrimaryContainer: c(onPrimaryContainer, other.onPrimaryContainer),
      primaryFixed: c(primaryFixed, other.primaryFixed),
      primaryFixedDim: c(primaryFixedDim, other.primaryFixedDim),
      secondary: c(secondary, other.secondary),
      onSecondary: c(onSecondary, other.onSecondary),
      secondaryContainer: c(secondaryContainer, other.secondaryContainer),
      tertiary: c(tertiary, other.tertiary),
      onTertiary: c(onTertiary, other.onTertiary),
      tertiaryContainer: c(tertiaryContainer, other.tertiaryContainer),
      tertiaryFixed: c(tertiaryFixed, other.tertiaryFixed),
      tertiaryFixedDim: c(tertiaryFixedDim, other.tertiaryFixedDim),
      onTertiaryFixed: c(onTertiaryFixed, other.onTertiaryFixed),
      heart: c(heart, other.heart),
      error: c(error, other.error),
    );
  }
}

/// `context.colors.surface` のように、テーマ追従の色へ簡潔にアクセスするための
/// 拡張。まだ移行していない画面は引き続き `BloomColors.xxx`（ダーク固定）を
/// 参照してよい。
extension BloomColorsContext on BuildContext {
  BloomColorsExt get colors => Theme.of(this).extension<BloomColorsExt>()!;
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

/// [brightness] 省略時はダーク(既存の見た目のまま)。
/// ライトを渡すと [BloomColorsLight] ベースの `ColorScheme` と
/// `BloomColorsExt.light` が使われる。
ThemeData buildBloomTheme({Brightness brightness = Brightness.dark}) {
  final isDark = brightness == Brightness.dark;
  final colors = isDark ? BloomColorsExt.dark : BloomColorsExt.light;

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: isDark
        ? const ColorScheme.dark(
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
          )
        : const ColorScheme.light(
            primary: BloomColorsLight.primary,
            onPrimary: BloomColorsLight.onPrimary,
            primaryContainer: BloomColorsLight.primaryContainer,
            onPrimaryContainer: BloomColorsLight.onPrimaryContainer,
            secondary: BloomColorsLight.secondary,
            onSecondary: BloomColorsLight.onSecondary,
            secondaryContainer: BloomColorsLight.secondaryContainer,
            tertiary: BloomColorsLight.tertiary,
            onTertiary: BloomColorsLight.onTertiary,
            tertiaryContainer: BloomColorsLight.tertiaryContainer,
            error: BloomColorsLight.error,
            surface: BloomColorsLight.surface,
            onSurface: BloomColorsLight.onSurface,
            onSurfaceVariant: BloomColorsLight.onSurfaceVariant,
            outline: BloomColorsLight.outline,
            outlineVariant: BloomColorsLight.outlineVariant,
            inverseSurface: BloomColorsLight.inverseSurface,
            scrim: BloomColorsLight.scrim,
          ),
    extensions: [colors],
  );

  return base.copyWith(
    scaffoldBackgroundColor: colors.surface,
    splashFactory: InkRipple.splashFactory,
    // 既定の SnackBar は inverseSurface（＝白）になってしまうので背景色に揃える。
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.surfaceContainerHigh,
      contentTextStyle: BloomText.bodyMd.copyWith(color: colors.onSurface),
      actionTextColor: colors.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BloomRadius.md),
      ),
      elevation: 0,
    ),
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
