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
}
