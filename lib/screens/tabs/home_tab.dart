import 'package:flutter/material.dart';

import '../../api/bloom_api.dart';
import '../../models/models.dart';
import '../../proximity/proximity_service.dart';
import '../../theme/bloom_theme.dart';
import '../../widgets/film_effects.dart';
import '../../widgets/post_media.dart';
import '../../widgets/remote_image.dart';
import '../../widgets/wordmark.dart';
import '../friend_add_sheet.dart';
import '../other_profile_screen.dart';
import '../user_log_overlay.dart';

/// ホーム画面（仕様書 10）。
///
/// - 縦フリック上下で投稿者を切り替える
/// - メディアをタップで同じ人の過去の投稿へ
/// - メディア長押しでその人のログを開く
/// - 最上部から下へ引っ張ると近距離の手動検索
///
/// 横フリックは親の PageView が処理するので、ここでは縦だけ拾う。
///
/// v15 は全画面共通のトップバーを持たず、Home が自前でヘッダー
/// （wordmark・フレンド追加・通知ベル）を描画する。フレンド追加は
/// [showFriendAddSheet] でシートとして開く（独立タブには戻さない）。
class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.api,
    required this.onToast,
    required this.proximity,
    required this.myBeaconId,
    required this.unreadNotifications,
    required this.onOpenNotifications,
    required this.onBleSuccess,
  });

  final BloomApi api;
  final void Function(String message) onToast;
  final ProximityService proximity;

  /// 自分の beaconId。未発行なら null。
  final String? myBeaconId;

  /// 通知の未読件数。バッジ表示用（状態自体は MainShell が持つ）。
  final int unreadNotifications;
  final VoidCallback onOpenNotifications;

  /// 新しく閲覧可能になった投稿が1件以上増えたときだけ MainShell に伝える。
  /// 単に近接した・投稿0件増加のときはこれを呼ばず、[onToast] のみ使う。
  final void Function(String peerName, int newPostCount) onBleSuccess;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

/// 引っ張り操作の段階（仕様書 10.4）。
enum _PullPhase { idle, pulling, ready, searching }

class _HomeTabState extends State<HomeTab> {
  List<AuthorFeed> _authors = const [];
  int _authorIndex = 0;
  int _postIndex = 0;

  bool _loading = true;
  String? _loadError;

  double _dragY = 0;
  _PullPhase _pull = _PullPhase.idle;

