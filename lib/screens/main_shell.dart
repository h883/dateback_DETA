import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/bloom_api.dart';
import '../device/location_service.dart';
import '../device/tilt_watcher.dart';
import '../drafts/draft_store.dart';
import '../models/models.dart';
import '../proximity/ble_proximity_service.dart';
import '../proximity/proximity_service.dart';
import '../settings/settings_store.dart';
import '../theme/bloom_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/ble_success_overlay.dart';
import '../widgets/post_status_banner.dart';
import 'post_failure_sheet.dart';
import 'post_viewer_screen.dart';
import 'settings_drawer.dart';
import 'tabs/home_tab.dart';
import 'tabs/post_tab.dart';
import 'notifications_screen.dart';
import 'tabs/profile_tab.dart';

/// v15 の画面配置。Camera ← Home → Profile の3画面。起動時はホーム。
/// フレンド追加は独立タブではなく、Home 右上・フレンド一覧からのシート
/// 起動に変わった（Phase 4 で実装。仕様書 8 の4画面構成から変更）。
enum ShellTab {
  post('投稿'),
  home('ホーム'),
  profile('自分');

  const ShellTab(this.label);

  final String label;
}

/// ログイン後の本体。3画面を横フリックで切り替える。
class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.api,
    required this.profile,
    required this.onProfileChanged,
    required this.onSignOut,
    required this.themeController,
    required this.settingsStore,
  });

  final BloomApi api;
  final Profile profile;
  final void Function(Profile profile) onProfileChanged;
  final VoidCallback onSignOut;
  final ThemeController themeController;
  final SettingsStore settingsStore;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  static const _initialTab = ShellTab.home;

  late final PageController _pager =
      PageController(initialPage: _initialTab.index);
  ShellTab _tab = _initialTab;

  /// Profile のハンバーガーから設定ドロワーを開くのに使う
  /// (ドロワーは MainShell 自身の Scaffold に持たせ、画面全体を覆う)。
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// 仕様書 14：自動近距離検知は画面と独立して動かす。
  late final ProximityService _proximity = BleProximityService();
  StreamSubscription<List<NearbyPeer>>? _peerSub;

  /// 交換済みの相手。仕様書 6.3 のクールダウンはサーバーが見るが、
  /// 無駄な往復を減らすため端末側でも直近の相手を覚えておく。
  final _recentlyExchanged = <String, DateTime>{};

  /// 端末の傾き。縦画面固定なので画面の回転では拾えない。
  final _tilt = TiltWatcher();
  StreamSubscription<DeviceTilt>? _tiltSub;

  /// tilt-to-camera によって Camera が自動的に開かれた場合の、その時点の
  /// [DeviceTilt]。手動(右フリック・ボトムナビ)で Camera を開いた場合は
  /// 常に null のまま。[PostTab] はこれが非null のときだけ
  /// `CameraController.lockCaptureOrientation` を適用する
  /// ([captureOrientationForTilt] 参照)。
  ///
  /// Camera タブを離れたら(傾き復帰・Home ボタン・スワイプのいずれでも)
  /// 必ず null に戻す([_onTiltChanged] の縦復帰分岐、PageView の
  /// `onPageChanged` を参照)。PostTab は PageView 内に残り続けるため、
  /// ここで確実にリセットしないと次に手動で Camera を開いたときに
  /// 古い lock 設定が紛れ込む。
  DeviceTilt? _activeCameraTilt;

  /// PostTab が撮影確認中・投稿処理中のとき true。縦に戻しても
  /// カメラを閉じないためのガード。
  bool _postBusy = false;

  /// PostTab の35mmフィルタースワイプ中は true。その間だけ PageView の
  /// 横スワイプ navigation を止め、Camera ← Home → Profile の既存タブ切替
  /// ジェスチャーと衝突しないようにする。
  bool _cameraFilterGestureActive = false;

  /// Home のヘッダーで見せる未読件数。
  int _unreadCount = 0;
  Timer? _unreadTimer;

  /// beaconId はサーバー側で2分ごとにローテーションされる（盗聴対策）。
  /// ローテーション周期より十分短い間隔で追従し、広告を出し直す。
  Timer? _beaconRefreshTimer;

  /// 画面に出すトースト。仕様書 14 のとおり、どの画面にいても出す。
  String? _toast;
  int _toastToken = 0;

  /// 新しく閲覧可能になった投稿が増えたときだけ出す BLE 成功カード。
  ({String peerName, int newPostCount})? _bleSuccess;
  int _bleSuccessToken = 0;

  /// 投稿の成功/失敗バナー(v15 の `.status-banner`)。ボトムナビ直上に
  /// 約2.5秒だけ出す。
  ({String message, String actionLabel, VoidCallback onAction})? _postBanner;
  int _postBannerToken = 0;

  /// 投稿に失敗したメディア。「確認する」→失敗シートの再試行/下書き保存/
  /// 破棄がこれを使う。解決する(成功・保存・破棄)までここに保持する。
  ({Uint8List bytes, PostKind kind, String contentType, String? locationLabel})?
      _pendingFailedPost;

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
    // サーバー側のローテーション周期(30秒)より十分短い間隔で確認しないと、
    // 前世代(beacon_id_prev)の猶予を使い切ってIDを見失う。
    _beaconRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshBeaconId(),
    );
  }

  /// サーバーの beaconId ローテーションに追従し、広告中の値を更新する。
  Future<void> _refreshBeaconId() async {
    try {
      final profile = await widget.api.fetchMyProfile();
      final newBeaconId = profile?.beaconId;
      if (!mounted || profile == null || newBeaconId == null) return;
      if (newBeaconId != widget.profile.beaconId) {
        widget.onProfileChanged(profile);
        await _proximity.updateBeaconId(newBeaconId);
      }
    } catch (_) {
      // 取れなくても次の周期でやり直す。
    }
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
  ///
  /// 発火条件（今回の仕様）:
  /// - Home 表示中に landscapeShutterRight（端末上部を左へ倒す＝反時計回り
  ///   90°、シャッターが右側に来る向き）になったときだけ自動でカメラへ。
  ///   ただし設定の「横向きでカメラを開く」が OFF ならこの自動起動だけを
  ///   無効化する(右フリック・ボトムナビからの Camera 遷移は影響しない。
  ///   どちらも TiltWatcher を経由せず別経路で動くため)。
  /// - Profile 表示中は無視する。逆向き（landscapeOther）も無視する。
  /// - 縦へ戻ったときは、Camera を右フリックやボトムナビで開いた場合も
  ///   含めて Home へ戻す。ただし PostTab が撮影確認中・投稿処理中
  ///   （[_postBusy]）のときは Camera を維持し、何もしない。
  void _onTiltChanged(DeviceTilt tilt) {
    if (!mounted) return;

    if (tilt == DeviceTilt.landscapeShutterRight) {
      if (!widget.settingsStore.tiltToCameraEnabled) return;
      if (_tab != ShellTab.home) return;
      // この自動遷移のときだけ、実際に検知した傾きを PostTab へ伝える
      // (=手動で開いた場合と区別する。orientation lock の可否はこれを見て
      // PostTab 側が決める)。
      setState(() => _activeCameraTilt = tilt);
      _goTo(ShellTab.post);
      return;
    }

    if (tilt == DeviceTilt.landscapeOther) {
      // 逆向きでは何もしない。
      return;
    }

    // 縦に戻した。Camera 表示中で、かつ撮影確認中・投稿処理中でなければ
    // Home へ戻す(開き方が傾き・右フリック・ボトムナビのいずれでも同じ)。
    if (_tab == ShellTab.post && !_postBusy) {
      _goTo(ShellTab.home);
    }
  }

  void _onPostBusyChanged(bool busy) {
    _postBusy = busy;
  }

  void _onCameraFilterGestureActive(bool active) {
    if (_cameraFilterGestureActive == active) return;
    setState(() => _cameraFilterGestureActive = active);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tiltSub?.cancel();
    _tilt.dispose();
    _unreadTimer?.cancel();
    _beaconRefreshTimer?.cancel();
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
  ///
  /// [_recentlyExchanged] の1分間隔チェックにより、`peers` ストリームが
  /// 2秒おきに再emitされても `resolveBeacons`/`reportProximity` は
  /// 相手ごとに最大1分に1回しか呼ばれない。新しく閲覧可能になった投稿の
  /// 前後比較（[BloomApi.fetchUserPosts]）もこの呼び出しに相乗りさせる
  /// ことで、スキャンのたびに追加通信が増えないようにしている。
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
        // reportProximity を実行する直前・直後だけ投稿数を比較する。
        // 取得に失敗したら差分は判定できないものとして扱う（安全側）。
        final beforeCount = await _visiblePostCountOrNull(friend.uid);

        final result = await widget.api.reportProximity(peerUid: friend.uid);
        if (!mounted) return;

        if (result.exchanged) {
          final newCount = beforeCount == null
              ? 0
              : await _newlyVisibleCount(friend.uid, beforeCount);
          if (newCount > 0) {
            _showBleSuccess(
              peerName: result.peerName ?? friend.username,
              newPostCount: newCount,
            );
          } else {
            showToast('${result.peerName}さんとデータを共有しました');
          }
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

  /// 交換「前」の閲覧可能投稿数。取得できなければ null(判定不能)。
  Future<int?> _visiblePostCountOrNull(String uid) async {
    try {
      return (await widget.api.fetchUserPosts(uid)).length;
    } catch (_) {
      return null;
    }
  }

  /// 交換「後」に増えた投稿数。取得できなければ 0(演出は出さない)。
  Future<int> _newlyVisibleCount(String uid, int beforeCount) async {
    try {
      final afterCount = (await widget.api.fetchUserPosts(uid)).length;
      final diff = afterCount - beforeCount;
      return diff > 0 ? diff : 0;
    } catch (_) {
      return 0;
    }
  }

  /// 仕様書 6.1 のトーストとは別に、新しく見える投稿が増えたときだけ出す
  /// v15 の BLE 成功カード。
  void _showBleSuccess({required String peerName, required int newPostCount}) {
    final token = ++_bleSuccessToken;
    setState(() => _bleSuccess = (peerName: peerName, newPostCount: newPostCount));
    Future<void>.delayed(const Duration(milliseconds: 1250), () {
      if (mounted && _bleSuccessToken == token) {
        setState(() => _bleSuccess = null);
      }
    });
  }

  /// 投稿の成功/失敗バナー(v15 の `.status-banner`)。約2.5秒で自動的に消える。
  void _showPostBanner({
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final token = ++_postBannerToken;
    setState(() {
      _postBanner =
          (message: message, actionLabel: actionLabel, onAction: onAction);
    });
    Future<void>.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && _postBannerToken == token) {
        setState(() => _postBanner = null);
      }
    });
  }

  /// ナビを手で押したとき。
  void _selectTab(ShellTab tab) {
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
    // v15 は全画面共通のトップバーを持たない。各タブが自前でヘッダーを
    // 描画する（HomeTab/ProfileTab）。Camera は portrait 用ヘッダーも
    // ボトムナビも持たず、専用の landscape UI だけを表示する。
    //
    // 設定ドロワーはこの MainShell 自身の Scaffold に持たせる(タブごとに
    // ネストした Scaffold へ endDrawer を付けると、画面全体ではなく
    // その Scaffold の範囲(ボトムナビの上まで)しか覆えないため)。
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: context.colors.surface,
      endDrawer: SettingsDrawer(
        themeController: widget.themeController,
        settingsStore: widget.settingsStore,
        onSignOut: widget.onSignOut,
        onToast: showToast,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  PageView(
                    controller: _pager,
                    // フィルタースワイプ中だけ明示的に止める。そうでない
                    // ときは null にして、各プラットフォームの既定の
                    // PageView 挙動(元の physics 未指定時の挙動)をそのまま
                    // 使う。
                    physics: _cameraFilterGestureActive
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    onPageChanged: (i) {
                      final next = ShellTab.values[i];
                      setState(() {
                        _tab = next;
                        // Camera 以外へ着地したら、開き方が傾き・右フリック・
                        // ボトムナビのいずれであっても tilt context を必ず
                        // 消す(PostTab は破棄されずに残り続けるため)。
                        if (next != ShellTab.post) _activeCameraTilt = null;
                      });
                    },
                    children: [
                      PostTab(
                        api: widget.api,
                        onPostResult: _handlePostOutcome,
                        onHome: () => _goTo(ShellTab.home),
                        onBusyChanged: _onPostBusyChanged,
                        onCaptureLocation: _captureLocationIfEnabled,
                        active: _tab == ShellTab.post,
                        onFilterGestureActive: _onCameraFilterGestureActive,
                        activeTilt: _activeCameraTilt,
                      ),
                      HomeTab(
                        api: widget.api,
                        onToast: showToast,
                        proximity: _proximity,
                        myBeaconId: widget.profile.beaconId,
                        unreadNotifications: _unreadCount,
                        onOpenNotifications: _openNotifications,
                        onBleSuccess: (peerName, newPostCount) =>
                            _showBleSuccess(
                          peerName: peerName,
                          newPostCount: newPostCount,
                        ),
                      ),
                      ProfileTab(
                        api: widget.api,
                        profile: widget.profile,
                        onProfileChanged: widget.onProfileChanged,
                        onToast: showToast,
                        proximity: _proximity,
                        onOpenSettings: () =>
                            _scaffoldKey.currentState?.openEndDrawer(),
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
                  if (_bleSuccess != null)
                    Positioned.fill(
                      child: BleSuccessOverlay(
                        peerName: _bleSuccess!.peerName,
                        newPostCount: _bleSuccess!.newPostCount,
                      ),
                    ),
                  if (_postBanner != null)
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 12,
                      child: PostStatusBanner(
                        message: _postBanner!.message,
                        actionLabel: _postBanner!.actionLabel,
                        onAction: () {
                          final action = _postBanner!.onAction;
                          setState(() => _postBanner = null);
                          action();
                        },
                      ),
                    ),
                ],
              ),
            ),
            if (_tab != ShellTab.post) _bottomNav(),
          ],
        ),
      ),
    );
  }

  /// 撮影地(粗いエリア名)の取得を試みる(B2)。ON/OFF の唯一の判断元は
  /// [SettingsStore.autoLocationEnabled]。OFF のときは位置取得 API 自体を
  /// 一切呼ばない(このメソッドの外へは出ない)。
  Future<String?> _captureLocationIfEnabled() {
    if (!widget.settingsStore.autoLocationEnabled) return Future.value(null);
    return LocationService.currentAreaLabel();
  }

  /// PostTab からの結果を受けて、成功・失敗どちらも中間確認画面を挟まず
  /// Home へ戻す。バナーの表示・(失敗時の)再試行/下書き保存はここが持つ。
  void _handlePostOutcome(PostOutcome outcome) {
    _goTo(ShellTab.home);
    switch (outcome) {
      case PostSuccess():
        _showPostSuccessBanner();
      case PostFailure(
          :final bytes,
          :final kind,
          :final contentType,
          :final locationLabel,
        ):
        _pendingFailedPost = (
          bytes: bytes,
          kind: kind,
          contentType: contentType,
          locationLabel: locationLabel,
        );
        _showPostBanner(
          message: '投稿に失敗しました',
          actionLabel: '確認する',
          onAction: _openPostFailureSheet,
        );
    }
  }

  /// バナー自体は Home へ戻った直後に即出す(取得を待たせない)。
  /// 一覧は裏で先行取得しておき、間に合えば「投稿を見る」タップ時に
  /// 追加の通信なしでそのまま使う。間に合わなければそのときに取り直す
  /// (新APIは使わない、既存 fetchMyPosts のみ)。
  void _showPostSuccessBanner() {
    List<Post>? prefetched;
    unawaited(() async {
      try {
        prefetched = await widget.api.fetchMyPosts();
      } catch (_) {
        // 取れなくても構わない。タップ時に取り直す。
      }
    }());
    _showPostBanner(
      message: '✓ 投稿しました',
      actionLabel: '投稿を見る',
      onAction: () => _openJustPostedViewer(prefetched),
    );
  }

  Future<void> _openJustPostedViewer(List<Post>? cached) async {
    var posts = cached;
    if (posts == null || posts.isEmpty) {
      try {
        posts = await widget.api.fetchMyPosts();
      } catch (_) {
        posts = null;
      }
    }
    if (!mounted) return;
    if (posts == null || posts.isEmpty) {
      showToast('投稿を確認できませんでした');
      return;
    }
    // fetchMyPosts は created_at 降順なので、先頭が今投稿したもの。
    await showPostViewer(
      context,
      api: widget.api,
      posts: posts,
      initialIndex: 0,
      onToast: showToast,
      isOwn: true,
    );
  }

  void _openPostFailureSheet() {
    final pending = _pendingFailedPost;
    if (pending == null) return;
    showPostFailureSheet(
      context,
      onRetry: () => _retryFailedPost(pending),
      onSaveDraft: () => _saveFailedPostAsDraft(pending),
      onDiscard: _discardFailedPost,
    );
  }

  /// 失敗したメディアと種別をそのまま使って再送する。撮影地(B2)は
  /// 撮影時に取得済みのものをそのまま使い、ここで取り直さない。
  Future<bool> _retryFailedPost(
    ({
      Uint8List bytes,
      PostKind kind,
      String contentType,
      String? locationLabel,
    }) pending,
  ) async {
    try {
      await widget.api.createPost(
        bytes: pending.bytes,
        kind: pending.kind,
        contentType: pending.contentType,
        locationLabel: pending.locationLabel,
      );
      _pendingFailedPost = null;
      if (mounted) _showPostSuccessBanner();
      return true;
    } catch (_) {
      // 失敗してもメディアは _pendingFailedPost に残したまま
      // (呼び出し側のシートが再試行できる状態を保つ)。
      return false;
    }
  }

  Future<bool> _saveFailedPostAsDraft(
    ({
      Uint8List bytes,
      PostKind kind,
      String contentType,
      String? locationLabel,
    }) pending,
  ) async {
    try {
      await DraftStore.instance.save(
        bytes: pending.bytes,
        kind: pending.kind,
        contentType: pending.contentType,
        locationLabel: pending.locationLabel,
      );
      _pendingFailedPost = null;
      if (mounted) showToast('下書きに保存しました');
      return true;
    } catch (_) {
      return false;
    }
  }

  void _discardFailedPost() {
    _pendingFailedPost = null;
    showToast('投稿を破棄しました');
  }

  Widget _bottomNav() {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        9,
        12,
        9 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
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

  /// v15 のボトムナビは Camera / Home / Profile。選択中は塗りつぶし、
  /// 非選択はアウトラインのアイコンにして意味が伝わるようにする。
  static const _filledIcons = {
    ShellTab.post: Icons.camera_alt,
    ShellTab.home: Icons.home,
    ShellTab.profile: Icons.person,
  };
  static const _outlinedIcons = {
    ShellTab.post: Icons.camera_alt_outlined,
    ShellTab.home: Icons.home_outlined,
    ShellTab.profile: Icons.person_outline,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = active ? colors.onSurface : colors.secondary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? colors.surfaceContainerHigh : null,
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
                      ? colors.primaryContainer
                      : colors.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                active ? _filledIcons[tab] : _outlinedIcons[tab],
                size: 14,
                color: active ? colors.primaryContainer : color,
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
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(message, style: BloomText.bodySm.copyWith(color: colors.onSurface)),
    );
  }
}
