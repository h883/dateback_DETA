import 'dart:io';

import 'package:flutter/material.dart';

import '../api/bloom_api.dart';
import '../drafts/draft_store.dart';
import '../theme/bloom_theme.dart';
import 'draft_preview_screen.dart';
import 'tabs/post_tab.dart' show PostOutcome;

/// 保存済み下書きの一覧シート。
///
/// Camera 画面の下書きアイコンから開く。行をタップすると、このシートを
/// 閉じてから [DraftPreviewScreen] へ遷移する(投稿する/削除/戻る はそちら
/// の責務)。
Future<void> showDraftsSheet(
  BuildContext context, {
  required BloomApi api,
  required void Function(PostOutcome outcome) onPostResult,
  required VoidCallback onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DraftsSheet(
      api: api,
      onPostResult: onPostResult,
      onChanged: onChanged,
    ),
  );
}

class _DraftsSheet extends StatefulWidget {
  const _DraftsSheet({
    required this.api,
    required this.onPostResult,
    required this.onChanged,
  });

  final BloomApi api;
  final void Function(PostOutcome outcome) onPostResult;
  final VoidCallback onChanged;

  @override
  State<_DraftsSheet> createState() => _DraftsSheetState();
}

class _DraftsSheetState extends State<_DraftsSheet> {
  List<PostDraft>? _drafts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final drafts = await DraftStore.instance.loadAll();
    if (!mounted) return;
    setState(() => _drafts = drafts);
  }

  /// このシートを閉じてから Draft preview を開く(同じ Navigator スタック上
  /// に積まれているので、先に NavigatorState を確保してから pop する)。
  void _openPreview(PostDraft draft) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute(
        builder: (_) => DraftPreviewScreen(
          api: widget.api,
          draft: draft,
          onPostResult: widget.onPostResult,
          onChanged: widget.onChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(BloomRadius.lg)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
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
              '下書き',
              style: BloomText.headlineSm.copyWith(color: colors.onSurface),
            ),
            const SizedBox(height: 12),
            Flexible(child: _content(colors)),
          ],
        ),
      ),
    );
  }

  Widget _content(BloomColorsExt colors) {
    final drafts = _drafts;
    if (drafts == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (drafts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '下書きはありません',
            style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: drafts.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: colors.outlineVariant),
      itemBuilder: (context, i) => _DraftRow(
        draft: drafts[i],
        onTap: () => _openPreview(drafts[i]),
      ),
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({required this.draft, required this.onTap});

  final PostDraft draft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 63,
                height: 42,
                child: _DraftThumbnail(draft: draft),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        draft.kind.wire,
                        style: BloomText.labelSm.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatSavedAt(draft.createdAt),
                        style: BloomText.labelSm
                            .copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                  if (draft.locationLabel != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.place_outlined,
                            size: 11, color: colors.onSurfaceVariant),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            draft.locationLabel!,
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
            Icon(Icons.chevron_right, size: 18, color: colors.outline),
          ],
        ),
      ),
    );
  }
}

class _DraftThumbnail extends StatelessWidget {
  const _DraftThumbnail({required this.draft});

  final PostDraft draft;

  @override
  Widget build(BuildContext context) {
    if (draft.kind.isVideo) {
      return const ColoredBox(
        color: Color(0xFF1F1714),
        child: Center(
          child: Icon(Icons.play_circle_outline,
              color: BloomColors.secondary, size: 18),
        ),
      );
    }
    return FutureBuilder<File>(
      future: DraftStore.instance.mediaFile(draft),
      builder: (context, snap) {
        final file = snap.data;
        if (file == null) {
          return ColoredBox(color: context.colors.surfaceContainerHigh);
        }
        return Image.file(file, fit: BoxFit.cover);
      },
    );
  }
}

String _formatSavedAt(DateTime dt) {
  final y = (dt.year % 100).toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return "'$y ${dt.month} ${dt.day.toString().padLeft(2, '0')} $hh:$mm";
}
