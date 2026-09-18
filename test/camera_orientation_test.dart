import 'package:flutter/rendering.dart' show BoxConstraints;
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
        'landscapeShutterRight は quarterTurns=1 '
        '(実機確認により修正済み: 以前の quarterTurns=3 は Camera preview'
        'のセンサー画像補正用の対応表を誤って転用したもので、実機で180°'
        '反転していた。RotatedBox.quarterTurns は "clockwise" ('
        'package:flutter/src/widgets/basic.dart のdoc comment)であり、'
        'portraitUp から反時計回り90°という物理回転を打ち消すには同じ'
        '90°ぶんの時計回り=quarterTurns:1が正しい)', () {
      expect(uiQuarterTurnsForTilt(DeviceTilt.landscapeShutterRight), 1);
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

  group('tiltPreviewFrameLogicalSize', () {
    test('論理 aspect は物理 3:2 の逆比(2:3、縦長)になる', () {
      // 十分に高さが余っている(width 側で頭打ちになる)ケース。
      final size = tiltPreviewFrameLogicalSize(
        const BoxConstraints(maxWidth: 400, maxHeight: 10000),
      );
      expect(size.width, 400);
      expect(size.height, closeTo(600, 0.001)); // 400 * 3/2
      // width:height = 400:600 = 2:3 (物理的には 600:400 = 3:2 に見える)。
      expect(size.width / size.height, closeTo(2 / 3, 0.0001));
    });

    test('短辺(物理2側=論理width)を利用可能な高さいっぱいに合わせる', () {
      final size = tiltPreviewFrameLogicalSize(
        const BoxConstraints(maxWidth: 1080, maxHeight: 2238),
      );
      // 1080 * 1.5 = 1620 <= 2238 なので width 側で頭打ちになり、
      // 論理 width がそのまま最大化される(=物理的な短辺が画面高いっぱい)。
      expect(size.width, 1080);
      expect(size.height, closeTo(1620, 0.001));
    });

    test('frame は利用可能な constraints を超えない(高さが足りない場合は縮小)', () {
      // width=400 のまま height=600 にすると overflow するケース
      // (利用可能な高さが 500 しかない)。
      final size = tiltPreviewFrameLogicalSize(
        const BoxConstraints(maxWidth: 400, maxHeight: 500),
      );
      expect(size.width, lessThanOrEqualTo(400));
      expect(size.height, lessThanOrEqualTo(500));
      expect(size.height, closeTo(500, 0.001));
      expect(size.width, closeTo(500 * 2 / 3, 0.001));
      expect(size.width / size.height, closeTo(2 / 3, 0.0001));
    });

    test('physicalAspect を指定すればその逆比の論理サイズになる(汎用性の確認)', () {
      final size = tiltPreviewFrameLogicalSize(
        const BoxConstraints(maxWidth: 100, maxHeight: 10000),
        physicalAspect: 4 / 3,
      );
      expect(size.width, 100);
      expect(size.height, closeTo(100 * 4 / 3, 0.001));
    });
  });

  group('previewQuarterTurnsForTilt', () {
    test(
        'landscapeShutterRight は quarterTurns=1 '
        '(uiQuarterTurnsForTilt とは別目的: frame 自体ではなく、実機で'
        '確認された「frame は正しいが中の映像内容だけ90°ズレる」問題への'
        '表示専用の補正。値がたまたま uiQuarterTurnsForTilt と同じ1でも、'
        'それぞれ独立に導出・変更できることをこの別関数で保証する)', () {
      expect(previewQuarterTurnsForTilt(DeviceTilt.landscapeShutterRight), 1);
    });

    test('portrait のときは quarterTurns=0(映像内容を回転しない)', () {
      expect(previewQuarterTurnsForTilt(DeviceTilt.portrait), 0);
    });

    test('landscapeOther のときは quarterTurns=0', () {
      expect(previewQuarterTurnsForTilt(DeviceTilt.landscapeOther), 0);
    });

    test('null(手動 entry)のときは quarterTurns=0', () {
      expect(previewQuarterTurnsForTilt(null), 0);
    });
  });
}
