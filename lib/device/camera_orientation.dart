import 'package:flutter/services.dart' show DeviceOrientation;

import 'tilt_watcher.dart';

/// tilt-to-camera で実際に検知した [DeviceTilt] から、
/// [CameraController.lockCaptureOrientation]（`package:camera`）へ渡すべき
/// [DeviceOrientation] を決める、副作用の無い純粋関数。
///
/// ## 対応根拠(名前だけで推測していない)
///
/// Flutter 本体の `DeviceOrientation` enum の doc comment
/// (`package:flutter/src/services/system_chrome.dart`)には次のように
/// 明記されている:
///
/// > As you rotate the device by 90 degrees in a counter-clockwise
/// > direction around the axis that pierces the screen, you step through
/// > each value in this enum in the order given.
/// > (portraitUp, landscapeLeft, portraitDown, landscapeRight の順)
/// >
/// > landscapeLeft: The orientation that is 90 degrees counterclockwise
/// > from portraitUp.
///
/// つまり **portraitUp から反時計回り(counterclockwise)に90°** 回した
/// 状態が `landscapeLeft` である、と Flutter 自身のソースが定義している。
///
/// [TiltWatcher] のドキュメントコメントは `landscapeShutterRight` を
/// 「端末上部を左へ倒す＝**反時計回り90°**、シャッターが右側に来る向き」と
/// 説明しており、これは Flutter の `landscapeLeft` の定義と**回転方向が
/// 完全に一致する**(どちらも「portraitUp から反時計回り90°」を指している)。
///
/// `landscapeShutterRight` の "Right" はシャッターボタンが来る側(持ち手の
/// 都合による命名)であり、Flutter の `landscapeLeft`/`landscapeRight` の
/// "Left"/"Right" は回転方向による命名で、**互いに無関係な別軸の命名**。
/// 名前の字面だけで対応させると `landscapeShutterRight` →
/// `DeviceOrientation.landscapeRight` と誤読しやすいため、今回は両者の
/// ドキュメントに書かれた回転方向の記述を直接突き合わせてこの対応を決めた。
///
/// ## front/back camera について
///
/// この対応表はカメラの前後(`CameraLensDirection`)を入力に取らない。
/// [DeviceOrientation] は「端末を物理的にどう構えているか」を表す値であり、
/// レンズの向きとは独立している。前後カメラの `sensorOrientation` の差
/// (一般に背面90°・前面270°など)や、前面カメラの鏡像処理は
/// `camera_android_camerax` プラグイン内部
/// (`ImageReaderRotatedPreview.frontFacingCamera`/`backFacingCamera` が
/// `sensorOrientationDegrees`・`cameraIsFrontFacing` を別途受け取っている)
/// で既に吸収されるため、アプリ側で `lensDirection` ごとに異なる
/// [DeviceOrientation] を渡す必要は無い。
///
/// ## landscapeOther / portrait
///
/// [DeviceTilt.landscapeOther](逆向きの傾き)と [DeviceTilt.portrait] は
/// tilt-to-camera の自動起動対象そのものではない
/// ([MainShell] 側で `landscapeOther` は無視され、`portrait` では
/// そもそも Camera を開かない)。ここでは意図的に `null` を返し、
/// 呼び出し側が「この2つでは capture orientation を lock しない」ことを
/// 型で保証できるようにする。
DeviceOrientation? captureOrientationForTilt(DeviceTilt tilt) {
  switch (tilt) {
    case DeviceTilt.landscapeShutterRight:
      return DeviceOrientation.landscapeLeft;
    case DeviceTilt.landscapeOther:
    case DeviceTilt.portrait:
      return null;
  }
}

/// [DeviceTilt] から、Camera 画面の **UI chrome**(戻るボタン・シャッター・
/// 35mm/8mm セレクター・flash・camera switch・timer・filter dots・
/// date stamp・下書き導線・撮影確認 UI 等。CameraPreview の映像そのものは
/// 含まない)を [RotatedBox] で正立させるための `quarterTurns` を返す、
/// 副作用の無い純粋関数。
///
/// ## なぜ [captureOrientationForTilt] と同じ値を再利用してよいか
///
/// `package:camera` の `camera_preview.dart`(`CameraPreview._getQuarterTurns`)
/// は、[DeviceOrientation] から `RotatedBox` の `quarterTurns` への対応を
/// 次の表で持っている(pub cache 内の camera-0.12.1 のソースで確認済み):
///
/// ```
/// portraitUp     -> 0
/// landscapeRight -> 1
/// portraitDown   -> 2
/// landscapeLeft  -> 3
/// ```
///
/// これは「センサーのネイティブ(portrait 前提)テクスチャを、実際に
/// 端末を構えている向きへ正しく見せるための回転量」であり、まさに今回
/// 解決したい問題(「portrait 前提で組まれたコンテンツを、実際の物理的な
/// 傾きに合わせて正立させる」)と同じ構造の変換である。このアプリの UI
/// chrome も同じく portrait 前提で組まれたレイアウトなので、同じ対応表を
/// 転用できる。実際に `DeviceOrientation.landscapeLeft` + `quarterTurns: 3`
/// の組み合わせは、今回の tilt-to-camera 修正で CameraPreview 側が既に
/// 実機(Xperia)で正しく動作することを確認済み
/// (`entry=tilt tilt=DeviceTilt.landscapeShutterRight
/// lockedCaptureOrientation=DeviceOrientation.landscapeLeft` のログ、かつ
/// 「Camera preview自体は正しい向きになりました」との実機報告)。
///
/// この関数は [captureOrientationForTilt] の結果を経由してこの対応表を
/// 適用するだけで、tilt → DeviceOrientation の判定ロジック自体
/// (どちらが landscapeLeft か)は一切変更しない
/// ([captureOrientationForTilt] のコメント参照)。
///
/// null(手動 entry、または tilt-to-camera の対象外の向き)のときは 0
/// (=無回転、既存の portrait UI のまま)を返す。
int uiQuarterTurnsForTilt(DeviceTilt? tilt) {
  if (tilt == null) return 0;
  return switch (captureOrientationForTilt(tilt)) {
    DeviceOrientation.landscapeRight => 1,
    DeviceOrientation.portraitDown => 2,
    DeviceOrientation.landscapeLeft => 3,
    DeviceOrientation.portraitUp || null => 0,
  };
}
