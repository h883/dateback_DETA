import 'package:flutter/material.dart';

import '../api/bloom_api.dart';
import '../models/models.dart';
import '../proximity/proximity_service.dart';
import '../theme/bloom_theme.dart';
import '../widgets/remote_image.dart';
import '../widgets/wordmark.dart';
import 'friend_add_sheet.dart';
import 'other_profile_screen.dart';

/// フレンド一覧(仕様書 12.2 / v15)。
///
/// v15 の仕様に合わせ、各フレンドは「アバター + 名前」だけのシンプルな行で
/// 表示する(「◯◯までの投稿が見られます」のような説明は出さない)。
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({
    super.key,
    required this.api,
    required this.proximity,
    required this.onToast,
  });

  final BloomApi api;
  final ProximityService proximity;
  final void Function(String message) onToast;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  List<Friend> _friends = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final friends = await widget.api.fetchFriends();
      if (!mounted) return;
      setState(() {
        _friends = friends;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onToast('読み込めませんでした');
    }
  }

  Future<void> _openAddSheet() async {
    await showFriendAddSheet(
      context,
      api: widget.api,
      proximity: widget.proximity,
      onToast: widget.onToast,
    );
    // シートを閉じたらこの一覧画面へそのまま戻る。追加・成立していれば
    // 反映されるよう読み直す。
    if (mounted) _load();
  }

  Future<void> _openProfile(String uid) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OtherProfileScreen(
          api: widget.api,
          uid: uid,
          onToast: widget.onToast,
        ),
      ),
    );
    // OtherProfileScreen でフレンド解除が成功しているかもしれないので、
    // 戻ってきたら一覧を読み直す(何も変わっていなければ無害な no-op)。
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _header(colors),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'フレンド',
                  style:
                      BloomText.headlineSm.copyWith(color: colors.onSurface),
                ),
              ),
            ),
            Expanded(child: _body(colors)),
          ],
        ),
      ),
    );
  }

  Widget _header(BloomColorsExt colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 14, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(
                  Icons.arrow_back_ios_new,
                  size: 18,
                  color: colors.onSurface,
                ),
              ),
              const Wordmark(),
            ],
          ),
          GestureDetector(
            onTap: _openAddSheet,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.surfaceContainerLow,
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Icon(
                Icons.person_add_alt_1_outlined,
                size: 20,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BloomColorsExt colors) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: colors.primary));
    }
    if (_friends.isEmpty) {
      return _emptyState(colors);
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: colors.primary,
      backgroundColor: colors.surfaceContainerHigh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 26),
        itemCount: _friends.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: colors.outlineVariant),
        itemBuilder: (context, i) => _FriendRow(
          api: widget.api,
          friend: _friends[i],
          onTap: () => _openProfile(_friends[i].profile.uid),
        ),
      ),
    );
  }

  /// フレンドが0人のとき。person+ から直接シートを開けるようにする。
  Widget _emptyState(BloomColorsExt colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.surfaceContainerLow,
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Icon(
                Icons.person_add_alt_1_outlined,
                color: colors.onSurface,
                size: 26,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'まだフレンドがいません',
              style: BloomText.headlineSm.copyWith(color: colors.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              '近くの人を探すと、フレンド申請を送れます。',
              style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: _openAddSheet,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  border: Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(BloomRadius.pill),
                ),
                child: Text(
                  '近くの人を探す',
                  style: BloomText.labelMd.copyWith(color: colors.onSurface),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.api,
    required this.friend,
    required this.onTap,
  });

  final BloomApi api;
  final Friend friend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            RemoteAvatar(api: api, path: friend.profile.avatarPath, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                friend.profile.username,
                style: BloomText.labelLg.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
