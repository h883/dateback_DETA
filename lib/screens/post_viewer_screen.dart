import 'package:flutter/material.dart';

import '../api/bloom_api.dart';
import '../models/models.dart';
import '../theme/bloom_theme.dart';
import '../widgets/film_effects.dart';
import '../widgets/post_media.dart';
import 'post_likers_sheet.dart';

/// 投稿ビューアーを開く。
///
/// Own Profile のグリッドタップ、Phase 6 の投稿完了後「投稿を見る」など、
/// どこからでも同じビューアーを呼び出せるようにするための入口。
/// `showDialog` + `Dialog.fullscreen` は既存の [UserLogOverlay] と同じ
/// 提示方法。
Future<void> showPostViewer(
  BuildContext context, {
  required BloomApi api,
  required List<Post> posts,
  required int initialIndex,
  required void Function(String message) onToast,
  bool isOwn = false,
}) {
  if (posts.isEmpty) return Future<void>.value();
  return showDialog<void>(
    context: context,
    barrierColor: context.colors.scrim.withValues(alpha: 0.9),
    builder: (_) => PostViewerScreen(
      api: api,
      posts: posts,
      initialIndex: initialIndex,
      isOwn: isOwn,
      onToast: onToast,
    ),
  );
}

/// 投稿ビューアー本体(v15 の `#viewer`)。
///
/// [isOwn] が true のときだけ「自分の投稿ビュー」特有の操作になる:
/// メディアタップで1つ古い投稿へ進み、最古の投稿でタップすると閉じる。
/// 右下の「♥ 件数」表示(B1)も [isOwn] のときだけ出し、タップすると
/// いいねした人一覧のシートを開く(自分の投稿へいいねする操作ではない)。
///
/// [isOwn] が false の場合(他人の投稿ビュー)は、このフェーズではまだ
/// 対応する画面が無いため、メディアタップ・いいね表示は出さない
/// (縦スワイプでの移動と閉じる操作は isOwn に関係なく使える)。
class PostViewerScreen extends StatefulWidget {
  const PostViewerScreen({
    super.key,
    required this.api,
    required this.posts,
    required this.initialIndex,
    required this.onToast,
    this.isOwn = false,
  });

  final BloomApi api;
  final List<Post> posts;
  final int initialIndex;
  final bool isOwn;
  final void Function(String message) onToast;

  @override
  State<PostViewerScreen> createState() => _PostViewerScreenState();
}

class _PostViewerScreenState extends State<PostViewerScreen> {
  late int _index =
      widget.initialIndex.clamp(0, widget.posts.length - 1).toInt();

  double _dragY = 0;

  static const _swipeThreshold = 45.0;

  void _close() => Navigator.of(context).pop();

  void _goTo(int index) => setState(() => _index = index);

  void _onVerticalDragEnd(DragEndDetails details) {
    final dy = _dragY;
    _dragY = 0;
    if (dy.abs() < _swipeThreshold) return;

    // 縦スワイプでの投稿移動(既存仕様どおり循環する)。
    // 上スワイプ(dy<0)=古い方へ、下スワイプ=新しい方へ。
    final total = widget.posts.length;
    if (total < 2) return;
    final delta = dy < 0 ? 1 : -1;
    _goTo((_index + delta + total) % total);
  }

  /// メディアタップ。自分の投稿ビューだけの挙動。
  void _onTapMedia() {
    if (!widget.isOwn) return;
    if (_index < widget.posts.length - 1) {
      _goTo(_index + 1); // 1つ古い投稿へ
    } else {
      _close(); // すでに最古の投稿を表示中
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final post = widget.posts[_index];

    return Dialog.fullscreen(
      backgroundColor: colors.surface,
      child: GestureDetector(
        onVerticalDragStart: (_) => _dragY = 0,
        onVerticalDragUpdate: (d) => _dragY += d.delta.dy,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Stack(
          children: [
            // 余白タップで閉じる(メディア・Xボタン以外はすべてここに落ちる)。
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _header(colors),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (post.locationLabel != null) ...[
                              IgnorePointer(child: _location(colors, post)),
                              const SizedBox(height: 6),
                            ],
                            _media(colors, post),
                            const SizedBox(height: 8),
                            _meta(colors, post),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BloomColorsExt colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 18, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: _close,
            icon: Icon(Icons.close, color: colors.onSurface),
          ),
          Expanded(
            child: IgnorePointer(
              child: Text(
                '縦スワイプで投稿移動',
                textAlign: TextAlign.center,
                style:
                    BloomText.labelSm.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _media(BloomColorsExt colors, Post post) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTapMedia,
      child: AspectRatio(
        aspectRatio: 3 / 2,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(BloomRadius.md),
          child: Container(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Film8mmEffects(
                  active: post.kind.isVideo,
                  child: PostMedia(api: widget.api, post: post),
                ),
                Positioned(
                  right: 12,
                  bottom: 11,
                  child: Text(
                    post.stamp,
                    style: BloomText.labelMd.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// メディア上部の撮影地(B2)。無ければ呼び出し側がそもそも配置しない
  /// (余白も残さない)。
  Widget _location(BloomColorsExt colors, Post post) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.place_outlined, size: 12, color: colors.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          post.locationLabel!,
          style: BloomText.labelSm.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  /// 左: 現在位置 / 投稿総数(タップは背景の閉じる操作へ通す)。
  /// 右: 自分の投稿のときだけ ♥ 件数(B1、タップでいいねした人一覧)。
  Widget _meta(BloomColorsExt colors, Post post) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Expanded(
            child: IgnorePointer(
              child: Text(
                '${_index + 1} / ${widget.posts.length}',
                style:
                    BloomText.labelSm.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ),
          if (widget.isOwn) _likeCount(colors, post),
        ],
      ),
    );
  }

  /// 自分自身が自分の投稿へいいねする操作ではない。タップは
  /// いいねした人一覧のシートを開くだけ。
  Widget _likeCount(BloomColorsExt colors, Post post) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showPostLikersSheet(
        context,
        api: widget.api,
        postId: post.id,
        onToast: widget.onToast,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite, size: 15, color: colors.heart),
            const SizedBox(width: 4),
            Text(
              '${post.likeCount}',
              style: BloomText.labelSm.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
