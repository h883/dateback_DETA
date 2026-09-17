import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../settings/settings_store.dart';
import '../theme/bloom_theme.dart';
import '../theme/theme_controller.dart';
import 'tutorial_screen.dart';

/// Profile 右上のハンバーガーから開く設定ドロワー(v15)。
///
/// 独立した設定画面へ全面遷移するのではなく、`Scaffold.endDrawer` として
/// 右側から重なるオーバーレイにする(背景タップでの閉じる・スワイプでの
/// 閉じるは Scaffold 標準の Drawer 機構をそのまま使う)。
class SettingsDrawer extends StatefulWidget {
  const SettingsDrawer({
    super.key,
    required this.themeController,
    required this.settingsStore,
    required this.onSignOut,
    required this.onToast,
  });

  final ThemeController themeController;
  final SettingsStore settingsStore;
  final VoidCallback onSignOut;
  final void Function(String message) onToast;

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  bool _themeWheelOpen = false;

  /// 「別の設定操作をする」「drawer を閉じる」のいずれでもホイールは閉じる。
  /// 各行の onTap の先頭で必ずこれを呼ぶ。
  void _collapseWheel() {
    if (_themeWheelOpen) setState(() => _themeWheelOpen = false);
  }

  void _openTutorial() {
    _collapseWheel();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => TutorialScreen(
          replay: true,
          // 再生時は初回完了フラグを書き換えない。ただ閉じるだけ。
          onFinished: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  }

  Future<void> _openOsAppSettings() async {
    _collapseWheel();
    final opened = await openAppSettings();
    if (!opened && mounted) widget.onToast('設定アプリを開けませんでした');
  }

  void _placeholder(String label) {
    _collapseWheel();
    widget.onToast('$labelは近日公開します');
  }

  Future<void> _confirmLogout() async {
    _collapseWheel();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _ConfirmDialog(
        title: 'ログアウトしますか？',
        confirmLabel: 'ログアウト',
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(); // drawer を閉じてから。
      widget.onSignOut();
    }
  }

  // アカウント削除: backend に削除 API が無いため、押せて確認ダイアログまで
  // 進める「実行可能に見える」UI にはしない。非活性行として置くだけに
  // とどめる。API 実装後、ここを _MenuRow(onTap: _confirmDeleteAccount,
  // danger: true) のような形へ戻して有効化する想定。

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Drawer(
      backgroundColor: colors.surfaceContainerLow,
      width: 268,
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 6, top: 4),
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, size: 20, color: colors.onSurface),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                children: [
                  const _SectionLabel('サポート'),
                  _MenuRow(label: '使い方', onTap: _openTutorial),
                  _MenuRow(label: '通知', onTap: _openOsAppSettings),
                  const _SectionLabel('アプリ設定'),
                  _ThemeRow(
                    themeController: widget.themeController,
                    isOpen: _themeWheelOpen,
                    onOpen: () => setState(() => _themeWheelOpen = true),
                    onClose: _collapseWheel,
                  ),
                  _ToggleRow(
                    label: '横向きでカメラを開く',
                    value: widget.settingsStore.tiltToCameraEnabled,
                    onChanged: (v) {
                      _collapseWheel();
                      widget.settingsStore.setTiltToCameraEnabled(v);
                      setState(() {});
                    },
                  ),
                  _ToggleRow(
                    label: '撮影地を自動で追加',
                    value: widget.settingsStore.autoLocationEnabled,
                    onChanged: (v) {
                      _collapseWheel();
                      widget.settingsStore.setAutoLocationEnabled(v);
                      setState(() {});
                    },
                  ),
                  const _SectionLabel('アカウント'),
                  _MenuRow(
                    label: 'プライバシーとセキュリティ',
                    onTap: _openOsAppSettings,
                  ),
                  _MenuRow(
                    label: '法的情報',
                    onTap: () => _placeholder('利用規約・プライバシーポリシー'),
                  ),
                  _MenuRow(label: 'ログアウト', onTap: _confirmLogout),
                  const _MenuRow(
                    label: 'アカウントを削除',
                    danger: true,
                    onTap: null,
                    disabledNote: '準備中',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 6),
      child: Text(
        label,
        style: BloomText.labelSm.copyWith(color: context.colors.outline),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.label,
    this.onTap,
    this.danger = false,
    this.disabledNote,
  });

  final String label;

  /// null なら非活性表示にする(タップできない)。
  final VoidCallback? onTap;
  final bool danger;

