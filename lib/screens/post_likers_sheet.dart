import 'package:flutter/material.dart';

import '../api/bloom_api.dart';
import '../models/models.dart';
import '../theme/bloom_theme.dart';
import '../widgets/remote_image.dart';

/// いいねした人一覧のボトムシート(B1)。
///
/// [postId] の一覧は開いたときに初めて取得する(投稿一覧取得時にまとめて
/// 先読みしない)。他ユーザーのプロフィール専用画面はまだ無いため、行を
/// タップしても [FriendsScreen] の行タップと同じプレースホルダを出すだけ
/// にとどめる(正式な遷移は未実装)。
Future<void> showPostLikersSheet(
  BuildContext context, {
  required BloomApi api,
  required String postId,
  required void Function(String message) onToast,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _PostLikersSheet(api: api, postId: postId, onToast: onToast),
  );
}

class _PostLikersSheet extends StatefulWidget {
  const _PostLikersSheet({
    required this.api,
    required this.postId,
    required this.onToast,
  });

  final BloomApi api;
  final String postId;
  final void Function(String message) onToast;

  @override
  State<_PostLikersSheet> createState() => _PostLikersSheetState();
}

class _PostLikersSheetState extends State<_PostLikersSheet> {
  List<Profile>? _likers;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final likers = await widget.api.fetchLikers(widget.postId);
      if (!mounted) return;
      setState(() => _likers = likers);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  /// 他ユーザーのプロフィール専用画面はまだ無い([FriendsScreen] の
  /// 行タップと同じ扱い)。
  void _openProfilePlaceholder() {
    widget.onToast('プロフィール表示は近日対応します');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(BloomRadius.lg)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: colors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'いいねした人',
              style: BloomText.headlineSm.copyWith(color: colors.onSurface),
            ),
            const SizedBox(height: 12),
            Flexible(child: _content(colors)),
          ],
        ),
      ),
    );
  }

  Widget _content(BloomColorsExt colors) {
    final likers = _likers;
    if (likers == null) {
      if (_failed) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              '読み込めませんでした',
              style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        );
      }
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (likers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'まだいいねがありません',
            style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: likers.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: colors.outlineVariant),
      itemBuilder: (context, i) => _LikerRow(
        api: widget.api,
        profile: likers[i],
        onTap: _openProfilePlaceholder,
      ),
    );
  }
}

class _LikerRow extends StatelessWidget {
  const _LikerRow({required this.api, required this.profile, required this.onTap});

  final BloomApi api;
  final Profile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            RemoteAvatar(api: api, path: profile.avatarPath, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                profile.username,
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
