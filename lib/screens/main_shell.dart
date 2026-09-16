import 'package:flutter/material.dart';

import '../api/bloom_api.dart';
import '../models/models.dart';
import '../theme/bloom_theme.dart';
import 'tabs/add_friend_tab.dart';
import 'tabs/home_tab.dart';
import 'tabs/post_tab.dart';
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

class _MainShellState extends State<MainShell> {
  static const _initialTab = ShellTab.home;

  late final PageController _pager =
      PageController(initialPage: _initialTab.index);
  ShellTab _tab = _initialTab;

  /// 画面に出すトースト。仕様書 14 のとおり、どの画面にいても出す。
  String? _toast;
  int _toastToken = 0;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
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
                      HomeTab(api: widget.api, onToast: showToast),
                      ProfileTab(
                        api: widget.api,
                        profile: widget.profile,
                        onProfileChanged: widget.onProfileChanged,
                        onSignOut: widget.onSignOut,
                        onToast: showToast,
                      ),
                      AddFriendTab(api: widget.api, onToast: showToast),
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
          Text(
            _tab.label,
            style: BloomText.labelMd.copyWith(color: BloomColors.secondary),
          ),
        ],
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
                onTap: () => _goTo(tab),
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
