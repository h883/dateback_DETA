import 'package:flutter/material.dart';

import '../api/bloom_api.dart';
import '../models/models.dart';
import '../theme/bloom_theme.dart';
import '../widgets/remote_image.dart';

/// アプリ内の通知一覧。
///
/// フレンド申請・フレンド成立・閲覧権限の交換（仕様書 F-12）・いいねが並ぶ。
/// 開いた時点でまとめて既読にする。
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.api,
    required this.onRead,
  });

  final BloomApi api;

  /// 既読にしたあと、呼び出し側のバッジを消すために呼ぶ。
  final VoidCallback onRead;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  NotificationFeed _feed = NotificationFeed.empty;
  bool _loading = true;
  String? _error;

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
      final feed = await widget.api.fetchNotifications();
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _loading = false;
      });

      // 開いたら既読にする。失敗しても一覧は見せる。
      if (feed.unreadCount > 0) {
        try {
          await widget.api.markNotificationsRead();
          widget.onRead();
        } catch (_) {
          // 次に開いたときに再試行される。
        }
      }
    } on BloomApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '読み込めませんでした: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: colors.surface,
        title: Text('お知らせ',
            style: BloomText.headlineSm.copyWith(color: colors.onSurface)),
        iconTheme: IconThemeData(color: colors.onSurface),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: colors.primary,
        backgroundColor: colors.surfaceContainerHigh,
        child: _body(colors),
      ),
    );
  }

  Widget _body(BloomColorsExt colors) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: colors.primary),
      );
    }

    final error = _error;
    if (error != null) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          Text(
            error,
            style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: BloomSpace.md),
          Center(
            child: TextButton(
              onPressed: _load,
              child: Text(
                '再試行',
                style: BloomText.labelMd.copyWith(color: colors.primary),
              ),
            ),
          ),
        ],
      );
    }

    if (_feed.notifications.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 80),
          Text(
            'お知らせはまだありません',
            style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 26),
      itemCount: _feed.notifications.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final item = _feed.notifications[i];
        return _NotificationRow(
          key: ValueKey(item.id),
          api: widget.api,
          item: item,
          onHandled: () => _removeNotification(item.id),
        );
      },
    );
  }

  /// フレンド申請を承認・拒否したあと、その通知をその場で消す
  /// （v15 と同じ挙動。承認/拒否済みの申請ボタンを残して誤操作させない）。
  void _removeNotification(String id) {
    setState(() {
      _feed = NotificationFeed(
        notifications:
            _feed.notifications.where((n) => n.id != id).toList(),
        unreadCount: _feed.unreadCount,
      );
    });
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    super.key,
    required this.api,
    required this.item,
    required this.onHandled,
  });

  final BloomApi api;
  final AppNotification item;

  /// フレンド申請の承認・拒否が成功したときに呼ぶ。
  final VoidCallback onHandled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final actorUid = item.actorUid;
    final canRespond =
        item.kind == NotificationKind.friendRequest && actorUid != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // 未読は少し明るくして見分けられるようにする。
        color: item.read
            ? colors.surfaceContainerLow
            : colors.surfaceContainerHigh,
        border: Border.all(
          color: item.read
              ? colors.outlineVariant
              : colors.primary.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(BloomRadius.base),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RemoteAvatar(api: api, path: item.actorAvatarPath, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.message,
                  style: BloomText.bodySm.copyWith(color: colors.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  _relativeTime(item.createdAt),
                  style: BloomText.labelSm
                      .copyWith(color: colors.onSurfaceVariant),
                ),
                if (canRespond)
                  _FriendRequestActions(
                    api: api,
                    actorUid: actorUid,
                    onHandled: onHandled,
                  ),
              ],
            ),
          ),
          if (!item.read)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  static String _relativeTime(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'たったいま';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
    if (diff.inHours < 24) return '${diff.inHours}時間前';
    if (diff.inDays < 7) return '${diff.inDays}日前';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}/${two(at.month)}/${two(at.day)}';
  }
}

/// フレンド申請通知の「承認」「拒否」。v15 の `.notice-actions.compact-actions`
/// と同じ、通知カードの中に収まる小さなピル型ボタン。
///
/// 拒否は既存の [BloomApi.cancelFriendRequest]
/// （`DELETE /api/friends/requests/:uid`）をそのまま使う。このエンドポイントは
/// `workers/src/index.ts` の `handleFriends` で
/// `(requester=自分 AND addressee=相手) OR (requester=相手 AND addressee=自分)`
/// と対称に条件を見ており、送信済み申請の取り消しと受信申請の却下の両方に
/// 使える設計になっている。
class _FriendRequestActions extends StatefulWidget {
  const _FriendRequestActions({
    required this.api,
    required this.actorUid,
    required this.onHandled,
  });

  final BloomApi api;
  final String actorUid;
  final VoidCallback onHandled;

  @override
  State<_FriendRequestActions> createState() => _FriendRequestActionsState();
}

class _FriendRequestActionsState extends State<_FriendRequestActions> {
  bool _processing = false;

  Future<void> _respond({required bool accept}) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      if (accept) {
        await widget.api.acceptFriend(widget.actorUid);
      } else {
        await widget.api.cancelFriendRequest(widget.actorUid);
      }
      if (!mounted) return;
      // 一覧からこの通知を消すのは呼び出し側（NotificationsScreen）の役目。
      // ここで setState(_processing = false) はしない
      // （消える直前の行にまだボタンが見えて押し直せてしまうのを防ぐ）。
      widget.onHandled();
    } on BloomApiException catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      _showError(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _processing = false);
      _showError(accept ? '承認できませんでした' : '拒否できませんでした');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (_processing) {
      return const Padding(
        padding: EdgeInsets.only(top: 9),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionPill(
            label: '承認',
            background: colors.onSurface,
            foreground: colors.surface,
            onTap: () => _respond(accept: true),
          ),
          const SizedBox(width: 6),
          _ActionPill(
            label: '拒否',
            background: colors.surfaceContainer,
            foreground: colors.onSurface,
            onTap: () => _respond(accept: false),
          ),
        ],
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(BloomRadius.pill),
        ),
        child: Text(
          label,
          style:
              BloomText.labelSm.copyWith(color: foreground, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
