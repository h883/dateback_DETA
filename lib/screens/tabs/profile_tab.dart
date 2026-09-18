import 'package:flutter/material.dart';

import '../../api/bloom_api.dart';
import '../../models/models.dart';
import '../../proximity/proximity_service.dart';
import '../../theme/bloom_theme.dart';
import '../../widgets/post_media.dart';
import '../../widgets/remote_image.dart';
import '../../widgets/wordmark.dart';
import '../friends_screen.dart';
import '../post_viewer_screen.dart';
import '../profile_setup_screen.dart';

/// プロフィール画面（仕様書 12）。自分の情報・自分の投稿・フレンド一覧。
///
/// v15 は全画面共通のトップバーを持たず、Profile が自前でヘッダー
/// （wordmark・ハンバーガーメニュー）を描画する。設定ドロワーは
/// MainShell 自身の Scaffold(endDrawer)に持たせているため、ハンバーガーは
/// [onOpenSettings] を呼ぶだけ(画面全体を覆う一枚のドロワーにするため)。
class ProfileTab extends StatefulWidget {
  const ProfileTab({
    super.key,
    required this.api,
    required this.profile,
    required this.onProfileChanged,
    required this.onToast,
    required this.proximity,
    required this.onOpenSettings,
  });

  final BloomApi api;
  final Profile profile;
  final void Function(Profile profile) onProfileChanged;

  /// フレンド一覧からフレンド追加シートを開くために渡す
  /// （MainShell が保持する常時スキャン中のインスタンスをそのまま使う）。
  final ProximityService proximity;
  final void Function(String message) onToast;
  final VoidCallback onOpenSettings;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  List<Post> _posts = const [];
  List<Friend> _friends = const [];
  bool _loading = true;

  /// 投稿・フレンドどちらか一方でも取得に失敗したときの表示用。
  /// 片方だけ更新して片方は古い値を残すと「フレンド0人」等の誤解を招くため、
  /// 両方まとめて取得できたときだけ両方を更新する([Future.wait])。
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final results = await Future.wait<Object>([
        widget.api.fetchMyPosts(),
        widget.api.fetchFriends(),
      ]);
      if (!mounted) return;
      setState(() {
        _posts = results[0] as List<Post>;
        _friends = results[1] as List<Friend>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
      widget.onToast('読み込めませんでした');
    }
  }

  /// loading/error 中は「0」を架空の確定値として出さないための表示用文字列。
  /// (`_posts`/`_friends` は取得に成功したときしか更新しないので、
  /// 数値そのものは信頼できるが、まだ一度も読み込めていない/失敗した
  /// 直後はプレースホルダにする)
  String _statValue(int count) {
    if (_loading) return '…';
    if (_error) return '—';
    return '$count';
  }

  Future<void> _edit() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProfileSetupScreen(
          api: widget.api,
          initial: widget.profile,
          onDone: (profile) {
            widget.onProfileChanged(profile);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _openFriends() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FriendsScreen(
          api: widget.api,
          proximity: widget.proximity,
          onToast: widget.onToast,
        ),
      ),
    );
    // フレンドを追加・削除して戻ってきているかもしれないので数を更新する。
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final colors = context.colors;

    return Column(
      children: [
        _header(),
        Expanded(
          child: RefreshIndicator(
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
                        style: BloomText.bodySm
                            .copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: _edit,
                icon: Icon(Icons.edit_outlined,
                    color: colors.onSurfaceVariant, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: colors.outlineVariant, height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatLabel(
                colors: colors,
                text: '投稿 ${_statValue(_posts.length)}',
              ),
              const SizedBox(width: 22),
              _StatLabel(
                colors: colors,
                text: 'フレンド ${_statValue(_friends.length)}',
                onTap: _openFriends,
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(
                  color: colors.primary,
                ),
              ),
            )
          else if (_error)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '読み込めませんでした',
                      style: BloomText.bodySm
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: BloomSpace.sm),
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
            )
          else if (_posts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'まだ投稿がありません',
                  style: BloomText.bodySm
                      .copyWith(color: colors.onSurfaceVariant),
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
                  isOwn: true,
                ),
                child: _GridTile(
                  api: widget.api,
                  post: _posts[i],
                ),
              ),
            ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 14, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Wordmark(),
          GestureDetector(
            onTap: widget.onOpenSettings,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              child: Icon(Icons.menu, size: 22, color: context.colors.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

/// プロフィール本文の stats 行（「投稿 N」「フレンド N」）に使う 1 項目。
/// [onTap] を渡すとタップ可能になる(フレンド → FriendsScreen)。
/// 投稿数側は [onTap] を渡さないのでタップ不可。
class _StatLabel extends StatelessWidget {
  const _StatLabel({required this.colors, required this.text, this.onTap});

  final BloomColorsExt colors;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      style: BloomText.labelLg.copyWith(
        fontWeight: FontWeight.w700,
        color: colors.onSurface,
      ),
    );
    if (onTap == null) return label;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: label,
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
