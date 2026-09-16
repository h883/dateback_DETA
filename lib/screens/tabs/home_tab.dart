import 'package:flutter/material.dart';

import '../../api/bloom_api.dart';
import '../../models/models.dart';
import '../../proximity/proximity_service.dart';
import '../../theme/bloom_theme.dart';
import '../../widgets/post_media.dart';
import '../../widgets/remote_image.dart';
import '../user_log_overlay.dart';

/// ホーム画面（仕様書 10）。
///
/// - 縦フリック上下で投稿者を切り替える
/// - メディアをタップで同じ人の過去の投稿へ
/// - メディア長押しでその人のログを開く
/// - 最上部から下へ引っ張ると近距離の手動検索
///
/// 横フリックは親の PageView が処理するので、ここでは縦だけ拾う。
class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.api,
    required this.onToast,
    required this.proximity,
    required this.myBeaconId,
  });

  final BloomApi api;
  final void Function(String message) onToast;
  final ProximityService proximity;

  /// 自分の beaconId。未発行なら null。
  final String? myBeaconId;

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

      var exchanged = false;
      for (final friend in resolved.friends) {
        final result = await widget.api.reportProximity(peerUid: friend.uid);
        if (result.exchanged) {
          exchanged = true;
          widget.onToast('${result.peerName}さんとデータを共有しました');
        }
      }
      if (!mounted) return;
      // 交換したぶん新しく見えるようになった投稿を取り込む。
      if (exchanged) await _load();
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
      barrierColor: BloomColors.scrim.withValues(alpha: 0.9),
      builder: (_) => UserLogOverlay(api: widget.api, author: author),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: BloomColors.primaryContainer),
      );
    }
    if (_loadError != null) return _errorState(_loadError!);
    if (_authors.isEmpty) return _emptyState();

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
            Center(child: _card()),
            if (_pull != _PullPhase.idle)
              Positioned(top: 2, left: 0, right: 0, child: _pullZone()),
          ],
        ),
      ),
    );
  }

  Widget _pullZone() {
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
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: BloomColors.primaryContainer,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            text,
            style: BloomText.bodySm.copyWith(color: BloomColors.secondary),
          ),
        ],
      ),
    );
  }

  Widget _card() {
    final author = _author!;
    final post = _post;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            RemoteAvatar(api: widget.api, path: author.avatarPath),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                author.username,
                style: BloomText.bodyLg.copyWith(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              onPressed: _toggleLike,
              icon: Icon(
                post?.liked == true ? Icons.favorite : Icons.favorite_border,
                color: post?.liked == true
                    ? BloomColors.heart
                    : BloomColors.secondary,
                size: 23,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (post == null)
          _noVisiblePosts()
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
                    color: const Color(0xFF0E1013),
                    border: Border.all(color: BloomColors.outlineVariant),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PostMedia(api: widget.api, post: post),
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
                            color: BloomColors.primaryContainer,
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

  Widget _noVisiblePosts() => AspectRatio(
        aspectRatio: 3 / 2,
        child: Container(
          decoration: BoxDecoration(
            color: BloomColors.surfaceContainerLow,
            border: Border.all(color: BloomColors.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            'まだ見られる投稿がありません',
            style: BloomText.bodySm.copyWith(color: BloomColors.secondary),
          ),
        ),
      );

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'まだ見られる投稿がありません',
                style: BloomText.headlineSm,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: BloomSpace.sm),
              Text(
                'フレンドと実際に会うと、その時点までの投稿が見られるようになります。',
                style: BloomText.bodySm.copyWith(color: BloomColors.secondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: BloomSpace.lg),
              TextButton(
                onPressed: _load,
                child: Text(
                  '再読み込み',
                  style:
                      BloomText.labelMd.copyWith(color: BloomColors.primary),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _errorState(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                style: BloomText.bodySm.copyWith(color: BloomColors.secondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: BloomSpace.md),
              TextButton(
                onPressed: _load,
                child: Text(
                  '再試行',
                  style:
                      BloomText.labelMd.copyWith(color: BloomColors.primary),
                ),
              ),
            ],
          ),
        ),
      );
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
