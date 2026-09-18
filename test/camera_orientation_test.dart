import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sns_novahack/device/camera_orientation.dart';
import 'package:sns_novahack/device/tilt_watcher.dart';

void main() {
  group('captureOrientationForTilt', () {
    test(
        'landscapeShutterRight(端末上部を左へ倒す=反時計回り90°)は '
        'DeviceOrientation.landscapeLeft に対応する '
        '(Flutter の DeviceOrientation doc: landscapeLeft は '
        'portraitUp から反時計回り90°、という回転方向の一致で決めた対応。'
        '名前の Left/Right だけで揃えたものではない)', () {
      expect(
        captureOrientationForTilt(DeviceTilt.landscapeShutterRight),
        DeviceOrientation.landscapeLeft,
      );
    });

    test('landscapeOther(逆向き)は自動 Camera 用の orientation lock に使わない', () {
      expect(captureOrientationForTilt(DeviceTilt.landscapeOther), isNull);
    });

    test('portrait のときは landscape lock しない', () {
      expect(captureOrientationForTilt(DeviceTilt.portrait), isNull);
    });

    // front/back camera(CameraLensDirection)を入力に取らない設計。
    // DeviceOrientation は「端末を物理的にどう構えているか」を表す値で
    // あり、レンズの向きとは独立している。前後カメラのセンサー角度差や
    // 前面カメラの鏡像処理は camera_android_camerax プラグイン内部
    // (ImageReaderRotatedPreview.frontFacingCamera/backFacingCamera)で
    // 既に吸収されるため、ここで lensDirection ごとに mapping を
    // 分ける必要は無い(camera_orientation.dart のコメント参照)。
  });

  group('uiQuarterTurnsForTilt', () {
    test(
        'landscapeShutterRight は quarterTurns=3 '
        '(package:camera の camera_preview.dart 内 _getQuarterTurns() の '
        'landscapeLeft -> 3 という対応表を、同じ portrait 前提レイアウトの '
        'UI chrome にもそのまま転用したもの。実機で CameraPreview 側の '
        'landscapeLeft ロックが既に正しく動くことを確認済み)', () {
      expect(uiQuarterTurnsForTilt(DeviceTilt.landscapeShutterRight), 3);
    });

    test('portrait のときは quarterTurns=0(UI を回転しない)', () {
      expect(uiQuarterTurnsForTilt(DeviceTilt.portrait), 0);
    });

    test('null(手動 entry)のときは quarterTurns=0', () {
      expect(uiQuarterTurnsForTilt(null), 0);
    });

    test('landscapeOther(tilt-to-camera の自動起動対象外)は quarterTurns=0', () {
      expect(uiQuarterTurnsForTilt(DeviceTilt.landscapeOther), 0);
    });

    // PostTab._cameraStage は「quarterTurns == 0 なら既存 portrait レイアウト、
    // それ以外なら回転済み tilt レイアウト」という1行の分岐だけでラッパーを
    // 選ぶ(lib/screens/tabs/post_tab.dart の _cameraStage 参照)。その分岐を
    // 実際に左右するのはこの関数の戻り値そのものであり、CameraController
    // 等の実機カメラを起動しなくても、上記のテストで
    // 「tilt entry(landscapeShutterRight)では回転 wrapper が選ばれ、
    // manual entry(null)/portrait/landscapeOther では選ばれない」ことを
    // 直接検証できている。
  });
}
