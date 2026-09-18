import 'package:flutter_test/flutter_test.dart';
import 'package:sns_novahack/models/models.dart';
import 'package:sns_novahack/screens/tabs/post_tab.dart';

void main() {
  group('showDatebackForMode', () {
    test('35mm では dateback の日付を表示する', () {
      expect(showDatebackForMode(PostKind.film35mm), isTrue);
    });

    test('8mm では dateback の日付を表示しない', () {
      expect(showDatebackForMode(PostKind.film8mm), isFalse);
    });
  });

  group('showFilmGateForMode', () {
    test('8mm ではフィルムゲートを表示する', () {
      expect(showFilmGateForMode(PostKind.film8mm), isTrue);
    });

    test('35mm ではフィルムゲートを表示しない', () {
      expect(showFilmGateForMode(PostKind.film35mm), isFalse);
    });
  });
}
