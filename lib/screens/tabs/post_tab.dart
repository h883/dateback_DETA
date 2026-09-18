import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute, debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../../api/bloom_api.dart';
import '../../device/app_permissions.dart';
import '../../device/camera_orientation.dart';
import '../../device/tilt_watcher.dart' show DeviceTilt;
import '../../drafts/draft_store.dart';
import '../../models/models.dart';
import '../../theme/bloom_theme.dart';
import '../../widgets/film_effects.dart';
import '../drafts_sheet.dart';
import 'photo_filter.dart';

/// 投稿処理の結果。MainShell はこれを見て Home への遷移・成功/失敗の
/// バナー表示・(失敗時の)再試行/下書き保存を行う。
///
/// PostTab は「アップロードを試みた結果」を渡すところまでが責務で、
/// 成功後のビューアー導線や失敗後の再試行・下書き保存は MainShell 側
/// (Phase 6)で扱う。
sealed class PostOutcome {
  const PostOutcome();
}

class PostSuccess extends PostOutcome {
  const PostSuccess();
}

class PostFailure extends PostOutcome {
  const PostFailure({
    required this.bytes,
    required this.kind,
    required this.contentType,
    this.locationLabel,
  });

  /// 失敗したメディアそのもの。再試行・下書き保存にそのまま使う。
  final Uint8List bytes;
  final PostKind kind;
  final String contentType;

  /// 撮影時に取得済みの撮影地(B2)。再試行・下書き保存では位置を
  /// 取り直さず、これをそのまま使う。
  final String? locationLabel;
}

/// 撮影フレームの縦横比。ユーザーが見ている範囲と投稿される範囲を一致させる
/// ため、静止画はこの比率へ中央切り出しする([_cropAndFilterTo3x2])。
///
/// 動画については camera プラグインに「3:2 で録画ファイルそのものを書き出す」
/// 手段が無く、切り出しには動画の再エンコードが要る(=重い native/FFmpeg
/// 依存が要る)。それは今回追加しない方針のため、動画はプレビューの見た目
/// だけをこの比率に合わせ、実際に保存されるファイルはセンサーのネイティブ
/// 比率のまま(Phase 7 の制約として報告する)。
const _targetAspect = 3 / 2;

/// dateback の日付表示(いわゆる dateback スタンプ)は 35mm のときだけ。
/// 8mm では表示しない。副作用の無い純粋関数(widget test 用)。
bool showDatebackForMode(PostKind mode) => mode == PostKind.film35mm;

/// 8mm のフィルムゲート表現([Film8mmEffects])は 8mm のときだけ。
/// 35mm では表示しない。副作用の無い純粋関数(widget test 用)。
bool showFilmGateForMode(PostKind mode) => mode == PostKind.film8mm;

/// [_cropAndFilterTo3x2] へ渡す引数。[compute] は引数を1つしか渡せないため
/// まとめておく。
class _CropAndFilterParams {
  const _CropAndFilterParams(this.jpegBytes, this.filterMatrix);

  final Uint8List jpegBytes;

  /// シャッターが切られた瞬間に選択されていた [PhotoFilter.matrix]
  /// (v15 の35mm filter swipe)。呼び出し側で確定させてから渡すことで、
  /// 処理中にユーザーがフィルターを変えても結果へ混ざらないようにする。
  final List<double> filterMatrix;
}

/// 撮影した静止画を中央から 3:2 へ切り出し、選択中の35mmフィルターを
/// 焼き込む。[compute] で別 isolate で実行するためのトップレベル関数。
///
/// ライブプレビューは Flutter の `ColorFilter.matrix` で同じ matrix を
/// 見せているだけなので、ここで実際のピクセルへ同じ値を適用することで、
/// プレビューと投稿される JPEG の見た目を一致させる([applyColorMatrix])。
Uint8List _cropAndFilterTo3x2(_CropAndFilterParams params) {
  final decoded = img.decodeImage(params.jpegBytes);
  if (decoded == null) return params.jpegBytes;
  // EXIF の回転情報をピクセルへ焼き込んでから切り出す
  // (焼き込まないと端末によっては横倒しのまま切り出してしまう)。
  final oriented = img.bakeOrientation(decoded);

  final w = oriented.width;
  final h = oriented.height;
  var cropW = w;
  var cropH = h;
  if (w / h > _targetAspect) {
    cropW = (h * _targetAspect).round();
  } else {
    cropH = (w / _targetAspect).round();
  }
  final x = ((w - cropW) / 2).round();
  final y = ((h - cropH) / 2).round();
  final cropped =
      img.copyCrop(oriented, x: x, y: y, width: cropW, height: cropH);
  applyColorMatrix(cropped, params.filterMatrix);
  return img.encodeJpg(cropped, quality: 92);
}

/// 投稿画面(仕様書 11)。
///
/// 35mm は静止画、8mm は2秒の動画。
/// アプリは縦画面固定なので、この画面も縦で表示する。
/// 端末を横に倒すとここへ来る導線は MainShell が持っている。
///
/// Camera permission は Consent/Permission 画面でのみ要求する。この画面は
/// 現況を読む([AppPermissions])だけで、Granted かつ [PostTab.active] に
/// なって初めて [CameraController] を作る(lazy-init)。Denied のときは
/// [CameraController.initialize] を一切呼ばない(camera プラグイン自身が
/// 内部で OS permission dialog を出すのを防ぐため)。
///
/// アプリ全体を portrait 固定にしたまま端末を物理的に横へ倒して使う
/// tilt-to-camera の都合上、OS/Flutter の window 自体は回転しない。この
/// ままだと camera プラグイン(`camera_android_camerax`)の orientation
/// 判定が Window 回転(常に portrait)を基準にしてしまい、実際の物理的な
/// 傾きと噛み合わずプレビュー・撮影結果が約90°ズレる。これを避けるため、
/// tilt 経由で開いた場合([PostTab.activeTilt] が非null)だけ
/// `CameraController.lockCaptureOrientation` で明示的に
/// [DeviceOrientation] を固定する([captureOrientationForTilt] 参照)。
/// 手動で開いた場合は何もせず、既存の(lock しない)挙動のまま。
class PostTab extends StatefulWidget {
  const PostTab({
    super.key,
    required this.api,
    required this.onPostResult,
    required this.onHome,
    required this.onBusyChanged,
    required this.onCaptureLocation,
    required this.active,
    required this.onFilterGestureActive,
    required this.activeTilt,
  });

  final BloomApi api;

  /// 投稿の成功・失敗を MainShell へ伝える。成功/失敗どちらでも
  /// このあと MainShell が Home へ戻す(中間確認画面は挟まない)。
  final void Function(PostOutcome outcome) onPostResult;

  /// 右上の Home ボタン。v15 は Camera に portrait 用ヘッダーを持たず、
  /// カメラ右レール上部の Home アイコンだけで戻れる。
  final VoidCallback onHome;

  /// 撮影確認中・投稿処理中・セルフタイマー中かどうかを MainShell に伝える。
  /// 縦へ戻ったときに Camera を閉じてよいかの判断に使われる。
  final void Function(bool busy) onBusyChanged;