  /// 非活性のときに右側へ出す短い注記(例: 「準備中」)。
  final String? disabledNote;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    final row = Container(
      constraints: const BoxConstraints(minHeight: 45),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: BloomText.bodySm.copyWith(
              color: !enabled
                  ? colors.onSurfaceVariant.withValues(alpha: 0.6)
                  : (danger ? colors.error : colors.onSurface),
            ),
          ),
          enabled
              ? Text('›', style: TextStyle(color: colors.outline, fontSize: 15))
              : Text(
                  disabledNote ?? '',
                  style: BloomText.labelSm.copyWith(color: colors.outline),
                ),
        ],
      ),
    );
    if (!enabled) return row;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: row,
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final void Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 45),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: BloomText.bodySm.copyWith(color: colors.onSurface),
              ),
            ),
            _Switch(value: value),
          ],
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 39,
      height: 23,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value
            ? colors.primary.withValues(alpha: 0.16)
            : colors.surfaceContainer,
        border: Border.all(color: value ? colors.primary : colors.outlineVariant),
        borderRadius: BorderRadius.circular(999),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 160),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 17,
          height: 17,
          decoration: BoxDecoration(
            color: value ? colors.primary : colors.outline,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// 「表示」行。現在値そのものが縦ホイールピッカーへ展開する。
/// 現在値表示とピッカーを二重に出さない(同じ領域が差し替わるだけ)。
class _ThemeRow extends StatefulWidget {
  const _ThemeRow({
    required this.themeController,
    required this.isOpen,
    required this.onOpen,
    required this.onClose,
  });

  final ThemeController themeController;
  final bool isOpen;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  State<_ThemeRow> createState() => _ThemeRowState();
}

class _ThemeRowState extends State<_ThemeRow> {
  static const _options = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
  static const _labels = {
    ThemeMode.system: 'システム',
    ThemeMode.light: 'ライト',
    ThemeMode.dark: 'ダーク',
  };
  static const _itemExtent = 32.0;

  late FixedExtentScrollController _wheelController = _newController();

  FixedExtentScrollController _newController() =>
      FixedExtentScrollController(
        initialItem: _options.indexOf(widget.themeController.mode),
      );

  @override
  void didUpdateWidget(covariant _ThemeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen && !oldWidget.isOpen) {
      // 開くたびに現在値の位置へ合わせ直す(前回位置を引きずらない)。
      _wheelController.dispose();
      _wheelController = _newController();
    }
  }

  @override
  void dispose() {
    _wheelController.dispose();
    super.dispose();
  }

  void _select(ThemeMode mode) {
    widget.themeController.setMode(mode);
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedBuilder(
      animation: widget.themeController,
      builder: (context, _) {
        final current = widget.themeController.mode;
        return Container(
          constraints: const BoxConstraints(minHeight: 45),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('表示', style: BloomText.bodySm.copyWith(color: colors.onSurface)),
              GestureDetector(
                onTap: () {
                  if (widget.isOpen) {
                    widget.onClose();
                  } else {
                    widget.onOpen();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 100,
                  height: widget.isOpen ? _itemExtent * 3 : _itemExtent,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: widget.isOpen ? colors.surfaceContainer : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: widget.isOpen
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            ListWheelScrollView.useDelegate(
                              controller: _wheelController,
                              itemExtent: _itemExtent,
                              diameterRatio: 1.7,
                              perspective: 0.003,
                              physics: const FixedExtentScrollPhysics(),
                              onSelectedItemChanged: (i) =>
                                  widget.themeController.setMode(_options[i]),
                              childDelegate: ListWheelChildBuilderDelegate(
                                childCount: _options.length,
                                builder: (context, i) {
                                  final selected = _options[i] == current;
                                  return GestureDetector(
                                    onTap: () => _select(_options[i]),
                                    child: Center(
                                      child: Text(
                                        _labels[_options[i]]!,
                                        style: selected
                                            ? BloomText.labelLg.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: colors.onSurface,
                                              )
                                            : BloomText.bodySm.copyWith(
                                                color: colors.onSurfaceVariant,
                                              ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            IgnorePointer(
                              child: Container(
                                margin: EdgeInsets.symmetric(
                                  vertical: _itemExtent,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.symmetric(
                                    horizontal: BorderSide(color: colors.outlineVariant),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Center(
                          child: Text(
                            _labels[current]!,
                            style: BloomText.labelLg.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 確認ダイアログ。今のところログアウトだけが使う(アカウント削除は
/// API未実装のため確認ダイアログ自体を出さない非活性行にしてある)。
class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.title, required this.confirmLabel});

  final String title;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.surfaceContainerLow,
      title: Text(title, style: BloomText.headlineSm.copyWith(color: colors.onSurface)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('キャンセル', style: TextStyle(color: colors.onSurfaceVariant)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel, style: TextStyle(color: colors.onSurface)),
        ),
      ],
    );
  }
}
