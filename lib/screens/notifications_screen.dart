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
    return Scaffold(
      backgroundColor: BloomColors.surface,
      appBar: AppBar(
        backgroundColor: BloomColors.surface,
        surfaceTintColor: BloomColors.surface,
        title: Text('お知らせ', style: BloomText.headlineSm),
        iconTheme: const IconThemeData(color: BloomColors.onSurface),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: BloomColors.primaryContainer,
        backgroundColor: BloomColors.surfaceContainerHigh,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: BloomColors.primaryContainer),
      );
    }

    final error = _error;
    if (error != null) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          Text(
            error,
            style: BloomText.bodySm.copyWith(color: BloomColors.secondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: BloomSpace.md),
          Center(
            child: TextButton(
              onPressed: _load,
              child: Text(
                '再試行',
                style: BloomText.labelMd.copyWith(color: BloomColors.primary),
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
            style: BloomText.bodySm.copyWith(color: BloomColors.secondary),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 26),
      itemCount: _feed.notifications.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) =>
          _NotificationRow(api: widget.api, item: _feed.notifications[i]),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.api, required this.item});

  final BloomApi api;
  final AppNotification item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // 未読は少し明るくして見分けられるようにする。
        color: item.read
            ? BloomColors.surfaceContainerLow
            : BloomColors.surfaceContainerHigh,
        border: Border.all(
          color: item.read
              ? BloomColors.outlineVariant
              : BloomColors.primaryContainer.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(BloomRadius.base),
      ),
      child: Row(
        children: [
          RemoteAvatar(api: api, path: item.actorAvatarPath, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.message, style: BloomText.bodySm),
                const SizedBox(height: 2),
                Text(
                  _relativeTime(item.createdAt),
                  style: BloomText.labelSm
                      .copyWith(color: BloomColors.secondary),
                ),
              ],
            ),
          ),
          if (!item.read)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(left: 8),
              decoration: const BoxDecoration(
                color: BloomColors.primaryContainer,
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
