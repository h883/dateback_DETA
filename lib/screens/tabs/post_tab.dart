import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../api/bloom_api.dart';
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

  /// フィルタースワイプの累積横移動量。
  double _filterDragAccum = 0;
  static const _filterSwipeThreshold = 45.0;

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
    _setUpCamera();
    _reloadDraftCount();
  }

  @override
  void didUpdateWidget(covariant PostTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Camera タブへ戻ってきたタイミングで下書き件数を読み直す
    // (保存・投稿・削除は他画面で起きるため、ここでしか気づけない)。
    if (!oldWidget.active && widget.active) {
      _reloadDraftCount();
    }
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
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {
      // フラッシュが無い端末では失敗して当然。既定値のままにする。
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

    return Row(
      children: [
        _leftTools(),
        Expanded(child: Center(child: _filterSwipeArea(controller))),
        _rightRail(),
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

  /// 3:2 の撮影フレーム。見えている範囲と投稿される範囲を一致させる中心。
  ///
  /// フィルムゲート・グレイン・ジッターは [Film8mmEffects](共通実装)を
  /// 映像レイヤーだけに適用し、日付スタンプ・録画中インジケーター・
  /// カウントダウンはその上の固定レイヤーとして揺らさない。
  Widget _previewFrame(CameraController controller) {
    final filmActive = _mode == PostKind.film8mm;
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
              Film8mmEffects(
                active: filmActive,
                child: _stillPreview != null
                    ? Image.memory(_stillPreview!, fit: BoxFit.cover)
                    : _cropping
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white70,
                            ),
                          )
                        : _previewFilter(_fillPreview(controller)),
              ),
              if (_recording) const _RecordDot(),
              Positioned(right: 12, bottom: 10, child: _stamp()),
              if (_countdownRemaining != null) _countdownOverlay(),
              if (_mode == PostKind.film35mm &&
                  _stillPreview == null &&
                  !_cropping)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 26,
                  child: IgnorePointer(child: _filterDots()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// プレビューを歪めずに 3:2 の枠いっぱいに収める。
  ///
  /// CameraPreview はセンサーの縦横比で描くので、3:2 の枠とは比率が合わない。
  /// 差のぶんだけ拡大して切り落とす(BoxFit.cover と同じ考え方)。
  Widget _fillPreview(CameraController controller) {
    var scale = _targetAspect / controller.value.aspectRatio;
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
      return const SizedBox(width: 62);
    }
    final canFlash = controller.description.lensDirection ==
        CameraLensDirection.back;
    final canFlip =
        _cameras.map((c) => c.lensDirection).toSet().length > 1;

    return SizedBox(
      width: 62,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (canFlash) ...[
            _toolChip(icon: _flashIcon(), onTap: _cycleFlash),
            const SizedBox(height: 10),
          ],
          if (canFlip) ...[
            _toolChip(
              icon: Icons.cameraswitch_outlined,
              onTap: _switchingCamera ? null : _switchCamera,
            ),
            const SizedBox(height: 10),
          ],
          _toolChip(
            icon: Icons.timer_outlined,
            onTap: _cycleTimer,
            badge: _timerSeconds == 0 ? 'off' : '$_timerSeconds',
          ),
          // 下書きが無いときは、控えめであっても常時ここへ出さない。
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
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
            Icon(icon, size: 19, color: Colors.white),
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
      width: 100,
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
