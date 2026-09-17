import 'dart:async';

import 'package:flutter/material.dart';

import '../api/bloom_api.dart';
import '../device/tilt_watcher.dart';
import '../models/models.dart';
import '../proximity/ble_proximity_service.dart';
import '../proximity/proximity_service.dart';
import '../theme/bloom_theme.dart';
import 'tabs/add_friend_tab.dart';
import 'tabs/home_tab.dart';
import 'tabs/post_tab.dart';
import 'notifications_screen.dart';
import 'tabs/profile_tab.dart';

/// 仕様書 8 の画面配置。左から 投稿 / ホーム / プロフィール / フレンド追加。
/// 起動時はホーム。
enum ShellTab {
  post('投稿'),
  home('ホーム'),
  profile('自分'),
  addFriend('追加');

  const ShellTab(this.label);

  final String label;
}

/// ログイン後の本体。4画面を横フリックで切り替える。
class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.api,
    required this.profile,
    required this.onProfileChanged,
    required this.onSignOut,
  });

  final BloomApi api;
  final Profile profile;
  final void Function(Profile profile) onProfileChanged;
  final VoidCallback onSignOut;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  static const _initialTab = ShellTab.home;

  late final PageController _pager =
      PageController(initialPage: _initialTab.index);
  ShellTab _tab = _initialTab;

  /// 仕様書 14：自動近距離検知は画面と独立して動かす。
  late final ProximityService _proximity = BleProximityService();
  StreamSubscription<List<NearbyPeer>>? _peerSub;

  /// 交換済みの相手。仕様書 6.3 のクールダウンはサーバーが見るが、
  /// 無駄な往復を減らすため端末側でも直近の相手を覚えておく。
  final _recentlyExchanged = <String, DateTime>{};

  /// 端末の傾き。縦画面固定なので画面の回転では拾えない。
  final _tilt = TiltWatcher();
  StreamSubscription<DeviceTilt>? _tiltSub;

  /// 横に倒す直前にいた画面。縦に戻したらここへ帰る。
  ShellTab? _tabBeforeTilt;

  /// トップバーのバッジに出す未読件数。
  int _unreadCount = 0;
  Timer? _unreadTimer;

  /// 画面に出すトースト。仕様書 14 のとおり、どの画面にいても出す。
  String? _toast;
  int _toastToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tiltSub = _tilt.changes.listen(_onTiltChanged);
    _tilt.start();
    _startProximity();
    _refreshUnread();
    // フレンド申請などは相手の操作で増えるので、開いている間は定期的に見に行く。
    _unreadTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshUnread(),
    );
  }

  Future<void> _refreshUnread() async {
    try {
      final feed = await widget.api.fetchNotifications();
      if (!mounted) return;
      setState(() => _unreadCount = feed.unreadCount);
    } catch (_) {
      // 取れなくてもバッジを出さないだけ。
    }
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsScreen(
          api: widget.api,
          onRead: () {
            if (mounted) setState(() => _unreadCount = 0);
          },
        ),
      ),
    );
  }

  /// 横に倒したら撮影画面へ、縦に戻したら元いた画面へ帰る。
  /// 画面自体は縦固定のまま回らない。
  void _onTiltChanged(DeviceTilt tilt) {
    if (!mounted) return;

    if (tilt == DeviceTilt.landscape) {
      if (_tab == ShellTab.post) return;
      _tabBeforeTilt = _tab;
      _goTo(ShellTab.post);
      return;
    }

    // 縦に戻した。傾ける前の画面を覚えているならそこへ帰る。
    final back = _tabBeforeTilt;
    _tabBeforeTilt = null;
    if (back != null && _tab == ShellTab.post) _goTo(back);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tiltSub?.cancel();
    _tilt.dispose();
    _unreadTimer?.cancel();
    _peerSub?.cancel();
    _proximity.dispose();
    _pager.dispose();
    super.dispose();
  }

  /// 仕様書 18.1：フォアグラウンドの間だけ動かす。
  /// resumed 以外（inactive / hidden / paused / detached）はすべて停止対象。
  /// paused だけを見ていると、他アプリへの切り替え直後に inactive / hidden
  /// 止まりで止まらないことがあるため。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tilt.start();
      _startProximity();
    } else {
      unawaited(_proximity.stop());
    }
  }

  Future<void> _startProximity() async {
    final beaconId = widget.profile.beaconId;
    if (beaconId == null) return;

    _peerSub ??= _proximity.peers.listen(_onPeersFound);
    await _proximity.start(myBeaconId: beaconId);
  }

  /// 仕様書 6.1：双方で近距離が確認できたら、ボタンを押させず自動で交換する。
  Future<void> _onPeersFound(List<NearbyPeer> peers) async {
    final now = DateTime.now();
    final fresh = peers
        .where((p) => now.difference(
              _recentlyExchanged[p.beaconId] ?? DateTime(0),
            ) >
            const Duration(minutes: 1))
        .toList();
    if (fresh.isEmpty) return;

    try {
      final resolved =
          await widget.api.resolveBeacons(fresh.map((p) => p.beaconId).toList());
      for (final friend in resolved.friends) {
        final result = await widget.api.reportProximity(peerUid: friend.uid);
        if (result.exchanged && mounted) {
          showToast('${result.peerName}さんとデータを共有しました');
          unawaited(_refreshUnread());
        }
      }
      for (final peer in fresh) {
        _recentlyExchanged[peer.beaconId] = now;
      }
    } catch (_) {
      // 通信に失敗しても次のスキャンで拾い直す。
    }
  }

  /// ナビを手で押したとき。傾きで戻る先は忘れる。
  void _selectTab(ShellTab tab) {
    _tabBeforeTilt = null;
    _goTo(tab);
  }

  void _goTo(ShellTab tab) {
    _pager.animateToPage(
      tab.index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  /// 仕様書 10.4 / 13 の各状態メッセージはここを通して出す。
  void showToast(String message) {
    final token = ++_toastToken;
    setState(() => _toast = message);
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (mounted && _toastToken == token) setState(() => _toast = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BloomColors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: Stack(
                children: [
                  PageView(
                    controller: _pager,
                    onPageChanged: (i) =>
                        setState(() => _tab = ShellTab.values[i]),
                    children: [
                      PostTab(api: widget.api, onPosted: _onPosted),
                      HomeTab(
                        api: widget.api,
                        onToast: showToast,
                        proximity: _proximity,
                        myBeaconId: widget.profile.beaconId,
                      ),
                      ProfileTab(
                        api: widget.api,
                        profile: widget.profile,
                        onProfileChanged: widget.onProfileChanged,
                        onSignOut: widget.onSignOut,
                        onToast: showToast,
                      ),
                      AddFriendTab(
                        api: widget.api,
                        onToast: showToast,
                        proximity: _proximity,
                      ),
                    ],
                  ),
                  if (_toast != null)
                    Positioned(
                      top: 14,
                      left: 0,
                      right: 0,
                      child: Center(child: _ToastBubble(message: _toast!)),
                    ),
                ],
              ),
            ),
            _bottomNav(),
          ],
        ),
      ),
    );
  }

  void _onPosted() {
    showToast('投稿しました');
    _goTo(ShellTab.home);
  }

  Widget _topBar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: BloomColors.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: BloomColors.primaryContainer,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '写真共有',
                style: BloomText.labelSm.copyWith(
                  color: BloomColors.primaryContainer,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                _tab.label,
                style: BloomText.labelMd.copyWith(color: BloomColors.secondary),
              ),
              const SizedBox(width: 10),
              _notificationButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _notificationButton() {
    return GestureDetector(
      onTap: _openNotifications,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(
              Icons.notifications_none,
              size: 22,
              color: BloomColors.secondary,
            ),
            if (_unreadCount > 0)
              Positioned(
                right: -3,
                top: -3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints: const BoxConstraints(minWidth: 15),
                  height: 15,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: BloomColors.primaryContainer,
                    borderRadius: BorderRadius.circular(BloomRadius.pill),
                  ),
                  child: Text(
                    _unreadCount > 99 ? '99+' : '$_unreadCount',
                    style: BloomText.labelSm.copyWith(
                      color: BloomColors.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomNav() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        9,
        12,
        9 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: BloomColors.surfaceContainerLow,
        border: Border(top: BorderSide(color: BloomColors.outlineVariant)),
      ),
      child: Row(
        children: [
          for (final tab in ShellTab.values)
            Expanded(
              child: _NavButton(
                tab: tab,
                active: tab == _tab,
                onTap: () => _selectTab(tab),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  final ShellTab tab;
  final bool active;
  final VoidCallback onTap;

  static const _icons = {
    ShellTab.post: Icons.add,
    ShellTab.home: Icons.circle,
    ShellTab.profile: Icons.circle_outlined,
    ShellTab.addFriend: Icons.person_add_alt,
  };

  @override
  Widget build(BuildContext context) {
    final color = active ? BloomColors.onSurface : BloomColors.secondary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? BloomColors.surfaceContainerHigh : null,
          borderRadius: BorderRadius.circular(BloomRadius.base),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 27,
              height: 27,
              decoration: BoxDecoration(
                border: Border.all(
                  color: active
                      ? BloomColors.primaryContainer
                      : BloomColors.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                _icons[tab],
                size: 14,
                color: active ? BloomColors.primaryContainer : color,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              tab.label,
              style: BloomText.labelSm.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToastBubble extends StatelessWidget {
  const _ToastBubble({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: BloomColors.surfaceContainerHigh,
        border: Border.all(color: BloomColors.outlineVariant),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(message, style: BloomText.bodySm),
    );
  }
}
