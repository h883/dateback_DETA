import 'dart:io' show Platform;

import 'package:flutter/rendering.dart' show BoxConstraints, Size;
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
/// ## 訂正の経緯(実機で 180° 反転していた)
///
/// 以前はここで `package:camera` の `camera_preview.dart` 内
/// `_getQuarterTurns()` の対応表(`landscapeLeft -> 3`)をそのまま転用して
/// いたが、実機(Xperia)で確認したところ UI chrome 全体が正解から
/// **180° 反転**していた(quarterTurns 3 と 1 はちょうど 180° 違う)。
///
/// この転用は誤りだった。理由: `camera_preview.dart` の対応表が解いている
/// 問題と、ここで UI chrome について解きたい問題は**似て非なる別の問題**
/// である。
///
/// - `camera_preview.dart` の対応表は「センサーが持つ固定のネイティブ
///   テクスチャを、**window 自体も現在の [DeviceOrientation] へ回転済み**
///   という前提のもとで、その回転済み window 内で正しい向きに見せる」
///   ための回転量(=センサー画像側の補正)。
/// - このアプリで解きたいのは「**window は portrait 固定のまま一切回転
///   しない**のに、ユーザーだけが物理的に [DeviceTilt] ぶん端末を回転させて
///   構えている」ときに、portrait 前提で描いた UI を**その人間から見て
///   正立させる**という、window 側は動かない別の補正。
///
/// 後者を正しく導出するには、camera プラグインの表を借りずに物理的な
/// 回転から直接考える必要がある。
///
/// ## 正しい導出
///
/// [TiltWatcher] のコメント、および Flutter 本体の `DeviceOrientation`
/// enum の doc comment(`package:flutter/src/services/system_chrome.dart`)
/// はどちらも、`landscapeShutterRight`/`landscapeLeft` を
/// 「portraitUp から**反時計回り(counterclockwise)90°**」という同じ
/// 物理的な回転方向で説明している(名前の Left/Right ではなく、この
/// 回転方向の記述の一致で対応を決めている点は [captureOrientationForTilt]
/// と同じ)。
///
/// 端末が物理的に反時計回り θ だけ回転すると、window に描かれている
/// (window 自体は回転しない)内容は、端末に固定されたまま一緒に運ばれる
/// ため、ユーザーから見ると同じ θ だけ反時計回りに傾いて見える。これを
/// 打ち消して正立させるには、window の描画内容自体を**あらかじめ時計回り
/// に θ だけ**回しておけばよい(時計回り θ + 反時計回り θ = 差し引き0)。
///
/// [RotatedBox.quarterTurns] は Flutter 本体のドキュメントで
/// 「The number of **clockwise** quarter turns」と明記されている
/// (`package:flutter/src/widgets/basic.dart` で確認済み)。よって
/// 「物理的な反時計回り θ」を打ち消す `quarterTurns` は、**同じ回転量を
/// そのまま時計回りの quarterTurns として使えばよい**:
///
/// ```
/// portraitUp     (回転  0°) -> quarterTurns 0
/// landscapeLeft  (回転 90°反時計回り) -> quarterTurns 1
/// portraitDown   (回転180°)          -> quarterTurns 2
/// landscapeRight (回転270°反時計回り=90°時計回り) -> quarterTurns 3
/// ```
///
/// これは `camera_preview.dart` の対応表(0,1,2,3 の並びが
/// portraitUp,landscapeRight,portraitDown,landscapeLeft)を
/// landscapeLeft/landscapeRight についてだけ入れ替えた、いわば
/// **逆回転の表**になる(0°/180° は自分自身が逆回転でもあるため変わらない)。
/// 上記の物理的な導出と、実機で quarterTurns=1 が正解だったという結果は
/// 一致する。
///
/// この関数は [captureOrientationForTilt] の結果(=どちらが landscapeLeft
/// かという判定)は一切変更せず、そこから先の「UI chrome 用の回転量」だけを
/// 独自に(camera プラグインの表を借りずに)導出する。
///
/// null(手動 entry、または tilt-to-camera の対象外の向き)のときは 0
/// (=無回転、既存の portrait UI のまま)を返す。
int uiQuarterTurnsForTilt(DeviceTilt? tilt) {
  if (tilt == null) return 0;
  return switch (captureOrientationForTilt(tilt)) {
    DeviceOrientation.landscapeLeft => 1,
    DeviceOrientation.portraitDown => 2,
    DeviceOrientation.landscapeRight => 3,
    DeviceOrientation.portraitUp || null => 0,
  };
}

