import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../api/bloom_api.dart';
import '../../models/models.dart';
import '../../theme/bloom_theme.dart';

/// 投稿画面（仕様書 11）。
///
/// 35mm は静止画、8mm は2秒の動画。モックと同じく横向きでのみ撮影させる。
class PostTab extends StatefulWidget {
  const PostTab({super.key, required this.api, required this.onPosted});

  final BloomApi api;
  final VoidCallback onPosted;

  @override
  State<PostTab> createState() => _PostTabState();
}

class _PostTabState extends State<PostTab> with WidgetsBindingObserver {
  static const _recordDuration = Duration(seconds: 2);

  CameraController? _controller;
  String? _cameraError;

  /// 初期化中の多重起動を防ぐ。回転のたびに resumed が来るため。
  bool _settingUp = false;

  PostKind _mode = PostKind.film35mm;
  bool _recording = false;
  bool _uploading = false;

  /// 撮影済みの一枚（または2秒）。投稿するまで保持する。
  Uint8List? _captured;
  String? _capturedContentType;
  Uint8List? _stillPreview;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setUpCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    final controller = _controller;
    if (controller == null) return;
    if (mounted) {
      setState(() => _controller = null);
    } else {
      _controller = null;
    }
    controller.dispose();
  }

  Future<void> _setUpCamera() async {
    if (_settingUp || _controller != null) return;
    _settingUp = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'カメラが見つかりませんでした');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        // 8mm は音も込みで残す。
        enableAudio: true,
      );
      // 初期化が済んでから公開する。半端な状態を build に見せない。
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _cameraError = null;
      });
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

  void _setMode(PostKind mode) {
    if (_recording) return;
    setState(() {
      _mode = mode;
      _captured = null;
      _capturedContentType = null;
      _stillPreview = null;
    });
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

  Future<void> _take35mm(CameraController controller) async {
    try {
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      if (!mounted) return;
      setState(() {
        _captured = bytes;
        _capturedContentType = 'image/jpeg';
        _stillPreview = bytes;
      });
    } catch (e) {
      if (mounted) _snack('撮影できませんでした: $e');
    }
  }

  Future<void> _take8mm(CameraController controller) async {
    setState(() => _recording = true);
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
  }

  Future<void> _post() async {
    final bytes = _captured;
    final contentType = _capturedContentType;
    if (bytes == null || contentType == null || _uploading) return;

    setState(() => _uploading = true);
    try {
      await widget.api.createPost(
        bytes: bytes,
        kind: _mode,
        contentType: contentType,
      );
      if (!mounted) return;
      setState(() {
        _captured = null;
        _capturedContentType = null;
        _stillPreview = null;
      });
      widget.onPosted();
    } on BloomApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (e) {
      if (mounted) _snack('投稿できませんでした: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // 縦でも横でも撮影できる。横向きにしたときにこの画面へ来る導線は
    // MainShell 側が持っている。
    return ColoredBox(
      color: const Color(0xFF050608),
      child: _cameraStage(context),
    );
  }

  Widget _cameraStage(BuildContext context) {
    final controller = _controller;
    final error = _cameraError;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                error,
                style: BloomText.bodySm.copyWith(color: BloomColors.secondary),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else if (controller == null)
          const Center(
            child: CircularProgressIndicator(color: BloomColors.primaryContainer),
          )
        else if (!controller.value.isInitialized)
          const Center(
            child: CircularProgressIndicator(color: BloomColors.primaryContainer),
          )
        // 撮影済みの静止画があればそれを見せる（8mm は撮り終えたら素通し）。
        else if (_stillPreview != null)
          Image.memory(_stillPreview!, fit: BoxFit.cover)
        else
          _previewFilter(_fillPreview(context, controller)),
        if (_recording) const _RecordChip(),
        Positioned(top: 14, left: 0, right: 0, child: Center(child: _modeSwitch())),
        Positioned(left: 18, top: 18, child: _copy()),
        Positioned(right: 18, bottom: 18, child: _stamp()),
        Positioned(left: 0, right: 0, bottom: 18, child: Center(child: _controls())),
      ],
    );
  }

  /// プレビューを歪めずに画面いっぱいに収める。
  ///
  /// CameraPreview はセンサーの縦横比で描くので、縦向きでは画面と比率が合わない。
  /// 差のぶんだけ拡大して切り落とす（BoxFit.cover と同じ考え方）。
  Widget _fillPreview(BuildContext context, CameraController controller) {
    final screen = MediaQuery.sizeOf(context);
    var scale = screen.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    return ClipRect(
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.center,
        child: Center(child: CameraPreview(controller)),
      ),
    );
  }

  /// 8mm はセピア寄り・彩度低めにして、モックの質感に寄せる。
  Widget _previewFilter(Widget child) {
    if (_mode == PostKind.film35mm) return child;
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

  Widget _modeSwitch() {
    return Container(
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 190),
      decoration: BoxDecoration(
        color: BloomColors.scrim.withValues(alpha: 0.68),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(BloomRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mode in PostKind.values)
            GestureDetector(
              onTap: () => _setMode(mode),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 19, vertical: 9),
                decoration: BoxDecoration(
                  color: _mode == mode ? const Color(0xFFF1EFED) : null,
                  borderRadius: BorderRadius.circular(BloomRadius.pill),
                ),
                child: Text(
                  mode.wire,
                  style: BloomText.labelLg.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _mode == mode
                        ? const Color(0xFF17181B)
                        : const Color(0xFFA6A8AF),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _copy() {
    final (title, body) = switch ((_mode, _captured != null, _recording)) {
      (_, _, true) => ('', '2秒だけ撮影中…'),
      (PostKind.film35mm, true, _) => ('', 'この一枚で残す？'),
      (PostKind.film8mm, true, _) => ('', '2秒の記憶を残す？'),
      (PostKind.film35mm, false, _) => ('35mm', 'その瞬間を一枚。'),
      (PostKind.film8mm, false, _) => ('8mm', '2秒だけ、動く記憶。'),
    };

    return SizedBox(
      width: 170,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              style: BloomText.bodySm.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          Text(
            body,
            style: BloomText.bodySm.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
        ],
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

  Widget _controls() {
    final taken = _captured != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 92,
          child: taken
              ? _sideButton('撮り直す', _retake, primary: false)
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: 15),
        _shutter(),
        const SizedBox(width: 15),
        SizedBox(
          width: 92,
          child: taken
              ? _sideButton(
                  _uploading ? '投稿中…' : '投稿',
                  _uploading ? null : _post,
                  primary: true,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _sideButton(String label, VoidCallback? onTap, {required bool primary}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
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
          style: BloomText.labelMd.copyWith(
            color: primary ? const Color(0xFF1D0B00) : const Color(0xFFF0EEEE),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _shutter() {
    final isVideo = _mode == PostKind.film8mm;
    return GestureDetector(
      onTap: _captured == null ? _shoot : null,
      child: Container(
        width: 72,
        height: 72,
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
          width: isVideo ? 29 : 49,
          height: isVideo ? 29 : 49,
          decoration: BoxDecoration(
            color: isVideo ? const Color(0xFFEE5D64) : const Color(0xFFF3F1EF),
            borderRadius: BorderRadius.circular(isVideo ? 8 : 999),
          ),
        ),
      ),
    );
  }
}

class _RecordChip extends StatelessWidget {
  const _RecordChip();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 17,
      top: 17,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: BloomColors.scrim.withValues(alpha: 0.66),
          borderRadius: BorderRadius.circular(BloomRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFFEE5D64),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '2 SEC',
              style: BloomText.labelSm.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
