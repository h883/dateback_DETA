import 'package:flutter/material.dart';

import '../api/bloom_api.dart';
import '../models/models.dart';
import '../theme/bloom_theme.dart';
import '../widgets/film_effects.dart';
import '../widgets/post_media.dart';
import '../widgets/remote_image.dart';

/// ホームでメディアを長押ししたときに開く、その人のログ。
/// ここに出るのは閲覧可能な投稿だけ（サーバーが絞っている）。
class UserLogOverlay extends StatelessWidget {
  const UserLogOverlay({super.key, required this.api, required this.author});

  final BloomApi api;
  final AuthorFeed author;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog.fullscreen(
      backgroundColor: colors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 7, 18, 14),
              child: Row(
                children: [
                  RemoteAvatar(api: api, path: author.avatarPath),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      author.username,
                      style: BloomText.bodyLg.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: colors.secondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 26),
                itemCount: author.posts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 18),
                itemBuilder: (context, i) => _LogItem(
                  api: api,
                  post: author.posts[i],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogItem extends StatelessWidget {
  const _LogItem({required this.api, required this.post});

  final BloomApi api;
  final Post post;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AspectRatio(
      aspectRatio: 3 / 2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            // メディアの背景は他画面と同じく光/暗テーマに関わらず固定
            // (Quiet Analog のフィルム台紙の質感)。
            color: const Color(0xFF0E1013),
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Film8mmEffects(
                active: post.kind.isVideo,
                child: PostMedia(api: api, post: post),
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
    );
  }
}
