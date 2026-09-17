import 'package:flutter/material.dart';

import '../api/bloom_api.dart';
import '../models/models.dart';
import '../theme/bloom_theme.dart';
import '../widgets/post_media.dart';
import '../widgets/remote_image.dart';
import 'post_viewer_screen.dart';

/// 他ユーザーのプロフィール画面。
///
/// 自分用の [ProfileTab] とは違い、プロフィール編集・ハンバーガー
/// (Settings)・ログアウトなど自分専用の操作は一切出さない。
///
/// 表示する投稿は常にバックエンドが「今この viewer に」返す閲覧可能投稿
/// だけ([BloomApi.fetchUserPosts])。Flutter 側で `visible_until` や
/// 投稿時刻を独自に判定しない(既存の閲覧権限制御をそのまま利用する)。
class OtherProfileScreen extends StatefulWidget {
  const OtherProfileScreen({
    super.key,
    required this.api,
    required this.uid,
    required this.onToast,
  });

  final BloomApi api;
  final String uid;
  final void Function(String message) onToast;

  @override
  State<OtherProfileScreen> createState() => _OtherProfileScreenState();
}

class _OtherProfileScreenState extends State<OtherProfileScreen> {
  Profile? _profile;
  List<Post> _posts = const [];

  /// フレンド一覧に含まれているかどうか(フレンド解除の表示可否にのみ使う)。
  /// 他ユーザーの友達数のような統計は、専用APIが無いため出さない。
  bool _isFriend = false;

  bool _loading = true;
  String? _error;

  /// 解除APIの二重タップ防止。
  bool _removingFriend = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        widget.api.fetchUserProfile(widget.uid),
        widget.api.fetchUserPosts(widget.uid),
        widget.api.fetchFriends(),
      ]);
      if (!mounted) return;
      final profile = results[0] as Profile;
      final posts = results[1] as List<Post>;
      final friends = results[2] as List<Friend>;
      setState(() {
        _profile = profile;
        _posts = posts;
        _isFriend = friends.any((f) => f.profile.uid == widget.uid);
        _loading = false;
      });
    } on BloomApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            e.code == 'not_visible' ? 'このプロフィールは閲覧できません' : '読み込めませんでした';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '読み込めませんでした';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(child: Column(children: [_header(colors), Expanded(child: _body(colors))])),
    );
  }

  Widget _header(BloomColorsExt colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 14, 6),
      child: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: Icon(Icons.arrow_back_ios_new, size: 18, color: colors.onSurface),
      ),
    );
  }

  Widget _body(BloomColorsExt colors) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: colors.primary));
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error,
                style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: BloomSpace.md),
              TextButton(
                onPressed: _load,
                child: Text(
                  '再試行',
                  style: BloomText.labelMd.copyWith(color: colors.primary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final profile = _profile!;
    return RefreshIndicator(
      onRefresh: _load,
      color: colors.primary,
      backgroundColor: colors.surfaceContainerHigh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 26),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              RemoteAvatar(api: widget.api, path: profile.avatarPath, size: 74),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.username,
                      style: BloomText.headlineMd.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    if (profile.bio.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        profile.bio,
                        style:
                            BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: colors.outlineVariant, height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                '投稿 ${_posts.length}件',
                style: BloomText.labelLg.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              if (_isFriend) ...[
                const Spacer(),
                _unfriendLabel(colors),
              ],
            ],
          ),
          const SizedBox(height: 18),
          if (_posts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'まだ見られる投稿がありません',
                  style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 9,
                crossAxisSpacing: 9,
                childAspectRatio: 3 / 2,
              ),
              itemCount: _posts.length,
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => showPostViewer(
                  context,
                  api: widget.api,
                  posts: _posts,
                  initialIndex: i,
                  onToast: widget.onToast,
                  isOwn: false,
                ),
                child: _GridTile(api: widget.api, post: _posts[i]),
              ),
            ),
        ],
      ),
    );
  }

  /// 確認 → `DELETE /api/friends/:uid` → 成功したら前画面へ戻る。
  /// 失敗時はこの画面のまま留まり、トーストで伝える(成功扱いにしない)。
  Future<void> _confirmUnfriend(BloomColorsExt colors) async {
    if (_removingFriend) return;
    final profile = _profile;
    if (profile == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _UnfriendConfirmDialog(username: profile.username),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _removingFriend = true);
    try {
      await widget.api.removeFriend(widget.uid);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _removingFriend = false);
      widget.onToast('フレンド解除に失敗しました');
    }
  }

  /// 控えめな赤系テキスト。タップで確認ダイアログを出す。
  Widget _unfriendLabel(BloomColorsExt colors) {
    return GestureDetector(
      onTap: _removingFriend ? null : () => _confirmUnfriend(colors),
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: _removingFriend ? 0.5 : 1,
        child: Text(
          'フレンド解除',
          style: BloomText.labelSm.copyWith(color: colors.error),
        ),
      ),
    );
  }
}

/// フレンド解除の確認ダイアログ([SettingsDrawer] のログアウト確認と
/// 同じ見た目の方針。解除は取り消せる操作ではないため確認色を赤系にする)。
class _UnfriendConfirmDialog extends StatelessWidget {
  const _UnfriendConfirmDialog({required this.username});

  final String username;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.surfaceContainerLow,
      title: Text(
        'フレンドを解除しますか?',
        style: BloomText.headlineSm.copyWith(color: colors.onSurface),
      ),
      content: Text(
        '$username さんとのフレンド関係を解除します。',
        style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('キャンセル', style: TextStyle(color: colors.onSurfaceVariant)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('解除する', style: TextStyle(color: colors.error)),
        ),
      ],
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.api, required this.post});

  final BloomApi api;
  final Post post;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PostMedia(api: api, post: post, playVideo: false),
          Positioned(
            right: 8,
            bottom: 7,
            child: Text(
              post.stamp,
              style: BloomText.labelSm.copyWith(
                color: colors.primary,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
