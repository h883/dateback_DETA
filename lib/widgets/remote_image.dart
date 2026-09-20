import 'package:flutter/material.dart';

import '../api/bloom_api.dart';
import '../theme/bloom_theme.dart';

/// API 経由のメディアは Bearer トークンが要るので、ヘッダを付けて読む。
///
/// ID トークンは期限付きなので毎回 [BloomApi.mediaHeaders] を引き直す。
/// 取得は非同期なので、揃うまでは [placeholder] を出す。
///
/// メディアの実体は Cloudflare KV にあり、KV は結果整合性なので「投稿した
/// 直後に自分の写真を開く」と、まだ伝播が終わっておらず 404 が返ることが
/// ある。これは恒久的な失敗ではないので、404 のときだけ間を置いて読み直す
/// ([_retryBackoff])。403(閲覧権限なし)や 401 は待っても変わらないため
/// 再試行しない。
class RemoteImage extends StatefulWidget {
  const RemoteImage({
    super.key,
    required this.api,
    required this.path,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  final BloomApi api;

  /// API の相対パス（例: /api/media/posts/xxx）。
  final String path;
  final BoxFit fit;
  final Widget? placeholder;

  @override
  State<RemoteImage> createState() => _RemoteImageState();
}

class _RemoteImageState extends State<RemoteImage> {
  /// KV の伝播待ちで 404 になったときに読み直す間隔。長さがそのまま
  /// 再試行回数になる。伝播は通常数秒で終わるので、合計10秒で諦める。
  static const _retryBackoff = [
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 6),
  ];

  late Future<Map<String, String>> _headers = widget.api.mediaHeaders();

  /// 何回目の読み直しか。[Image] の key に混ぜて、確実に読み直させる。
  int _attempt = 0;

  /// 再試行を予約済みかどうか。errorBuilder は1回の失敗で複数回呼ばれ
  /// うるので、二重に予約しないための見張り。
  bool _retryScheduled = false;

  @override
  void didUpdateWidget(RemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      _headers = widget.api.mediaHeaders();
    }
    if (oldWidget.path != widget.path) {
      _attempt = 0;
      _retryScheduled = false;
    }
  }

  /// KV の伝播待ち(404)だったときだけ、間を置いて読み直す。
  void _scheduleRetryIfPropagating(Object error) {
    if (_retryScheduled) return;
    if (error is! NetworkImageLoadException || error.statusCode != 404) return;
    if (_attempt >= _retryBackoff.length) return;

    _retryScheduled = true;
    Future<void>.delayed(_retryBackoff[_attempt], () {
      if (!mounted) return;
      setState(() {
        _attempt++;
        _retryScheduled = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final fallback = widget.placeholder ?? const _MediaPlaceholder();

    return FutureBuilder<Map<String, String>>(
      future: _headers,
      builder: (context, snapshot) {
        final headers = snapshot.data;
        if (headers == null) return fallback;
        return Image.network(
          widget.api.mediaUrl(widget.path),
          key: ValueKey(_attempt),
          headers: headers,
          fit: widget.fit,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : fallback,
          errorBuilder: (context, error, stack) {
            _scheduleRetryIfPropagating(error);
            return fallback;
          },
        );
      },
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1412), Color(0xFF2A1D18), Color(0xFF1F1714)],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

/// 丸いアイコン。画像が無ければデザインどおりのグラデーションを出す。
class RemoteAvatar extends StatelessWidget {
  const RemoteAvatar({
    super.key,
    required this.api,
    required this.path,
    this.size = 31,
  });

  final BloomApi api;
  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatarPath = path;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.outlineVariant),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A4540), Color(0xFF1B1D22)],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatarPath == null
          ? null
          : RemoteImage(
              api: api,
              path: avatarPath,
              placeholder: const SizedBox.shrink(),
            ),
    );
  }
}
