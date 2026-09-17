import 'package:image/image.dart' as img;

/// 35mm撮影の色調フィルター(v15 の「35mm filter swipe」)。8mm には適用しない。
///
/// 各フィルターは 4x5(20要素)の color matrix を1つだけ持つ。これは
/// Flutter の `ColorFilter.matrix` と全く同じ並び・スケール(0-255)の
/// 数値で、
/// - ライブプレビューは Flutter 側でこの matrix をそのまま
///   `ColorFilter.matrix(matrix)` として適用し、
/// - 保存する JPEG は [applyColorMatrix] で同じ matrix の値をピクセルへ
///   直接書き込む
/// ことで、プレビューと実際に投稿される画像の見た目を一致させる。
///
/// [label] は内部識別用の名前であり、Camera の UI には一切表示しない
/// (仕様どおり、フィルター名のテキストは出さない)。
enum PhotoFilter {
  neutral('Neutral', _neutralMatrix),
  warm('Warm', _warmMatrix),
  cool('Cool', _coolMatrix),
  filmContrast('Film Contrast', _filmContrastMatrix);

  const PhotoFilter(this.label, this.matrix);

  final String label;

  /// 4x5(20要素)の color matrix。0-255 スケール。
  final List<double> matrix;
}

const _neutralMatrix = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0, //
];

// やや暖色・柔らかめ: 彩度をごくわずかに落として柔らかい印象にしつつ、
// 赤をわずかに持ち上げ・青をわずかに落として暖色寄りにする。
// (彩度 90% への desaturate 行列 + 弱いオフセット)
const _warmMatrix = <double>[
  0.9213, 0.0715, 0.0072, 0, 6, //
  0.0213, 0.9715, 0.0072, 0, 1, //
  0.0213, 0.0715, 0.9072, 0, -6, //
  0, 0, 0, 1, 0, //
];

// やや寒色・低彩度: 彩度を 85% へ落とし、青を持ち上げ・赤を落として
// 寒色寄りにする。
const _coolMatrix = <double>[
  0.88195, 0.10725, 0.0108, 0, -4, //
  0.03195, 0.95725, 0.0108, 0, 0, //
  0.03195, 0.10725, 0.8608, 0, 6, //
  0, 0, 0, 1, 0, //
];

// 少しcontrastを持たせたfilm風: 色味は変えず、コントラストだけを
// 12%ほど強める((x-128)*1.12+128 と同じ式を係数+オフセットで表現)。
const _filmContrastMatrix = <double>[
  1.12, 0, 0, 0, -15.36, //
  0, 1.12, 0, 0, -15.36, //
  0, 0, 1.12, 0, -15.36, //
  0, 0, 0, 1, 0, //
];

/// [matrix] を [image] の各ピクセルへ直接適用する(in place)。
/// アルファは扱わない(すべての preset で恒等のため)。
///
/// カメラ・Flutter widget に依存しない純粋な関数なので、
/// プラットフォームカメラ無しで unit test できる。
void applyColorMatrix(img.Image image, List<double> matrix) {
  assert(matrix.length == 20, 'color matrix must have 20 elements');
  for (final pixel in image) {
    final r = pixel.r.toDouble();
    final g = pixel.g.toDouble();
    final b = pixel.b.toDouble();
    final a = pixel.a.toDouble();
    pixel
      ..r = _clamp255(
          matrix[0] * r + matrix[1] * g + matrix[2] * b + matrix[3] * a + matrix[4])
      ..g = _clamp255(
          matrix[5] * r + matrix[6] * g + matrix[7] * b + matrix[8] * a + matrix[9])
      ..b = _clamp255(matrix[10] * r +
          matrix[11] * g +
          matrix[12] * b +
          matrix[13] * a +
          matrix[14]);
  }
}

double _clamp255(double v) => v.clamp(0, 255).toDouble();
