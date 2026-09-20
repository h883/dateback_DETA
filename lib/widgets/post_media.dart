import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../api/bloom_api.dart';
import '../models/models.dart';
import '../theme/bloom_theme.dart';
import 'remote_image.dart';

/// 投稿のメディア。35mm は静止画、8mm は2秒の動画。
///
/// 一覧に並ぶ場所では動画プレイヤーを大量に持ちたくないので、
/// [playVideo] を false にすると動画でもサムネイル表示で済ませる。
class PostMedia extends StatelessWidget {
  const PostMedia({
    super.key,
    required this.api,
    required this.post,
    this.playVideo = true,
  });

  final BloomApi api;
  final Post post;
  final bool playVideo;

  @override
  Widget build(BuildContext context) {
    if (!post.kind.isVideo) {
      return RemoteImage(api: api, path: post.mediaPath);
    }
    if (!playVideo) return const _VideoThumbnail();
    return RemoteVideo(api: api, path: post.mediaPath);
  }
}

/// 認証ヘッダ付きで動画を読み、2秒クリップをループ再生する。
///
/// フィードなので音は出さない。撮影時の音声は残っているので、
/// 再生 UI を付けるならここで volume を上げる。
class RemoteVideo extends StatefulWidget {
  const RemoteVideo({super.key, required this.api, required this.path});

  final BloomApi api;
  final String path;

  @override
  State<RemoteVideo> createState() => _RemoteVideoState();
}

class _RemoteVideoState extends State<RemoteVideo> {
  /// メディアの実体がある Cloudflare KV は結果整合性なので、投稿した直後は
  /// まだ伝播が終わっておらず initialize() が失敗することがある。
  /// [RemoteImage] と違い video_player は HTTP ステータスを見せてくれない
  /// ため原因を区別できない。回数だけ絞って読み直す。
  static const _retryBackoff = [Duration(seconds: 2), Duration(seconds: 5)];

  VideoPlayerController? _controller;
  bool _failed = false;

  /// 何回読み直したか。path が変わったら 0 へ戻す。
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(RemoteVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _controller?.dispose();
      _controller = null;
      _failed = false;
      _attempt = 0;
      _open();
    }
  }

  Future<void> _open() async {
    // 再試行で待っている間に path が差し替わることがある。開き始めた対象を
    // 控えておき、途中で変わっていたら結果を捨てる(古い動画を新しい行へ
    // 出してしまわないようにする)。
    final opening = widget.path;
    try {
      final headers = await widget.api.mediaHeaders();
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.api.mediaUrl(opening)),
        httpHeaders: headers,
      );
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted || widget.path != opening) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      if (!mounted || widget.path != opening) return;
      // 伝播待ちの可能性があるうちは、間を置いて読み直す。
      if (_attempt < _retryBackoff.length) {
        final delay = _retryBackoff[_attempt];
        _attempt++;
        await Future<void>.delayed(delay);
        if (!mounted || widget.path != opening) return;
        await _open();
        return;
      }
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const _VideoThumbnail(label: '再生できませんでした');

    final controller = _controller;
    if (controller == null) return const _VideoThumbnail();

    // 3:2 の枠に合わせて中央を切り出す。
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

/// 動画の代わりに出す暗いタイル。読み込み中と一覧のサムネイルで共用する。
class _VideoThumbnail extends StatelessWidget {
  const _VideoThumbnail({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1412), Color(0xFF2A1D18), Color(0xFF1F1714)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_circle_outline,
              color: BloomColors.secondary,
              size: 30,
            ),
            if (label != null) ...[
              const SizedBox(height: 6),
              Text(
                label!,
                style:
                    BloomText.labelSm.copyWith(color: BloomColors.secondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
