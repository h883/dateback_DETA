import 'package:flutter/material.dart';

import '../../api/bloom_api.dart';
import '../../models/models.dart';
import '../../theme/bloom_theme.dart';
import '../../widgets/post_media.dart';
import '../../widgets/remote_image.dart';
import '../profile_setup_screen.dart';

/// プロフィール画面（仕様書 12）。自分の情報・自分の投稿・フレンド一覧。
class ProfileTab extends StatefulWidget {
  const ProfileTab({
    super.key,
    required this.api,
    required this.profile,
    required this.onProfileChanged,
    required this.onSignOut,
    required this.onToast,
  });

  final BloomApi api;
  final Profile profile;
  final void Function(Profile profile) onProfileChanged;
  final VoidCallback onSignOut;
  final void Function(String message) onToast;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  List<Post> _posts = const [];
  List<Friend> _friends = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final posts = await widget.api.fetchMyPosts();
      final friends = await widget.api.fetchFriends();
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _friends = friends;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onToast('読み込めませんでした');
    }
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

  void _showFriends() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: BloomColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(BloomRadius.lg)),
      ),
      builder: (_) => _FriendSheet(api: widget.api, friends: _friends),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;

    return RefreshIndicator(
      onRefresh: _load,
      color: BloomColors.primaryContainer,
      backgroundColor: BloomColors.surfaceContainerHigh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 26),
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
                      style: BloomText.headlineMd
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (profile.bio.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        profile.bio,
                        style: BloomText.bodySm
                            .copyWith(color: BloomColors.secondary),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: _edit,
                icon: const Icon(Icons.edit_outlined,
                    color: BloomColors.secondary, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: BloomColors.outlineVariant, height: 1),
          const SizedBox(height: 14),
          _rowButton(
            'フレンド ${_friends.length}人',
            onTap: _friends.isEmpty ? null : _showFriends,
          ),
          const SizedBox(height: 8),
          _rowButton('ログアウト', onTap: widget.onSignOut),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(
                  color: BloomColors.primaryContainer,
                ),
              ),
            )
          else if (_posts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'まだ投稿がありません',
                  style:
                      BloomText.bodySm.copyWith(color: BloomColors.secondary),
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
              itemBuilder: (context, i) => _GridTile(
                api: widget.api,
                post: _posts[i],
              ),
            ),
        ],
      ),
    );
  }

  Widget _rowButton(String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: BloomColors.surfaceContainerLow,
          border: Border.all(color: BloomColors.outlineVariant),
          borderRadius: BorderRadius.circular(BloomRadius.base),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: BloomText.labelLg.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: BloomColors.secondary),
          ],
        ),
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.api, required this.post});

  final BloomApi api;
  final Post post;

  @override
  Widget build(BuildContext context) {
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
                color: BloomColors.primaryContainer,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// フレンド一覧。各フレンドについて今どこまで見られるかも出す（仕様書 12.2）。
class _FriendSheet extends StatelessWidget {
  const _FriendSheet({required this.api, required this.friends});

  final BloomApi api;
  final List<Friend> friends;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.all(18),
        itemCount: friends.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final friend = friends[i];
          final until = friend.visibleUntil;
          return Row(
            children: [
              RemoteAvatar(api: api, path: friend.profile.avatarPath, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend.profile.username,
                      style: BloomText.labelLg
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      until == null
                          ? 'まだ会っていません'
                          : '${_formatDateTime(until)} までの投稿が見られます',
                      style: BloomText.labelSm
                          .copyWith(color: BloomColors.secondary),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _formatDateTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}/${two(dt.month)}/${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}