  /// 撮影地(粗いエリア名)の取得(B2)。ON/OFF の判断([SettingsStore.
  /// autoLocationEnabled])は呼び出し元(MainShell)が持ち、この callback
  /// 自体は「呼ばれたら試みる」だけ。OFF のときは呼び出し元が最初から
  /// `Future.value(null)` を返すので、ここでは何も分岐しない。
  final Future<String?> Function() onCaptureLocation;

  /// Camera タブが現在表示中かどうか(MainShell の現在タブを反映するだけの
  /// 単純な bool)。下書き件数を「Camera 再表示」のタイミングで読み直す
  /// ためだけに使う。
  final bool active;

  /// 35mm フィルタースワイプ中かどうかを MainShell へ伝える。MainShell は
  /// これを見て、その間だけ PageView(Camera ← Home → Profile)の横スワイプ
  /// navigation を止める(既存のタブ切替ジェスチャーと衝突させないため)。
  final void Function(bool active) onFilterGestureActive;

  /// tilt-to-camera によって自動的に Camera が開かれた場合の、その時点の
  /// [DeviceTilt]。右フリック・ボトムナビ等の**手動**操作で開いた場合は
  /// 必ず null(MainShell 側で区別済み)。
  ///
  /// 非null のときだけ [captureOrientationForTilt] で
  /// [DeviceOrientation] を求め、`CameraController.lockCaptureOrientation`
  /// を適用する。手動で開いた場合(null)は、この画面はこれまでどおり
  /// camera プラグインの既定の(lock しない)orientation 処理に任せる。
  final DeviceTilt? activeTilt;

  @override
  State<PostTab> createState() => _PostTabState();
}

class _PostTabState extends State<PostTab> with WidgetsBindingObserver {
  static const _recordDuration = Duration(seconds: 2);

  /// OFF / 3秒 / 10秒。
  static const _timerChoices = <int>[0, 3, 10];

  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  String? _cameraError;

  /// null = まだ確認していない。実際の OS permission status が
  /// source of truth(Consent 画面で許可した想定でも、ここで必ず読み直す)。
  /// Granted でない限り [CameraController.initialize] は絶対に呼ばない
  /// (=camera プラグインが内部で OS permission dialog を出すのを防ぐ)。
  bool? _cameraPermissionGranted;

  /// 初期化中の多重起動を防ぐ。回転のたびに resumed が来るため。
  bool _settingUp = false;

  /// 前後カメラ切替の連打・競合を防ぐ。
  bool _switchingCamera = false;

  PostKind _mode = PostKind.film35mm;
  bool _recording = false;
  bool _uploading = false;

  /// takePicture() 呼び出しからバイト列を受け取るまでの間だけ true。
  bool _capturing = false;

  /// 撮影直後、静止画を 3:2 へ切り出している間だけ true。
  bool _cropping = false;

  /// 撮影済みの一枚(または2秒)。投稿するまで保持する。
  Uint8List? _captured;
  String? _capturedContentType;
  Uint8List? _stillPreview;

  /// 撮影した瞬間(シャッターが切られたタイミング)にだけ取得を試みる
  /// 撮影地(B2)。カメラを開いただけでは開始しない。投稿・下書き保存の
  /// タイミングでこれを待つ。
  Future<String?>? _locationFuture;

  /// Camera の下書きアイコンに出す件数。0件なら [_leftTools] 側で
  /// アイコン自体を出さない。
  int _draftCount = 0;

  /// 35mm 撮影の色調フィルター(v15 の filter swipe)。8mm には使わない。
  /// 永続化はしない(Camera を作り直せば Neutral に戻る程度で十分)。
  PhotoFilter _filter = PhotoFilter.neutral;

  /// フィルタースワイプの累積移動量(手動 entry は横方向 dx、tilt entry は
  /// 縦方向 dy を蓄積する。[_filterSwipeArea]/[_tiltFilterSwipeArea] 参照)。
  double _filterDragAccum = 0;
  static const _filterSwipeThreshold = 45.0;

  /// tilt session 中の preview frame の論理サイズを [kDebugMode] で
  /// 1回だけログしたかどうか。[widget.activeTilt] が変わるたびリセットする。
  bool _loggedTiltFrameSize = false;

  /// [_leftTools]/[_rightRail] 自身が使っている固定幅(手動 entry の
  /// portrait Row でも、tilt entry で正立させた後の帯の厚みとしても使う)。
  static const _leftToolsWidth = 62.0;
  static const _rightRailWidth = 100.0;

  /// 左側の flash/camera switch/timer 用ボタン(既定の [_toolChip] は
  /// 44/19)。実機で小さく見えたため、既定の約1.27倍(直径)・約1.26倍
  /// (アイコン)へ大きくした。drafts のボタンはここでは対象外(既定のまま)。
  static const _leftToolsChipDiameter = 56.0;
  static const _leftToolsChipIconSize = 24.0;

  /// flash/camera switch/timer の縦方向の間隔(既定の10から約1.2倍)。
  /// drafts との間隔はここでは対象外(既定の10のまま)。
  static const _leftToolsChipGap = 12.0;

  FlashMode _flashMode = FlashMode.off;

  int _timerIndex = 0;
  int get _timerSeconds => _timerChoices[_timerIndex];

  /// セルフタイマーの残り秒数。null のときはタイマー動作中でない。
  int? _countdownRemaining;