  static const _pullReadyThreshold = 110.0;
  static const _changeAuthorThreshold = 42.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final authors = await widget.api.fetchFeed();
      if (!mounted) return;
      setState(() {
        _authors = authors;
        _authorIndex = 0;
        _postIndex = 0;
        _loading = false;
      });
    } on BloomApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '読み込めませんでした: $e';
        _loading = false;
      });
    }
  }

  AuthorFeed? get _author =>
      _authors.isEmpty ? null : _authors[_authorIndex % _authors.length];

  Post? get _post {
    final author = _author;
    if (author == null || author.posts.isEmpty) return null;
    return author.posts[_postIndex % author.posts.length];
  }

  void _changeAuthor(int delta) {
    if (_authors.length < 2) return;
    setState(() {
      _authorIndex = (_authorIndex + delta) % _authors.length;
      if (_authorIndex < 0) _authorIndex += _authors.length;
      _postIndex = 0;
    });
  }

  void _olderPost() {
    final author = _author;
    if (author == null || author.posts.length < 2) return;
    setState(() => _postIndex = (_postIndex + 1) % author.posts.length);
  }

  Future<void> _toggleLike() async {
    final post = _post;
    final author = _author;
    if (post == null || author == null) return;

    final next = !post.liked;
    // 先に反映してから送る。失敗したら戻す。
    setState(() {
      author.posts[_postIndex % author.posts.length] = post.copyWith(liked: next);
    });
    try {
      await widget.api.setLiked(post.id, next);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        author.posts[_postIndex % author.posts.length] = post;
      });
      widget.onToast('いいねを送れませんでした');
    }
  }

  /// 仕様書 10.3 手動近距離検索。
  ///
  /// BLE で拾えるのは beaconId だけなので、サーバーに解決させてから
  /// フレンドだけを交換対象にする（6.4）。交換はサーバーが双方向に行う。
  Future<void> _searchNearby() async {
    setState(() => _pull = _PullPhase.searching);
    try {
      final peers = await widget.proximity.scanOnce();
      if (!mounted) return;

      if (peers.isEmpty) {
        widget.onToast('近くにフレンドが見つかりませんでした');
        return;
      }

      final resolved =
          await widget.api.resolveBeacons(peers.map((p) => p.beaconId).toList());
      if (!mounted) return;

      if (resolved.friends.isEmpty) {
        widget.onToast('近くにフレンドが見つかりませんでした');
        return;
      }

      // 交換前の投稿数を、すでに画面が持っている _authors から控えておく。
      // 追加の API 通信はしない（フィードは _load() で1回だけ取り直す）。
      final beforeCounts = <String, int>{
        for (final a in _authors) a.uid: a.posts.length,
      };

      final exchangedWith = <({String uid, String name})>[];
      for (final friend in resolved.friends) {
        final result = await widget.api.reportProximity(peerUid: friend.uid);
        if (result.exchanged) {
          exchangedWith.add((
            uid: friend.uid,
            name: result.peerName ?? friend.username,
          ));
        }
      }
      if (!mounted || exchangedWith.isEmpty) return;

      // 交換したぶん新しく見えるようになった投稿を取り込む(1回だけ)。
      await _load();
      if (!mounted) return;

      final afterCounts = <String, int>{
        for (final a in _authors) a.uid: a.posts.length,
      };
      for (final peer in exchangedWith) {
        final newCount =
            (afterCounts[peer.uid] ?? 0) - (beforeCounts[peer.uid] ?? 0);
        if (newCount > 0) {
          widget.onBleSuccess(peer.name, newCount);
        } else {
          widget.onToast('${peer.name}さんとデータを共有しました');
        }
      }
    } on BloomApiException catch (e) {
      if (mounted) widget.onToast(e.message);
    } catch (e) {
      if (mounted) widget.onToast('検索に失敗しました');
    } finally {
      if (mounted) setState(() => _pull = _PullPhase.idle);
    }
  }

  void _openLog() {
    final author = _author;
    if (author == null) return;
    showDialog<void>(
      context: context,
      barrierColor: context.colors.scrim.withValues(alpha: 0.9),
      builder: (_) => UserLogOverlay(api: widget.api, author: author),
    );
  }

  /// avatar / username 部分だけの導線。投稿本体(タップ/縦スワイプ/長押し)
  /// のジェスチャーとは別の GestureDetector にしてあるので、そちらを
  /// 壊さない。
  void _openProfile(String uid) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OtherProfileScreen(
          api: widget.api,
          uid: uid,
          onToast: widget.onToast,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        _header(),
        Expanded(child: _body(colors)),
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoundActionButton(
                onTap: () => showFriendAddSheet(
                  context,
                  api: widget.api,
                  proximity: widget.proximity,
                  onToast: widget.onToast,
                ),
                icon: Icons.person_add_alt_1_outlined,
              ),
              const SizedBox(width: 5),
              _RoundActionButton(
                onTap: widget.onOpenNotifications,
                icon: Icons.notifications_none,
                badgeCount: widget.unreadNotifications,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body(BloomColorsExt colors) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: colors.primary),
      );
    }
    if (_loadError != null) return _errorState(colors, _loadError!);
    if (_authors.isEmpty) return _emptyState(colors);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) {
        _dragY = 0;
        setState(() => _pull = _PullPhase.idle);
      },
      onVerticalDragUpdate: (d) {
        _dragY += d.delta.dy;
        if (_dragY > 0) {
          setState(() => _pull = _dragY > _pullReadyThreshold
              ? _PullPhase.ready
              : _PullPhase.pulling);
        } else if (_pull != _PullPhase.idle) {
          setState(() => _pull = _PullPhase.idle);
        }
      },
      onVerticalDragEnd: (_) {
        final dy = _dragY;
        _dragY = 0;
        if (dy > _pullReadyThreshold) {
          _searchNearby();
          return;
        }
        setState(() => _pull = _PullPhase.idle);
        if (dy > _changeAuthorThreshold) {
          _changeAuthor(1);
        } else if (dy < -_changeAuthorThreshold) {
          _changeAuthor(-1);
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Stack(
          children: [
            Center(child: _card(colors)),
            if (_pull != _PullPhase.idle)
              Positioned(top: 2, left: 0, right: 0, child: _pullZone(colors)),
          ],
        ),
      ),
    );
  }

  Widget _pullZone(BloomColorsExt colors) {
    final (text, spinning) = switch (_pull) {
      _PullPhase.pulling => ('近くのフレンドを探す', false),
      _PullPhase.ready => ('離して検索', false),
      _PullPhase.searching => ('近くのフレンドを探しています…', true),
      _PullPhase.idle => ('', false),
    };

    return SizedBox(
      height: 52,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (spinning) ...[
            SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            text,
            style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _card(BloomColorsExt colors) {
    final author = _author!;
    final post = _post;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openProfile(author.uid),
              child: RemoteAvatar(api: widget.api, path: author.avatarPath),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openProfile(author.uid),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      author.username,
                      style: BloomText.bodyLg.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (post?.locationLabel != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 11,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              post!.locationLabel!,
                              style: BloomText.labelSm
                                  .copyWith(color: colors.onSurfaceVariant),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            IconButton(
              onPressed: _toggleLike,
              icon: Icon(
                post?.liked == true ? Icons.favorite : Icons.favorite_border,
                // liked のハートは brand color として常に同じ赤にする
                // (light/dark で変える必要が無いので theme には依存させない)。
                color: post?.liked == true
                    ? BloomColors.heart
                    : colors.onSurfaceVariant,
                size: 23,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (post == null)
          _noVisiblePosts(colors)
        else
          GestureDetector(
            onTap: _olderPost,
            onLongPress: _openLog,
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  decoration: BoxDecoration(
                    // メディアの背景はフィルムの黒台紙のような役割なので、
                    // Own Post Viewer 等の他画面と同じく光/暗テーマに
                    // 関わらず固定にしてある(Quiet Analog の意図的な質感)。
                    color: const Color(0xFF0E1013),
                    border: Border.all(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Film8mmEffects(
                        active: post.kind.isVideo,
                        child: PostMedia(api: widget.api, post: post),
                      ),
                      if (post.kind.isVideo)
                        const Positioned(
                          left: 10,
                          top: 10,
                          child: _KindBadge(label: '8mm'),
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
          ),
      ],
    );
  }

  Widget _noVisiblePosts(BloomColorsExt colors) => AspectRatio(
        aspectRatio: 3 / 2,
        child: Container(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            'まだ見られる投稿がありません',
            style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      );

  Widget _emptyState(BloomColorsExt colors) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'まだ見られる投稿がありません',
                style: BloomText.headlineSm.copyWith(color: colors.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: BloomSpace.sm),
              Text(
                'フレンドと実際に会うと、その時点までの投稿が見られるようになります。',
                style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: BloomSpace.lg),
              TextButton(
                onPressed: _load,
                child: Text(
                  '再読み込み',
                  style: BloomText.labelMd.copyWith(color: colors.primary),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _errorState(BloomColorsExt colors, String message) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
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

/// v15 の `.round-action`(境界線付きの円形アイコンボタン)。バッジ表示にも対応。
class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({
    required this.onTap,
    required this.icon,
    this.badgeCount = 0,
  });

  final VoidCallback onTap;
  final IconData icon;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
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
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, size: 20, color: colors.onSurface),
            if (badgeCount > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primary,
                    border: Border.all(color: colors.surface, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: BloomColors.scrim.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(BloomRadius.pill),
      ),
      child: Text(
        label,
        style: BloomText.labelSm.copyWith(color: BloomColors.onScrim),
      ),
    );
  }
}
