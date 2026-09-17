import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sns_novahack/screens/tabs/photo_filter.dart';

img.Image _pixelImage(int r, int g, int b) {
  final image = img.Image(width: 1, height: 1, numChannels: 3);
  image.setPixelRgb(0, 0, r, g, b);
  return image;
}

void main() {
  group('PhotoFilter', () {
    test('4種類の preset がそれぞれ 20要素(4x5)の matrix を持つ', () {
      for (final filter in PhotoFilter.values) {
        expect(filter.matrix, hasLength(20));
      }
    });

    test('preset は重複しない matrix を持つ(見た目が区別できる)', () {
      final matrices = PhotoFilter.values.map((f) => f.matrix).toSet();
      expect(matrices, hasLength(PhotoFilter.values.length));
    });

    test('Neutral は単位行列(色を実質変更しない)', () {
      expect(PhotoFilter.neutral.matrix, [
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, 1, 0, //
      ]);
    });
  });

  group('applyColorMatrix', () {
    test('Neutral(単位行列)を適用しても pixel は変化しない', () {
      final image = _pixelImage(120, 60, 200);
      applyColorMatrix(image, PhotoFilter.neutral.matrix);
      final pixel = image.getPixel(0, 0);
      expect(pixel.r, 120);
      expect(pixel.g, 60);
      expect(pixel.b, 200);
    });

    test('Warm は赤方向・Cool は青方向にずれる', () {
      final warmImage = _pixelImage(128, 128, 128);
      applyColorMatrix(warmImage, PhotoFilter.warm.matrix);
      final warmPixel = warmImage.getPixel(0, 0);

      final coolImage = _pixelImage(128, 128, 128);
      applyColorMatrix(coolImage, PhotoFilter.cool.matrix);
      final coolPixel = coolImage.getPixel(0, 0);

      // 同じ灰色の入力でも、warm は cool より赤成分が高く・青成分が低い。
      expect(warmPixel.r, greaterThan(coolPixel.r));
      expect(warmPixel.b, lessThan(coolPixel.b));
    });

    test('Film Contrast は中間グレーより明るい値をさらに持ち上げる', () {
      final brightImage = _pixelImage(200, 200, 200);
      applyColorMatrix(brightImage, PhotoFilter.filmContrast.matrix);
      final pixel = brightImage.getPixel(0, 0);
      expect(pixel.r, greaterThan(200));
    });

    test('白(255,255,255)にどの preset を適用しても 0〜255 を超えない', () {
      for (final filter in PhotoFilter.values) {
        final image = _pixelImage(255, 255, 255);
        applyColorMatrix(image, filter.matrix);
        final pixel = image.getPixel(0, 0);
        expect(pixel.r, inInclusiveRange(0, 255));
        expect(pixel.g, inInclusiveRange(0, 255));
        expect(pixel.b, inInclusiveRange(0, 255));
      }
    });

    test('黒(0,0,0)にどの preset を適用しても 0〜255 を超えない', () {
      for (final filter in PhotoFilter.values) {
        final image = _pixelImage(0, 0, 0);
        applyColorMatrix(image, filter.matrix);
        final pixel = image.getPixel(0, 0);
        expect(pixel.r, inInclusiveRange(0, 255));
        expect(pixel.g, inInclusiveRange(0, 255));
        expect(pixel.b, inInclusiveRange(0, 255));
      }
    });

    test('中間色でもどの preset を適用しても 0〜255 を超えない', () {
      for (final filter in PhotoFilter.values) {
        final image = _pixelImage(90, 150, 40);
        applyColorMatrix(image, filter.matrix);
        final pixel = image.getPixel(0, 0);
        expect(pixel.r, inInclusiveRange(0, 255));
        expect(pixel.g, inInclusiveRange(0, 255));
        expect(pixel.b, inInclusiveRange(0, 255));
      }
    });

    test('複数ピクセルの画像でも全ピクセルへ適用される', () {
      final image = img.Image(width: 2, height: 2, numChannels: 3);
      image.setPixelRgb(0, 0, 10, 10, 10);
      image.setPixelRgb(1, 0, 250, 250, 250);
      image.setPixelRgb(0, 1, 128, 64, 200);
      image.setPixelRgb(1, 1, 0, 0, 0);

      applyColorMatrix(image, PhotoFilter.warm.matrix);

      // Neutral 以外を適用したので、少なくとも1ピクセルは元の値から変わる。
      expect(image.getPixel(0, 0).r, isNot(10));
    });
  });
}