  /// タイマー待機中に Camera が破棄された場合、進行中のカウントダウンを
  /// 打ち切るためのトークン。
  int _countdownToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Camera permission が Granted、かつこのタブが実際に必要になった
    // (active)後にだけ controller を作る lazy-init。PostTab は PageView の
    // 隣接ページとして Home 到達直後から widget 自体は組み立てられ得るが、
    // 起動直後は active が false なので、ここではまだ initialize() を
    // 呼ばない(=OS permission dialog も出ない)。
    _refreshCameraPermission();
    _reloadDraftCount();
  }

  @override
  void didUpdateWidget(covariant PostTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Camera タブへ戻ってきたタイミングで下書き件数を読み直す
    // (保存・投稿・削除は他画面で起きるため、ここでしか気づけない)。
    if (!oldWidget.active && widget.active) {
      _reloadDraftCount();
      // Settings から戻って許可した直後に Camera タブへ来ることもあるため、
      // active になるたびに現況を読み直す。
      _refreshCameraPermission();
    }
    // widget.activeTilt が変わった(tilt 経由での入場/退場)。PostTab は
    // PageView 内に残り続けて controller が作り直されないことがあるため、
    // 既に生きている controller へ明示的に lock/unlock を同期させる
    // (次回この controller のまま手動で開かれたときに古い lock が
    // 残らないようにするため)。
    if (oldWidget.activeTilt != widget.activeTilt) {
      _syncCaptureOrientationLock();
      // capture orientation の付け外しの成否とは無関係に、UI chrome の
      // 回転量は widget.activeTilt だけで決まる([uiQuarterTurnsForTilt])
      // ので、こちらは常にログする。frame サイズは次の build 時に
      // LayoutBuilder 経由で確定してから改めて1回だけログする
      // ([_tiltCameraStage] 参照)。
      _debugLogUiOrientation();
      _loggedTiltFrameSize = false;
    }
  }

  /// [widget.activeTilt] から求まる目標の capture orientation。
  /// null なら「lock しない(手動で開いた/傾き対象外)」を意味する。
  DeviceOrientation? get _captureLockOrientation {
    final tilt = widget.activeTilt;
    if (tilt == null) return null;
    return captureOrientationForTilt(tilt);
  }

  /// 既に生きている [_controller] へ、現在の [_captureLockOrientation] を
  /// 反映する(lock すべきなのに未 lock なら lock、lock 不要になったのに
  /// まだ lock されたままなら unlock)。[_createController] 内での初回適用
  /// ではカバーできない、「controller は使い回すが tilt context だけ
  /// 変わった」場合のための同期。
  Future<void> _syncCaptureOrientationLock() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final target = _captureLockOrientation;
    final alreadyLocked = controller.value.isCaptureOrientationLocked;
    if (target == null && !alreadyLocked) return;
    if (target != null &&
        alreadyLocked &&
        controller.value.lockedCaptureOrientation == target) {
      return;
    }
    try {
      if (target != null) {
        await controller.lockCaptureOrientation(target);
      } else {
        await controller.unlockCaptureOrientation();
      }
    } catch (_) {
      // 付け外しに失敗しても撮影自体は継続できるようにする。
      return;
    }
    // await の間に controller が差し替え/破棄されていたら触れない。
    if (!mounted || _controller != controller) return;
    _debugLogCameraSession('orientation-sync', controller);
  }

  /// 次回 Android 実機確認で必要な orientation 情報を1行にまとめて出す。
  /// release では絶対に出さない([kDebugMode] のみ)。frame ごとではなく
  /// 「Camera session 開始時」「orientation lock/unlock を同期したとき」
  /// だけ呼ぶ(毎frame出力の禁止)。
  void _debugLogCameraSession(String event, CameraController controller) {
    if (!kDebugMode) return;
    final v = controller.value;
    debugPrint(
      '[CameraOrientation] event=$event '
      'entry=${widget.activeTilt == null ? "manual" : "tilt"} '
      'tilt=${widget.activeTilt} '
      'lens=${controller.description.lensDirection} '
      'sensorOrientation=${controller.description.sensorOrientation} '
      'deviceOrientation=${v.deviceOrientation} '
      'lockedCaptureOrientation=${v.lockedCaptureOrientation} '
      'previewSize=${v.previewSize} '
      'targetLock=$_captureLockOrientation',
    );
  }

  /// Camera **UI chrome**(tools・撮影オーバーレイ等、映像そのものは含まない)
  /// の回転量(+ 分かっていれば preview frame の論理サイズ、および
  /// preview **映像内容**だけにかける追加回転量)。
  /// [_debugLogCameraSession] と同様 [kDebugMode] 限定・呼び出し箇所を
  /// 絞った1回だけのログ(毎frame出力の禁止)。
  void _debugLogUiOrientation({
    Size? logicalFrameSize,
    int? previewQuarterTurns,
  }) {
    if (!kDebugMode) return;
    final frameInfo = logicalFrameSize == null
        ? ''
        : ' logicalFrame=$logicalFrameSize physicalIntended=3:2';
    final previewInfo =
        previewQuarterTurns == null ? '' : ' previewQuarterTurns=$previewQuarterTurns';
    debugPrint(
      '[CameraUIOrientation] '
      'entry=${widget.activeTilt == null ? "manual" : "tilt"} '
      'tilt=${widget.activeTilt} '
      'quarterTurns=${uiQuarterTurnsForTilt(widget.activeTilt)}'
      '$frameInfo'
      '$previewInfo',
    );
  }

  Future<void> _reloadDraftCount() async {
    final drafts = await DraftStore.instance.loadAll();
    if (!mounted) return;
    setState(() => _draftCount = drafts.length);
  }

  void _openDrafts() {
    showDraftsSheet(
      context,
      api: widget.api,
      onPostResult: widget.onPostResult,
      onChanged: _reloadDraftCount,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownToken++;
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      // Settings からの帰還も含め、実際の permission 状態を必ず読み直して
      // から(Granted かつ active のときだけ)initialize() する。ここでも
      // Permission.camera.request() は絶対に呼ばない。
      _refreshCameraPermission();
    }
  }

  /// 実際の OS camera permission status を読み直す(要求はしない)。
  /// Granted かつこのタブが active なら、そのまま lazy-init へ進む。
  Future<void> _refreshCameraPermission() async {
    final granted = await AppPermissions.isGranted(AppPermissionKind.camera);
    if (!mounted) return;
    setState(() => _cameraPermissionGranted = granted);
    if (granted && widget.active) {
      _setUpCamera();
    }
  }

  /// 破棄済みのコントローラを build が掴まないよう、参照を外してから捨てる。
  void _disposeCamera() {
    _countdownToken++; // 進行中のカウントダウンがあれば打ち切る。
    final controller = _controller;
    if (controller == null) return;
    if (mounted) {
      setState(() {
        _controller = null;
        _countdownRemaining = null;
      });
      _reportBusy();
    } else {
      _controller = null;
    }
    controller.dispose();
  }

  Future<void> _setUpCamera() async {
    if (_settingUp || _controller != null) return;
    // Granted を確認する前に initialize() を呼ぶと、camera プラグインが
    // 内部で OS permission dialog を出してしまう。ここが最後の砦。
    if (_cameraPermissionGranted != true) return;
    _settingUp = true;
    try {
      final cameras =
          _cameras.isNotEmpty ? _cameras : await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'カメラが見つかりませんでした');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = await _createController(back);
      _cameras = cameras;
      if (controller == null) return;
      if (mounted) {
        setState(() {
          _controller = controller;
          _cameraError = null;
        });
      }
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _cameraError = 'カメラを使えません: ${e.description ?? e.code}');
      }
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'カメラを使えません: $e');
    } finally {
      _settingUp = false;
    }
  }

  /// [description] で初期化済みの [CameraController] を作る。
  /// dateback は無音のため、8mm でもマイクは使わない
  /// (依存パッケージがマニフェストへ静的に足す RECORD_AUDIO はここでは
  /// 制御できないが、`enableAudio: false` により実行時にマイクへは
  /// 一切アクセスしない)。
  ///
  /// [_setUpCamera](初回)と [_switchCamera](前後カメラ切替)の両方が
  /// ここを経由するため、tilt 経由で入場した場合の orientation lock も
  /// この1箇所で適用すれば、切替後の新しい controller にも自動的に
  /// 引き継がれる(=前後カメラ切替のたびに90°ズレが再発することはない)。
  Future<CameraController?> _createController(
    CameraDescription description,
  ) async {
    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return null;
    }
    // tilt-to-camera で開いた場合だけ、実際に検知した傾きに対応する
    // DeviceOrientation を明示的に lock する。camera package 自身の
    // CameraPreview / still capture / video recording が、いずれもこの
    // 同じ lock 値を orientation の source として使うようになる
    // (`camera_preview.dart` の `_getApplicableOrientation`、
    // `camera_android_camerax` の `lockCaptureOrientation` 実装を確認済み。
    // 詳細は [captureOrientationForTilt] のコメント参照)。手動で開いた
    // 場合(activeTilt == null)はこれまでどおり何もせず、camera plugin
    // 既定の(portrait window 前提の)orientation 処理に委ねる。
    final lockOrientation = _captureLockOrientation;
    if (lockOrientation != null) {
      try {
        await controller.lockCaptureOrientation(lockOrientation);
      } catch (_) {
        // lock に失敗しても撮影自体は続行できるようにする(致命的にしない)。
      }
    }
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {
      // フラッシュが無い端末では失敗して当然。既定値のままにする。
    }
    if (mounted) {
      _debugLogCameraSession('controller-ready', controller);
      _debugLogUiOrientation();
    }
    return controller;
  }

  /// 撮影処理中・確認中・投稿中はすべて「busy」として扱う。MainShell は
  /// これを見て、縦に戻したときに Camera を閉じてよいか判断する。
  /// 二重シャッター・二重投稿を防ぐガードにも使う。
  bool get _busy =>
      _capturing ||
      _cropping ||
      _countdownRemaining != null ||
      _captured != null ||
      _uploading ||
      _recording;

  void _reportBusy() {
    widget.onBusyChanged(_busy);
  }

  void _setMode(PostKind mode) {
    if (_busy) return;
    setState(() {
      _mode = mode;
      _captured = null;
      _capturedContentType = null;
      _stillPreview = null;
    });
    _locationFuture = null;
    _reportBusy();
  }

  /// 実在する前後カメラを切り替える。連打や多重初期化を防ぐ。
  ///
  /// 新旧2つの [CameraController] を同時に持つと端末によってはリソースが
  /// 競合するため、必ず「1. 切替中フラグ → 2. 現controllerをUIから外す
  /// → 3. 旧controllerをdispose → 4. 次cameraをinitialize → 5. 成功したら
  /// 公開」の順で行う。次カメラの初期化に失敗したら、元の
  /// [CameraDescription] で一度だけ復旧を試みる(無限リトライはしない)。
  Future<void> _switchCamera() async {
    if (_switchingCamera || _busy) return;
    final oldController = _controller;
    final current = oldController?.description;
    if (oldController == null || current == null) return;
    final directions = _cameras.map((c) => c.lensDirection).toSet();
    if (directions.length < 2) return;

    final nextDirection = current.lensDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final next = _cameras.firstWhere(
      (c) => c.lensDirection == nextDirection,
      orElse: () => current,
    );
    if (next == current) return;

    // 1. 切替中フラグ / 2. 現controllerをUIから外す。
    setState(() {
      _switchingCamera = true;
      _controller = null;
    });

    // 3. 旧controllerをdispose。
    try {
      await oldController.dispose();
    } catch (_) {
      // 破棄に失敗しても続行する。
    }

    // 4. 次cameraをinitialize。
    CameraController? controller;
    try {
      controller = await _createController(next);
    } catch (_) {
      controller = null;
    }

    // 失敗したら元の CameraDescription で一度だけ復旧を試みる。
    var recovered = false;
    if (controller == null) {
      recovered = true;
      try {
        controller = await _createController(current);
      } catch (_) {
        controller = null;
      }
    }

    if (!mounted) {
      await controller?.dispose();
      return;
    }

    if (controller == null) {
      setState(() {
        _switchingCamera = false;
        _cameraError = 'カメラを切り替えられませんでした';
      });
      return;
    }

    setState(() {
      _controller = controller;
      _switchingCamera = false;
      _cameraError = null;
      // 前面カメラ等でフラッシュが無いことが多いので引き継がない。
      _flashMode = FlashMode.off;
    });
    if (recovered) _snack('カメラを切り替えられませんでした');
  }

  /// off → auto → always の順で切り替える。camera プラグインが実際に
  /// 対応している [FlashMode] だけを使い、失敗したら状態を変えない
  /// (使えるように見せかけない)。前面カメラでは呼ばない(UI側で隠す)。
  Future<void> _cycleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    const order = [FlashMode.off, FlashMode.auto, FlashMode.always];
    final next = order[(order.indexOf(_flashMode) + 1) % order.length];
    try {
      await controller.setFlashMode(next);
      if (mounted) setState(() => _flashMode = next);
    } catch (_) {
      // この端末・このカメラでは対応していない。
    }
  }

  void _cycleTimer() {
    if (_countdownRemaining != null) return;
    setState(() => _timerIndex = (_timerIndex + 1) % _timerChoices.length);
  }

  /// シャッター。タイマーが設定されていれば指定秒数待ってから撮影する。
  /// カウントダウン中・撮影確認中・投稿中の二重起動を防ぐ。
  Future<void> _onShutterTap() async {
    if (_busy) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final seconds = _timerSeconds;
    if (seconds > 0) {
      final token = ++_countdownToken;
      for (var remaining = seconds; remaining >= 1; remaining--) {
        if (!mounted || token != _countdownToken) return;
        setState(() => _countdownRemaining = remaining);
        _reportBusy();
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!mounted || token != _countdownToken) return;
      setState(() => _countdownRemaining = null);
      _reportBusy();
    }

    await _shoot();
  }

  Future<void> _shoot() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _recording) {
      return;
    }
    if (_mode == PostKind.film35mm) {
      await _take35mm(controller);
    } else {
      await _take8mm(controller);
    }
  }

  /// 撮影 → 3:2 へ中央切り出し + フィルター焼き込み(見えている範囲・見た目と
  /// 投稿される範囲・色を一致させる)。takePicture() 開始からクロップ完了
  /// まで一貫して busy にする(この間にシャッター再押下や縦向き復帰で
  /// Camera を閉じられないように)。
  Future<void> _take35mm(CameraController controller) async {
    // シャッターを押した瞬間のフィルターをこの1枚へ固定する。以降に
    // スワイプで _filter が変わっても、この撮影結果には混ざらない
    // (フィルタースワイプ自体も busy 中は受け付けない設計と合わせて二重に
    // 安全にしてある)。
    final filter = _filter;
    setState(() => _capturing = true);
    _reportBusy();
    // 画像処理と並行して進めておく(投稿確認画面の表示を位置取得で
    // 待たせない)。実際に使うのは _post() で投稿する瞬間。
    _locationFuture = widget.onCaptureLocation();
    try {
      final shot = await controller.takePicture();
      final raw = await shot.readAsBytes();
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _cropping = true;
      });
      _reportBusy();
      final cropped = await compute(
        _cropAndFilterTo3x2,
        _CropAndFilterParams(raw, filter.matrix),
      );
      if (!mounted) return;
      setState(() {
        _cropping = false;
        _captured = cropped;
        _capturedContentType = 'image/jpeg';
        _stillPreview = cropped;
      });
      _reportBusy();
    } catch (e) {
      if (mounted) {
        setState(() {
          _capturing = false;
          _cropping = false;
        });
        _reportBusy();
        _snack('撮影できませんでした: $e');
      }
    }
  }

  /// 約2秒・無音で録画する。ファイルそのものの 3:2 切り出しは行わない
  /// (Phase 7 の制約。クラスドキュメント・報告を参照)。
  Future<void> _take8mm(CameraController controller) async {
    setState(() => _recording = true);
    // 録画と並行して進めておく(投稿確認画面の表示を位置取得で
    // 待たせない)。実際に使うのは _post() で投稿する瞬間。
    _locationFuture = widget.onCaptureLocation();
    try {
      await controller.startVideoRecording();
      await Future<void>.delayed(_recordDuration);
      final clip = await controller.stopVideoRecording();
      final bytes = await File(clip.path).readAsBytes();
      if (!mounted) return;
      setState(() {
        _captured = bytes;
        _capturedContentType = 'video/mp4';
        _stillPreview = null;
      });
      _reportBusy();
    } catch (e) {
      if (mounted) _snack('撮影できませんでした: $e');
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  void _retake() {
    if (_recording) return;
    setState(() {
      _captured = null;
      _capturedContentType = null;
      _stillPreview = null;
    });
    _locationFuture = null;
    _reportBusy();
  }

  Future<void> _post() async {
    final bytes = _captured;
    final contentType = _capturedContentType;
    final kind = _mode;
    if (bytes == null || contentType == null || _uploading) return;

    setState(() => _uploading = true);
    _reportBusy();

    // 撮影時から並行して進めていた撮影地取得の結果を待つ(取り直していなければ
    // アップロード自体の通信時間と重なっているので、ここでの追加待ちは
    // 通常ほぼ無い)。失敗時は null のまま(LocationService 側で吸収済み)。
    String? locationLabel;
    try {
      locationLabel = await _locationFuture;
    } catch (_) {
      locationLabel = null;
    }

    PostOutcome outcome;
    try {
      await widget.api.createPost(
        bytes: bytes,
        kind: kind,
        contentType: contentType,
        locationLabel: locationLabel,
      );
      outcome = const PostSuccess();
    } catch (_) {
      // 成功/失敗どちらも、これ以降は MainShell が Home へ戻して伝える
      // (中間確認画面なし)。ここではメッセージの出し分けはしない。
      outcome = PostFailure(
        bytes: bytes,
        kind: kind,
        contentType: contentType,
        locationLabel: locationLabel,
      );
    }

    if (!mounted) return;
    // 成功・失敗どちらでも、この画面自体の「撮影確認中・投稿処理中」は
    // ここで終わる。busy を残留させない。
    setState(() {
      _uploading = false;
      _captured = null;
      _capturedContentType = null;
      _stillPreview = null;
    });
    _locationFuture = null;
    _reportBusy();
    widget.onPostResult(outcome);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // 画面は縦固定。Camera は横向き専用UIで、カメラ映像を主役にする。
    return ColoredBox(
      color: const Color(0xFF050608),
      child: SafeArea(child: _cameraStage(context)),
    );
  }

  Widget _cameraStage(BuildContext context) {
    final permissionGranted = _cameraPermissionGranted;
    if (permissionGranted == null) {
      // まだ現況を読んでいる最中。ここでは何も要求しない。
      return const Center(
        child: CircularProgressIndicator(color: BloomColors.primaryContainer),
      );
    }
    if (!permissionGranted) {
      return _permissionDeniedView();
    }

    final controller = _controller;
    final error = _cameraError;

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            error,
            style: BloomText.bodySm.copyWith(color: BloomColors.secondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: BloomColors.primaryContainer),
      );
    }

    // 手動 entry(または tilt-to-camera の対象外の向き)なら、既存の
    // portrait レイアウトをそのまま使う(無変更)。CameraPreview は
    // portrait window 前提の camera plugin 既定の orientation 処理のまま。
    final quarterTurns = uiQuarterTurnsForTilt(widget.activeTilt);
    if (quarterTurns == 0) {
      return Row(
        children: [
          _leftTools(),
          Expanded(child: Center(child: _filterSwipeArea(controller))),
          _rightRail(),
        ],
      );
    }

    return _tiltCameraStage(controller, quarterTurns);
  }

  /// tilt-to-camera 経由で開いた場合の Camera UI。
  ///
  /// window 自体は portrait 固定のまま回転しないので、ここは
  /// **window の論理座標(portrait)で「上から順に」中身を並べる**
  /// `Column` として組む:
  ///
  /// ```
  /// [window 論理TOP]    _leftTools 相当(flash/switch/timer/drafts)を
  ///                     RotatedBox で正立させた帯
  /// [window 論理中央]   preview frame(video は追加回転あり、overlay は
  ///                     UI chrome 用回転で正立)
  /// [window 論理BOTTOM] _rightRail 相当(shutter/35mm-8mm/home)を
  ///                     RotatedBox で正立させた帯
  /// ```
  ///
  /// ### 訂正の経緯(実機で左右が逆だった)
  ///
  /// 以前は _rightRail を論理TOP、_leftTools を論理BOTTOM に置いていたが、
  /// 実機(Xperia)では tools が右・shutter が左という、期待と逆の配置に
  /// なった。原因は「window の論理TOP はユーザーから見て右」という
  /// 当時の想定が誤りだったため。正しくは
  /// **window の論理TOP はユーザーから見て左、論理BOTTOM は右**
  /// (`landscapeShutterRight` は端末上部を左へ倒す=物理TOP辺が
  /// world-left 方向を向く回転であり、これは [TiltWatcher] 自身の
  /// コメント「端末上部を左へ倒す」と直接対応する)。そのため
  /// _leftTools を論理TOP、_rightRail を論理BOTTOM に**入れ替えた**。
  /// 各帯の中身([_leftTools]/[_rightRail] 自体、および両者に渡す
  /// [quarterTurns] の値)は一切変更していない(=レイアウト配置だけの
  /// 修正で、個々のアイコンを別々に反転させてはいない)。
  ///
  /// video layer(preview frame の中身)には [previewQuarterTurnsForTilt]
  /// による追加回転を適用する(実機で映像内容だけ90°ズレていたための
  /// 表示専用の補正。[uiQuarterTurnsForTilt] とは目的が異なる別の値。
  /// frame 自体の位置・サイズ・比率には影響しない)。overlay は
  /// video と全く同じ大きさの box の中で、内容だけ [uiQuarterTurnsForTilt]
  /// で正立させる(=UI chrome 側の回転のまま、変更なし)。
  Widget _tiltCameraStage(CameraController controller, int quarterTurns) {
    final previewQuarterTurns = previewQuarterTurnsForTilt(widget.activeTilt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _leftToolsWidth,
          child: RotatedBox(quarterTurns: quarterTurns, child: _leftTools()),
        ),
        Expanded(
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = tiltPreviewFrameLogicalSize(
                  BoxConstraints(
                    maxWidth: constraints.maxWidth,
                    maxHeight: constraints.maxHeight,
                  ),
                  physicalAspect: _targetAspect,
                );
                if (!_loggedTiltFrameSize) {
                  _loggedTiltFrameSize = true;
                  _debugLogUiOrientation(
                    logicalFrameSize: size,
                    previewQuarterTurns: previewQuarterTurns,
                  );
                }
                return SizedBox(
                  width: size.width,
                  height: size.height,
                  child: Stack(
                    children: [
                      _previewVideoOnly(
                        controller,
                        boxAspect: 1 / _targetAspect,
                        previewQuarterTurns: previewQuarterTurns,
                      ),
                      IgnorePointer(
                        child: RotatedBox(
                          quarterTurns: quarterTurns,
                          child: _previewOverlayOnly(),
                        ),
                      ),
                      _tiltFilterSwipeArea(),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        SizedBox(
          height: _rightRailWidth,
          child: RotatedBox(quarterTurns: quarterTurns, child: _rightRail()),
        ),
      ],
    );
  }

  /// Camera permission が Denied のときの表示。ここから OS permission
  /// dialog を再表示することはせず(=勝手に再要求しない)、設定アプリへの
  /// 導線だけを見せる。カメラだけが使えなくなり、他の機能には影響しない。
  Widget _permissionDeniedView() {
    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.camera_alt_outlined, color: Colors.white54, size: 32),
                const SizedBox(height: 12),
                Text(
                  'カメラへのアクセスが必要です',
                  style: BloomText.bodySm.copyWith(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: openAppSettings,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('設定を開く'),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 4,
          left: 12,
          child: _homeButton(),
        ),
      ],
    );
  }

  /// 35mm・ライブプレビュー中(撮影確認中でない)だけ、横スワイプで
  /// フィルターを切り替えられるようにする。
  ///
  /// [PostTab.onFilterGestureActive] は指が触れた瞬間([Listener]の
  /// onPointerDown)で呼ぶ。MainShell 側の PageView(Camera ← Home →
  /// Profile)は `Scrollable` が `NeverScrollableScrollPhysics` を見ると
  /// 自身のドラッグ用 GestureRecognizer を登録しなくなる(Flutter の
  /// `ScrollPositionWithSingleContext` が `setCanDrag(physics.
  /// shouldAcceptUserOffset(...))` で recognizer 自体を外す実装になって
  /// いるため)。onHorizontalDragStart まで待つと、そのときには既に
  /// 親 PageView 側の recognizer がこの pointer の gesture arena へ
  /// 参加してしまっている可能性があるため、より早い pointer down の時点で
  /// 知らせて PageView 側を無効化しておく。
  ///
  /// フィルターの切替判定そのものは、そのまま既存の
  /// onHorizontalDragUpdate/End(横方向の移動量の閾値判定)を使う。
  ///
  /// 8mm・撮影確認中・投稿処理中などは対象外にし、その間は普段どおり
  /// PageView のスワイプへ委ねる(このエリア自体をラップしない)。
  Widget _filterSwipeArea(CameraController controller) {
    final preview = _previewFrame(controller);
    if (_mode != PostKind.film35mm || _busy) return preview;

    return Listener(
      onPointerDown: (_) => widget.onFilterGestureActive(true),
      onPointerUp: (_) => widget.onFilterGestureActive(false),
      onPointerCancel: (_) => widget.onFilterGestureActive(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _filterDragAccum = 0,
        onHorizontalDragUpdate: (details) {
          _filterDragAccum += details.delta.dx;
        },
        onHorizontalDragEnd: (_) {
          if (_filterDragAccum.abs() > _filterSwipeThreshold) {
            _changeFilter(_filterDragAccum < 0 ? 1 : -1);
          }
        },
        child: preview,
      ),
    );
  }

  void _changeFilter(int delta) {
    final values = PhotoFilter.values;
    final next = (values.indexOf(_filter) + delta) % values.length;
    setState(() => _filter = values[(next + values.length) % values.length]);
  }

  /// tilt-to-camera 中の filter swipe。window 自体は portrait 固定のまま
  /// UI 全体を [uiQuarterTurnsForTilt] ぶん回転させて見せているため、
  /// ユーザーが物理的に「横方向」へスワイプする動きは、window の生座標
  /// (portrait 基準、無回転)では**縦方向**の指の動き(dy)として届く。
  ///
  /// ## 軸(dx→dy)の根拠
  ///
  /// `landscapeShutterRight`(portraitUp から反時計回り90°)へ端末を
  /// 傾けた状態で、window のネイティブ +x 軸(dx>0 方向)は重力基準の
  /// 「上」を、window のネイティブ +y 軸(dy>0 方向)は重力基準の「右」を
  /// 指す(portraitUp から反時計回り90°回転させた単位ベクトルの計算による。
  /// このタッチ座標→重力方向の対応は「window がその場で物理的に運ばれる」
  /// だけの話で、[uiQuarterTurnsForTilt] の回転方向とは無関係に成立する
  /// ため、UI chrome の回転量([captureOrientationForTilt] の
  /// quarterTurns 修正)が変わってもこの軸の対応(dx→dy)自体は変わらない)。
  /// つまり「ユーザーから見て右へスワイプ」は window 座標では dy>0
  /// (下方向のドラッグ)として届く。
  ///
  /// ## 符号の根拠(手動 entry とは意図的に異なる)
  ///
  /// 仕様として「ユーザーから見て右へswipe→次のfilter、左へswipe→前の
  /// filter」を満たす必要があるため、`_filterDragAccum < 0 ? -1 : 1`
  /// (accum<0 = 左スワイプ = 前のfilter、accum>0 = 右スワイプ = 次の
  /// filter)とする。これは手動 entry([_filterSwipeArea])の
  /// `_filterDragAccum < 0 ? 1 : -1` とは比較の向きが逆だが、手動 entry
  /// 側の dx 規約(左スワイプ→次)は変更しない、という指示に基づき
  /// 意図的に据え置いている。
  Widget _tiltFilterSwipeArea() {
    if (_mode != PostKind.film35mm || _busy) return const SizedBox.shrink();

    return Listener(
      onPointerDown: (_) => widget.onFilterGestureActive(true),
      onPointerUp: (_) => widget.onFilterGestureActive(false),
      onPointerCancel: (_) => widget.onFilterGestureActive(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => _filterDragAccum = 0,
        onVerticalDragUpdate: (details) {
          _filterDragAccum += details.delta.dy;
        },
        onVerticalDragEnd: (_) {
          if (_filterDragAccum.abs() > _filterSwipeThreshold) {
            _changeFilter(_filterDragAccum < 0 ? -1 : 1);
          }
        },
        child: const SizedBox.expand(),
      ),
    );
  }

  /// 3:2 の撮影フレームに重ねる、映像以外の固定オーバーレイ
  /// (録画中インジケーター・日付スタンプ・カウントダウン・filter dots)。
  /// [_previewFrame](手動 entry)と [_previewOverlayOnly](tilt entry)の
  /// 両方から共有する。
  List<Widget> _previewOverlayChildren() => [
        if (_recording) const _RecordDot(),
        // dateback の日付は 35mm だけ(8mm では出さない)。
        if (showDatebackForMode(_mode)) _datebackStamp(),
        if (_countdownRemaining != null) _countdownOverlay(),
        if (_mode == PostKind.film35mm && _stillPreview == null && !_cropping)
          Positioned(
            left: 0,
            right: 0,
            bottom: 26,
            child: IgnorePointer(child: _filterDots()),
          ),
      ];

  /// 3:2 の撮影フレーム。見えている範囲と投稿される範囲を一致させる中心。
  /// 手動 entry のときだけ使う(=既存の見た目・widget 構成を完全に維持)。
  ///
  /// フィルムゲート・グレイン・ジッターは [Film8mmEffects](共通実装)を
  /// 映像レイヤーだけに適用し、日付スタンプ・録画中インジケーター・
  /// カウントダウンはその上の固定レイヤーとして揺らさない。
  Widget _previewFrame(CameraController controller) {
    return AspectRatio(
      aspectRatio: _targetAspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: Colors.white24),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _previewVideoContent(controller, boxAspect: _targetAspect),
              ..._previewOverlayChildren(),
            ],
          ),
        ),
      ),
    );
  }

  /// tilt entry 用: 撮影フレームのうち、実際の映像ピクセル
  /// (CameraPreview・静止画プレビュー・crop 中スピナー)だけを描く。
  ///
  /// **frame 自体**(この widget が置かれる box の位置・サイズ・比率)は
  /// tilt-to-camera 中でも一切回転・変形しない(要件どおり)。ただし実機
  /// (Xperia)で、frame 自体は正しいのに中の映像内容だけ90°ズレることが
  /// 確認されたため、[previewQuarterTurns] が非0 のときだけ**映像内容**に
  /// 表示専用の追加回転をかける([previewQuarterTurnsForTilt] 参照。
  /// `CameraController` の capture orientation・`lockCaptureOrientation`
  /// は一切関与しない、Flutter 側の表示レイヤーだけの補正)。
  ///
  /// [_previewFrame](手動 entry)と違い、外側の [AspectRatio] は持たない
  /// (呼び出し元の [_tiltCameraStage] が [tiltPreviewFrameLogicalSize] で
  /// 計算した論理サイズの `SizedBox` を既に用意しているため、ここでは
  /// その `SizedBox` いっぱいに描くだけでよい)。枠(角丸・黒背景・
  /// 白い縁取り)は向きに依存しない見た目なので、[_previewFrame] と
  /// 同じくここに含めてよい。
  ///
  /// [boxAspect] は「実際にこの widget が描かれる box の width/height 比」
  /// (tilt entry では論理 2:3、手動 entry の [_previewFrame] 相当では
  /// 3:2)。[_fillPreview] のスケール計算がこの box の形に正しく
  /// フィットさせるために必要。
  Widget _previewVideoOnly(
    CameraController controller, {
    required double boxAspect,
    int previewQuarterTurns = 0,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: Colors.white24),
        ),
        child: _previewVideoContent(
          controller,
          boxAspect: boxAspect,
          previewQuarterTurns: previewQuarterTurns,
        ),
      ),
    );
  }

  /// tilt entry 用: 撮影オーバーレイだけを束ねた widget。
  /// 背景・枠は持たない(video layer の上に重ねるだけなので、ここに
  /// 不透明な背景を持たせると video が隠れてしまう)。
  Widget _previewOverlayOnly() => Stack(children: _previewOverlayChildren());

  /// [_previewFrame]/[_previewVideoOnly] で共有する、実際の映像ピクセル
  /// 部分(Film8mmEffects 以下)。[boxAspect] は [_fillPreview] 参照。
  ///
  /// [previewQuarterTurns] が非0(tilt entry のみ)のときは、live
  /// CameraPreview・35mm 静止画プレビュー・crop 中スピナーのいずれが
  /// 表示中でも同じ映像内容として一律に [RotatedBox] で回す(8mm の
  /// live/recording も同じ経路を通るため自動的に揃う)。`Film8mmEffects`
  /// (フィルムゲート・グレイン・ジッター)は回転後の内容の**外側**に
  /// 適用するので、フィルム質感自体の向きは変わらない。
  ///
  /// [Film8mmEffects] のフィルムゲートは、通常(手動 entry)は左辺に
  /// 表示するのが正しいが、tilt entry では映像内容だけ回っていて
  /// [Film8mmEffects] 自身はその回転の外側にあるため、そのままだと
  /// 実機で見て物理下側にズレる。[previewQuarterTurns] が非0のときだけ
  /// [FilmGateEdge.top] を渡し、window の論理TOP(=tilt 時にユーザーから
  /// 見て左辺になる。[uiQuarterTurnsForTilt] の根拠と同じ回転)に置く。
  Widget _previewVideoContent(
    CameraController controller, {
    required double boxAspect,
    int previewQuarterTurns = 0,
  }) {
    final filmActive = showFilmGateForMode(_mode);
    // RotatedBox は奇数 quarterTurns のとき子へ縦横入れ替えた制約を渡す。
    // そのぶん _fillPreview 側が cover すべき box の形も入れ替えておかないと、
    // 回転後に隙間(letterbox)や overflow が出る。
    final fillAspect =
        previewQuarterTurns.isOdd ? 1 / boxAspect : boxAspect;
    Widget content = _stillPreview != null
        ? Image.memory(_stillPreview!, fit: BoxFit.cover)
        : _cropping
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              )
            : _previewFilter(_fillPreview(controller, boxAspect: fillAspect));
    if (previewQuarterTurns != 0) {
      content = RotatedBox(quarterTurns: previewQuarterTurns, child: content);
    }
    return Film8mmEffects(
      active: filmActive,
      gateEdge: previewQuarterTurns != 0 ? FilmGateEdge.top : FilmGateEdge.left,
      child: content,
    );
  }

  /// プレビューを歪めずに [boxAspect] の枠いっぱいに収める。
  ///
  /// CameraPreview はセンサーの縦横比で描くので、枠とは比率が合わない。
  /// 差のぶんだけ拡大して切り落とす(BoxFit.cover と同じ考え方)。
  ///
  /// 手動 entry では枠が 3:2([_targetAspect])、tilt entry では
  /// window 論理座標上の枠が 2:3(=`1 / _targetAspect`。映像内容へ追加の
  /// [RotatedBox] をかける場合はその内側の子が見る、入れ替え後の形)に
  /// なるため、どちらの形にフィットさせるかを [boxAspect] で受け取る
  /// (`CameraPreview` 自体は `lockCaptureOrientation` により既に
  /// 正しい向き・比率で自己申告してくるので、ここでの計算式自体は
  /// 変更しない。CameraPreview の回転処理は一切変更していない)。
  Widget _fillPreview(CameraController controller, {required double boxAspect}) {
    var scale = boxAspect / controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    return ClipRect(
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.center,
        child: Center(child: CameraPreview(controller)),
      ),
    );
  }

  /// 35mm は選択中の [PhotoFilter](v15 filter swipe)を、8mm は既存どおり
  /// セピア寄り・彩度低めの質感を、それぞれライブプレビューへ適用する。
  ///
  /// 35mm 側は [PhotoFilter.matrix] をそのまま `ColorFilter.matrix` へ渡す
  /// だけなので、撮影時に同じ matrix でピクセルへ焼き込む
  /// [applyColorMatrix] と常に同じ見た目になる。
  Widget _previewFilter(Widget child) {
    if (_mode == PostKind.film35mm) {
      if (_filter == PhotoFilter.neutral) return child;
      return ColorFiltered(
        colorFilter: ColorFilter.matrix(_filter.matrix),
        child: child,
      );
    }
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.72, 0.21, 0.07, 0, 6, //
        0.20, 0.72, 0.07, 0, 2, //
        0.18, 0.19, 0.60, 0, 0, //
        0, 0, 0, 1, 0, //
      ]),
      child: child,
    );
  }

  /// フィルターの現在位置を示す控えめな dots。名前は出さない。
  Widget _filterDots() {
    final values = PhotoFilter.values;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final f in values) ...[
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: f == _filter
                  ? Colors.white.withValues(alpha: 0.85)
                  : Colors.white.withValues(alpha: 0.32),
            ),
          ),
        ],
      ],
    );
  }

  /// 35mm は残り秒数を数字で見せる。8mm は録画に数字を出さない方針と
  /// 揃え、控えめなリングだけにする(数値カウントダウンは出さない)。
  Widget _countdownOverlay() {
    if (_mode == PostKind.film8mm) {
      return const IgnorePointer(child: Center(child: _CountdownRing()));
    }
    return IgnorePointer(
      child: Center(
        child: Text(
          '${_countdownRemaining ?? ''}',
          style: const TextStyle(
            fontSize: 56,
            fontWeight: FontWeight.w300,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }

  /// 実在するコンパクトカメラの dateback 印字のように、右下ではあるが
  /// 端(枠の角)から少し内側に配置する。固定 px ではなく短辺の
  /// [_datebackInsetFraction](3〜5%目安、4%を採用)を使うことで、
  /// 手動 entry(3:2)・tilt entry(回転後 3:2 相当)のどちらでも、また
  /// 端末のframe実サイズが変わっても同じ見た目の余白になる。
  static const _datebackInsetFraction = 0.04;

  Widget _datebackStamp() {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shortSide = math.min(constraints.maxWidth, constraints.maxHeight);
          final inset = shortSide * _datebackInsetFraction;
          return Padding(
            padding: EdgeInsets.only(right: inset, bottom: inset),
            child: Align(alignment: Alignment.bottomRight, child: _stamp()),
          );
        },
      ),
    );
  }

  Widget _stamp() {
    final nowDate = DateTime.now();
    final y = (nowDate.year % 100).toString().padLeft(2, '0');
    return Text(
      "'$y ${nowDate.month} ${nowDate.day.toString().padLeft(2, '0')}",
      style: BloomText.labelMd.copyWith(
        color: BloomColors.primaryContainer,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.7,
      ),
    );
  }

  /// v15 の左側ツール(flash・前後カメラ・タイマー)。撮影確認中は隠す。
  Widget _leftTools() {
    final controller = _controller;
    if (controller == null || _busy) {
      return const SizedBox(width: _leftToolsWidth);
    }
    final canFlash = controller.description.lensDirection ==
        CameraLensDirection.back;
    final canFlip =
        _cameras.map((c) => c.lensDirection).toSet().length > 1;

    return SizedBox(
      width: _leftToolsWidth,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (canFlash) ...[
            _toolChip(
              icon: _flashIcon(),
              onTap: _cycleFlash,
              diameter: _leftToolsChipDiameter,
              iconSize: _leftToolsChipIconSize,
            ),
            const SizedBox(height: _leftToolsChipGap),
          ],
          if (canFlip) ...[
            _toolChip(
              icon: Icons.cameraswitch_outlined,
              onTap: _switchingCamera ? null : _switchCamera,
              diameter: _leftToolsChipDiameter,
              iconSize: _leftToolsChipIconSize,
            ),
            const SizedBox(height: _leftToolsChipGap),
          ],
          _toolChip(
            icon: Icons.timer_outlined,
            onTap: _cycleTimer,
            badge: _timerSeconds == 0 ? 'off' : '$_timerSeconds',
            diameter: _leftToolsChipDiameter,
            iconSize: _leftToolsChipIconSize,
          ),
          // 下書きが無いときは、控えめであっても常時ここへ出さない。
          // (drafts は今回のサイズ変更の対象外。既定サイズのまま)
          if (_draftCount > 0) ...[
            const SizedBox(height: 10),
            _toolChip(
              icon: Icons.folder_outlined,
              onTap: _openDrafts,
              badge: '$_draftCount',
            ),
          ],
        ],
      ),
    );
  }

  IconData _flashIcon() => switch (_flashMode) {
        FlashMode.off => Icons.flash_off,
        FlashMode.auto => Icons.flash_auto,
        _ => Icons.flash_on,
      };

  Widget _toolChip({
    required IconData icon,
    VoidCallback? onTap,
    String? badge,
    double diameter = 44,
    double iconSize = 19,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: diameter,
        height: diameter,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.4),
          border: Border.all(color: Colors.white24),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(icon, size: iconSize, color: Colors.white),
            if (badge != null)
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEE9DF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF141414),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// v15 のカメラ右レール。上から Home・シャッター(または投稿確認の操作)・
  /// 35mm/8mm 切替。
  Widget _rightRail() {
    final reviewing = _captured != null;
    return SizedBox(
      width: _rightRailWidth,
      child: Column(
        children: [
          const SizedBox(height: 4),
          _homeButton(),
          const Spacer(),
          reviewing ? _reviewButtons() : _shutterButton(),
          const Spacer(),
          if (!reviewing) _modeToggle(),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// Camera には portrait 用ヘッダーが無いので、戻る導線はこれだけ。
  /// 撮影確認中・投稿処理中・タイマー中は押しても戻れないようにする
  /// (縦向き復帰のガードと揃えるため)。
  Widget _homeButton() {
    return IgnorePointer(
      ignoring: _busy,
      child: Opacity(
        opacity: _busy ? 0.35 : 1,
        child: GestureDetector(
          onTap: widget.onHome,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BloomColors.scrim.withValues(alpha: 0.56),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child:
                const Icon(Icons.home_outlined, size: 19, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _shutterButton() {
    final isVideo = _mode == PostKind.film8mm;
    return GestureDetector(
      onTap: _busy ? null : _onShutterTap,
      child: Container(
        width: 68,
        height: 68,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: BloomColors.scrim.withValues(alpha: 0.56),
          border: Border.all(
            color: _recording
                ? BloomColors.heart.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.48),
            width: 2,
          ),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: isVideo ? 27 : 47,
          height: isVideo ? 27 : 47,
          decoration: BoxDecoration(
            color: isVideo ? const Color(0xFFEE5D64) : const Color(0xFFF3F1EF),
            borderRadius: BorderRadius.circular(isVideo ? 8 : 999),
          ),
        ),
      ),
    );
  }

  Widget _reviewButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _railButton(
          _uploading ? '投稿中…' : '投稿',
          _uploading ? null : _post,
          primary: true,
        ),
        const SizedBox(height: 8),
        _railButton('撮り直す', _uploading ? null : _retake, primary: false),
      ],
    );
  }

  Widget _railButton(String label, VoidCallback? onTap, {required bool primary}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 84,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary
              ? BloomColors.primaryContainer
              : BloomColors.scrim.withValues(alpha: 0.64),
          border: Border.all(
            color: primary
                ? BloomColors.primaryContainer
                : Colors.white.withValues(alpha: 0.18),
          ),
          borderRadius: BorderRadius.circular(BloomRadius.pill),
        ),
        child: Text(
          label,
          style: BloomText.labelSm.copyWith(
            color: primary ? const Color(0xFF1D0B00) : const Color(0xFFF0EEEE),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _modeToggle() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final mode in PostKind.values) ...[
          GestureDetector(
            onTap: _busy ? null : () => _setMode(mode),
            child: Container(
              width: 84,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _mode == mode
                    ? const Color(0xFFF1EFED)
                    : BloomColors.scrim.withValues(alpha: 0.5),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                borderRadius: BorderRadius.circular(BloomRadius.pill),
              ),
              child: Text(
                mode.wire,
                style: BloomText.labelSm.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _mode == mode
                      ? const Color(0xFF17181B)
                      : const Color(0xFFA6A8AF),
                ),
              ),
            ),
          ),
          if (mode != PostKind.values.last) const SizedBox(height: 6),
        ],
      ],
    );
  }
}

/// 8mm のセルフタイマー中に表示する、数字を使わないカウントダウン表現。
class _CountdownRing extends StatelessWidget {
  const _CountdownRing();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white54, width: 2),
      ),
    );
  }
}

/// 録画中インジケーター。数字の録画秒数は出さない(仕様どおり)。
class _RecordDot extends StatelessWidget {
  const _RecordDot();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 14,
      top: 12,
      child: Container(
        width: 9,
        height: 9,
        decoration: const BoxDecoration(
          color: Color(0xFFEE5D64),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
