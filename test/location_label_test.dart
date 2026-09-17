import 'package:flutter_test/flutter_test.dart';
import 'package:sns_novahack/device/location_label.dart';

void main() {
  group('buildAreaLabel', () {
    test('市 + 区 がどちらもあれば両方を返す', () {
      expect(
        buildAreaLabel(
          locality: '大阪市',
          subLocality: '中央区',
          subAdministrativeArea: null,
          administrativeArea: '大阪府',
        ),
        '大阪市 中央区',
      );
    });

    test('区が locality に入っている(東京23区型)場合は単独で返す', () {
      expect(
        buildAreaLabel(
          locality: '渋谷区',
          subLocality: null,
          subAdministrativeArea: null,
          administrativeArea: '東京都',
        ),
        '渋谷区',
      );
    });

    test('locality が無ければ subAdministrativeArea を市相当として使う', () {
      expect(
        buildAreaLabel(
          locality: null,
          subLocality: null,
          subAdministrativeArea: '舞鶴市',
          administrativeArea: '京都府',
        ),
        '舞鶴市',
      );
    });

    test('市区町村レベルの情報が無ければ都道府県だけ返す', () {
      expect(
        buildAreaLabel(
          locality: null,
          subLocality: null,
          subAdministrativeArea: null,
          administrativeArea: '京都府',
        ),
        '京都府',
      );
    });

    test('locality が無くても subAdministrativeArea だけで市相当を返す', () {
      expect(
        buildAreaLabel(
          locality: null,
          subLocality: null,
          subAdministrativeArea: 'Los Angeles County',
          administrativeArea: 'California',
        ),
        'Los Angeles County',
      );
    });

    test('全部空・空白のみなら null(空文字にしない)', () {
      expect(
        buildAreaLabel(
          locality: '',
          subLocality: '   ',
          subAdministrativeArea: null,
          administrativeArea: null,
        ),
        isNull,
      );
    });

    test('city と subLocality が同じ文字列なら重複させない', () {
      expect(
        buildAreaLabel(
          locality: '渋谷区',
          subLocality: '渋谷区',
          subAdministrativeArea: null,
          administrativeArea: '東京都',
        ),
        '渋谷区',
      );
    });

    test('海外の一般的なケースでもクラッシュせず市名を返す', () {
      expect(
        buildAreaLabel(
          locality: 'Los Angeles',
          subLocality: null,
          subAdministrativeArea: 'Los Angeles County',
          administrativeArea: 'California',
        ),
        'Los Angeles',
      );
    });
  });
}
