import 'package:flutter_test/flutter_test.dart';
import 'package:sns_novahack/device/app_permissions.dart';

void main() {
  group('lampStateFor', () {
    test('Granted なら常に green', () {
      expect(
        lampStateFor(granted: true, permanentlyDenied: false, requestedOnce: false),
        LampState.green,
      );
      expect(
        lampStateFor(granted: true, permanentlyDenied: true, requestedOnce: true),
        LampState.green,
      );
    });

    test('まだ一度も要求していない denied は gray(未許可 / 未要求)', () {
      expect(
        lampStateFor(granted: false, permanentlyDenied: false, requestedOnce: false),
        LampState.gray,
      );
    });

    test('要求済みで denied なら warn', () {
      expect(
        lampStateFor(granted: false, permanentlyDenied: false, requestedOnce: true),
        LampState.warn,
      );
    });

    test('恒久的に拒否(permanentlyDenied)なら要求歴に関係なく warn', () {
      expect(
        lampStateFor(granted: false, permanentlyDenied: true, requestedOnce: false),
        LampState.warn,
      );
    });
  });
}
