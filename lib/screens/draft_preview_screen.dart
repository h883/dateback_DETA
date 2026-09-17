import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../api/bloom_api.dart';
import '../drafts/draft_store.dart';
import '../theme/bloom_theme.dart';
import '../widgets/film_effects.dart';
import 'tabs/post_tab.dart' show PostOutcome, PostSuccess;

/// 下書き1件のプレビュー(投稿前確認)。
///
/// PostTab の撮影後プレビューへ特殊分岐を大量に足すのではなく、下書き専用の
/// 小さな画面として独立させてある。ここでの再投稿は撮影地を取り直さず、
/// 下書き保存時点の [PostDraft.locationLabel] をそのまま使う。
class DraftPreviewScreen extends StatefulWidget {
  const DraftPreviewScreen({
    super.key,
    required this.api,
    required this.draft,
    required this.onPostResult,
    required this.onChanged,
  });

  final BloomApi api;
  final PostDraft draft;

  /// 投稿成功時だけ呼ぶ。MainShell 側の既存の成功体験(Home へ戻る +
  /// 「✓ 投稿しました / 投稿を見る」バナー)をそのまま再利用するため、
  /// PostTab が MainShell へ渡しているのと同じ callback をそのまま流用する。
  final void Function(PostOutcome outcome) onPostResult;

  /// 投稿成功・削除のどちらでも呼ぶ(Camera の下書き件数バッジ更新用)。
  final VoidCallback onChanged;

  @override
  State<DraftPreviewScreen> createState() => _DraftPreviewScreenState();
}

class _DraftPreviewScreenState extends State<DraftPreviewScreen> {
  bool _posting = false;
  bool _deleting = false;
  String? _error;

  bool get _busy => _posting || _deleting;

  /// 投稿。API 成功後にだけ下書き本体を削除する(先に消さない)。
  /// 成功したら MainShell の既存の成功体験へそのまま合流する。
  Future<void> _post() async {
    if (_busy) return;
    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      final bytes = await DraftStore.instance.readBytes(widget.draft);
      await widget.api.createPost(
        bytes: bytes,
        kind: widget.draft.kind,
        contentType: widget.draft.contentType,
        locationLabel: widget.draft.locationLabel,
      );
      await DraftStore.instance.delete(widget.draft);
      if (!mounted) return;
      widget.onChanged();
      Navigator.of(context).pop();
      widget.onPostResult(const PostSuccess());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _posting = false;
        _error = '投稿できませんでした。もう一度お試しください。';
      });
    }
  }

  Future<void> _confirmDelete() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteDraftDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await DraftStore.instance.delete(widget.draft);
      if (!mounted) return;
      widget.onChanged();
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = '削除できませんでした';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final draft = widget.draft;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _header(colors),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (draft.locationLabel != null) ...[
                        _location(colors, draft.locationLabel!),
                        const SizedBox(height: 6),
                      ],
                      _media(colors, draft),
                      const SizedBox(height: 10),
                      Text(
                        '${draft.kind.wire} ・ ${_formatSavedAt(draft.createdAt)} に保存',
                        style: BloomText.labelSm
                            .copyWith(color: colors.onSurfaceVariant),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: BloomText.labelSm.copyWith(color: colors.error),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _actions(colors),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BloomColorsExt colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 14, 6),
      child: IconButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        icon: Icon(Icons.arrow_back_ios_new, size: 18, color: colors.onSurface),
      ),
    );
  }

  Widget _location(BloomColorsExt colors, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.place_outlined, size: 12, color: colors.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(label, style: BloomText.labelSm.copyWith(color: colors.onSurfaceVariant)),
      ],
    );
  }

  Widget _media(BloomColorsExt colors, PostDraft draft) {
    return AspectRatio(
      aspectRatio: 3 / 2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BloomRadius.md),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Film8mmEffects(
            active: draft.kind.isVideo,
            child: FutureBuilder<File>(
              future: DraftStore.instance.mediaFile(draft),
              builder: (context, snap) {
                final file = snap.data;
                if (file == null) return const SizedBox.shrink();
                return draft.kind.isVideo
                    ? _LocalVideoPreview(file: file)
                    : Image.file(file, fit: BoxFit.cover);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions(BloomColorsExt colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActionButton(
          label: _posting ? '投稿しています…' : '投稿する',
          background: colors.onSurface,
          foreground: colors.surface,
          onTap: _busy ? null : _post,
        ),
        const SizedBox(height: 8),
        _ActionButton(
          label: _deleting ? '削除しています…' : '削除',
          background: Colors.transparent,
          foreground: colors.error,
          border: colors.error.withValues(alpha: 0.4),
          onTap: _busy ? null : _confirmDelete,
        ),
      ],
    );
  }
}

class _LocalVideoPreview extends StatefulWidget {
  const _LocalVideoPreview({required this.file});

  final File file;

  @override
  State<_LocalVideoPreview> createState() => _LocalVideoPreviewState();
}

class _LocalVideoPreviewState extends State<_LocalVideoPreview> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final controller = VideoPlayerController.file(widget.file);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    // 3:2 の枠いっぱいに収める(RemoteVideo と同じ考え方)。
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _DeleteDraftDialog extends StatelessWidget {
  const _DeleteDraftDialog();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.surfaceContainerLow,
      title: Text(
        'この下書きを削除しますか?',
        style: BloomText.headlineSm.copyWith(color: colors.onSurface),
      ),
      content: Text(
        '削除すると元に戻せません。',
        style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('キャンセル', style: TextStyle(color: colors.onSurfaceVariant)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('削除する', style: TextStyle(color: colors.error)),
        ),
      ],
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
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          border: border != null ? Border.all(color: border!) : null,
          borderRadius: BorderRadius.circular(BloomRadius.base),
        ),
        child: Text(
          label,
          style: BloomText.labelMd.copyWith(
            color: disabled ? foreground.withValues(alpha: 0.5) : foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _formatSavedAt(DateTime dt) {
  final y = (dt.year % 100).toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return "'$y ${dt.month} ${dt.day.toString().padLeft(2, '0')} $hh:$mm";
}