/// tilt-to-camera 中の Camera preview frame の**論理**(=portrait window
/// 座標系での、無回転の)サイズを、利用可能な論理領域(chrome 用の領域を
/// 差し引いた後の [constraints])から計算する、副作用の無い純粋関数。
///
/// window 自体は portrait 固定のまま回転しないが、ユーザーは端末を
/// 物理的に90°傾けて構えているため、window の論理 width は物理的な
/// (ユーザーから見た)高さに、論理 height は物理的な幅に対応する
/// (90°傾けると width/height の対応が入れ替わって知覚されるため)。
///
/// 撮影 frame はユーザーから見て [physicalAspect](既定 3:2、横長)で
/// 見える必要があるため、論理座標上では **その逆比(既定 2:3、縦長)** の
/// box として配置する。物理的な短辺(縦長 box の論理 width 側)を利用可能な
/// 論理 width いっぱいに合わせ、長辺(論理 height 側)は
/// `height = width * physicalAspect` で自動的に決める。
///
/// [constraints] に収まらない(=どちらかの軸で overflow する)場合は、
/// 収まる側を基準に縮小し、常に [constraints] 以内(かつ [physicalAspect]
/// の逆比を保った)最大サイズを返す。
Size tiltPreviewFrameLogicalSize(
  BoxConstraints constraints, {
  double physicalAspect = 3 / 2,
}) {
  final maxW = constraints.maxWidth;
  final maxH = constraints.maxHeight;
  var width = maxW;
  var height = width * physicalAspect;
  if (height > maxH) {
    height = maxH;
    width = height / physicalAspect;
  }
  return Size(width, height);
}

/// [DeviceTilt] から、Camera **preview の映像内容そのもの**(live
/// CameraPreview・35mm 撮影後の静止画プレビュー・8mm 再生プレビュー)に
/// 追加でかける表示専用の回転量を返す、副作用の無い純粋関数。
///
/// ## [uiQuarterTurnsForTilt] とは別の目的
///
/// - [uiQuarterTurnsForTilt] は **UI chrome**(tools・shutter・overlay
///   等)を正立させるための回転量。3:2 frame 自体や `CameraController` の
///   capture orientation とは無関係。
/// - この関数は **frame の中に映る映像ピクセルだけ**を追加で回すための
///   回転量。frame 自体の位置・サイズ・比率([tiltPreviewFrameLogicalSize]
///   が計算する 2:3 論理 box)には一切影響しない。
///
/// 両者はたまたま現在同じ値(1)になっているが、解いている問題が違うため
/// 意図的に別関数に分けている。将来どちらか一方だけを直す必要が出ても、
/// もう一方へ影響しない。
///
/// ## 値の根拠
///
/// `CameraPreview` 自体は `lockCaptureOrientation(DeviceOrientation.
/// landscapeLeft)`(`captureOrientationForTilt` 参照、変更禁止)により
/// 正しい向き・比率を自己申告してくるはずだが、実機(Xperia)で確認した
/// ところ、3:2 frame 自体(位置・サイズ・比率)は正しいのに、その中の
/// 映像内容だけが90°ズレて見えることが分かった。実機で「時計回りに90°
/// 回転させれば正しい向きになる」ことを確認済みのため、
/// `landscapeShutterRight` では `quarterTurns = 1`(時計回り90°、
/// [RotatedBox.quarterTurns] の doc comment 参照)を返す。
///
/// capture 側([captureOrientationForTilt]/`lockCaptureOrientation`)は
/// この関数からは一切参照・変更しない。あくまで Flutter 側の表示レイヤー
/// だけの補正であり、CameraX 側の capture/recording orientation とは
/// 混同しない。
///
/// null(手動 entry)・[DeviceTilt.portrait]・[DeviceTilt.landscapeOther]
/// では 0(無回転)を返す。
///
/// ## iOS では補正しない
///
/// この quarterTurns=1 の補正値は Android 実機(Xperia、`camera` パッケージの
/// iOS/Android 双方で共有される `camera_android_camerax` 実装)で確認された
/// 「`lockCaptureOrientation` 済みのはずなのに映像内容だけ90°ズレる」という
/// **CameraX 固有の描画クセ**を打ち消すためのものであり、物理法則から導いた
/// 値ではない(この点は関数コメント冒頭に明記されている通り)。
///
/// iOS では `camera` パッケージが `camera_avfoundation` 実装に切り替わり、
/// AVFoundation の `AVCaptureVideoPreviewLayer` は `lockCaptureOrientation`
/// が指定した向きへ自前で正しく映像を回転させるため、CameraX と同じズレは
/// 起きない。CameraX 用の補正をそのまま iOS にも適用すると、既に正しい映像に
/// 追加で90°回してしまい、かえって誤った向きになる。そのため iOS では常に
/// 0(無回転)を返す。
int previewQuarterTurnsForTilt(DeviceTilt? tilt) {
  if (tilt == null || Platform.isIOS) return 0;
  return switch (tilt) {
    DeviceTilt.landscapeShutterRight => 1,
    DeviceTilt.landscapeOther || DeviceTilt.portrait => 0,
  };
}
