import 'package:flutter/material.dart';

import '../api/bloom_api.dart';
import '../theme/bloom_theme.dart';

/// API 経由のメディアは Bearer トークンが要るので、ヘッダを付けて読む。
///
/// ID トークンは期限付きなので毎回 [BloomApi.mediaHeaders] を引き直す。
/// 取得は非同期なので、揃うまでは [placeholder] を出す。
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
  late Future<Map<String, String>> _headers = widget.api.mediaHeaders();

  @override
  void didUpdateWidget(RemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      _headers = widget.api.mediaHeaders();
    }
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
          headers: headers,
          fit: widget.fit,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : fallback,
          errorBuilder: (context, error, stack) => fallback,
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
