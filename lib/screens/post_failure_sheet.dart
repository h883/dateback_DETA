import 'package:flutter/material.dart';

import '../theme/bloom_theme.dart';

/// 投稿失敗時の確認シート(v15 の `.post-failure-actions`)。
/// 再試行・下書きとして残す・破棄、をコンパクトな縦積みボタンで並べる。
/// 巨大なボタンやカードにはしない。
Future<void> showPostFailureSheet(
  BuildContext context, {
  required Future<bool> Function() onRetry,
  required Future<bool> Function() onSaveDraft,
  required VoidCallback onDiscard,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PostFailureSheet(
      onRetry: onRetry,
      onSaveDraft: onSaveDraft,
      onDiscard: onDiscard,
    ),
  );
}

class _PostFailureSheet extends StatefulWidget {
  const _PostFailureSheet({
    required this.onRetry,
    required this.onSaveDraft,
    required this.onDiscard,
  });

  /// true を返せば成功(シートを閉じる)。false ならメディアを失わず
  /// もう一度操作できる状態のままシートを開いておく。
  final Future<bool> Function() onRetry;
  final Future<bool> Function() onSaveDraft;
  final VoidCallback onDiscard;

  @override
  State<_PostFailureSheet> createState() => _PostFailureSheetState();
}

class _PostFailureSheetState extends State<_PostFailureSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _run(String failMessage, Future<bool> Function() action) async {
    if (_busy) return; // 二重タップ防止。
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await action();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = failMessage;
      });
    }
  }

  void _discard() {
    if (_busy) return;
    widget.onDiscard();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(BloomRadius.lg)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
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
              '投稿に失敗しました',
              style: BloomText.headlineSm.copyWith(color: colors.onSurface),
            ),
            const SizedBox(height: 5),
            Text(
              'もう一度送るか、下書きとして残すことができます。',
              style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: BloomText.labelSm.copyWith(color: colors.error),
              ),
            ],
            const SizedBox(height: 14),
            _ActionButton(
              label: _busy ? '再試行しています…' : '再試行',
              background: colors.onSurface,
              foreground: colors.surface,
              onTap: _busy
                  ? null
                  : () => _run('もう一度失敗しました', widget.onRetry),
            ),
            const SizedBox(height: 6),
            _ActionButton(
              label: '下書きとして残す',
              background: colors.surfaceContainer,
              foreground: colors.onSurface,
              onTap: _busy
                  ? null
                  : () => _run('保存できませんでした', widget.onSaveDraft),
            ),
            const SizedBox(height: 6),
            _ActionButton(
              label: '破棄',
              background: Colors.transparent,
              foreground: colors.error,
              border: colors.error.withValues(alpha: 0.4),
              onTap: _busy ? null : _discard,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.border,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color? border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          border: border != null ? Border.all(color: border!) : null,
          borderRadius: BorderRadius.circular(BloomRadius.base),
        ),
        child: Text(
          label,
          style: BloomText.labelSm.copyWith(
            color: disabled ? foreground.withValues(alpha: 0.5) : foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
