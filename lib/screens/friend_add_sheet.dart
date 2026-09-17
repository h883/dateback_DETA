import 'dart:async';

import 'package:flutter/material.dart';

import '../api/bloom_api.dart';
import '../models/models.dart';
import '../proximity/proximity_service.dart';
import '../theme/bloom_theme.dart';
import '../widgets/remote_image.dart';

/// フレンド追加のボトムシートを開く。
///
/// Home 右上の person+ と、フレンド一覧右上の person+ の両方から呼ぶ。
/// `showModalBottomSheet` はオーバーレイとして重なるだけなので、閉じれば
/// 呼び出し元の画面（Home / フレンド一覧）へそのまま戻る。
Future<void> showFriendAddSheet(
  BuildContext context, {
  required BloomApi api,
  required ProximityService proximity,
  required void Function(String message) onToast,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        FriendAddSheet(api: api, proximity: proximity, onToast: onToast),
  );
}

/// フレンド未登録の近くのユーザーを探して申請するシート（仕様書 13）。
///
/// この画面（シート）を開いている間だけ、フレンド未登録のユーザーを候補
/// として出す（仕様書 6.4 / 7.2）。受信したフレンド申請の承認・拒否は
/// 通知画面に一本化したため、ここでは扱わない。
class FriendAddSheet extends StatefulWidget {
  const FriendAddSheet({
    super.key,
    required this.api,
    required this.proximity,
    required this.onToast,
  });

  final BloomApi api;
  final ProximityService proximity;
  final void Function(String message) onToast;

  @override
  State<FriendAddSheet> createState() => _FriendAddSheetState();
}

class _FriendAddSheetState extends State<FriendAddSheet> {
  List<Profile> _candidates = const [];
  bool _searching = true;

  /// 申請を送った相手(承認待ち表示・重複送信防止用)。
  final _pendingOut = <String>{};

  /// Bluetooth が使えないときの理由。
  ProximityStatus? _blockedBy;
  StreamSubscription<ProximityStatus>? _statusSub;

  /// BLE のスキャンは常時回っているが、電波の受信にはムラがあり、
  /// 同じ相手でも一瞬 _peerTtl(BleProximityService 側)を超えて
  /// 見失っては再検知する、を繰り返すことがある。「消えた」ことでは
  /// 再検索せず、一度も見ていない beaconId が新しく現れたときだけ
  /// サーバーに解決要求を投げる。
  StreamSubscription<List<NearbyPeer>>? _peersSub;
  final _seenPeerBeaconIds = <String>{};

  /// シートを開いている間、変化が無くても低頻度で見直す。
  Timer? _fallbackTimer;
  bool _searchInFlight = false;

  @override
  void initState() {
    super.initState();
    _statusSub = widget.proximity.status.listen((status) {
      if (!mounted) return;
      if (status == ProximityStatus.bluetoothOff ||
          status == ProximityStatus.permissionDenied ||
          status == ProximityStatus.unsupported) {
        setState(() {
          _blockedBy = status;
          _searching = false;
        });
      }
    });
    _peersSub = widget.proximity.peers.listen((peers) {
      final newOnes = peers
          .map((p) => p.beaconId)
          .where((id) => !_seenPeerBeaconIds.contains(id))
          .toList();
      if (newOnes.isEmpty) return;
      _seenPeerBeaconIds.addAll(newOnes);
      if (!_searchInFlight) _search(silent: true);
    });
    _search();
    _fallbackTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_searchInFlight) _search(silent: true);
    });
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _peersSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  /// この画面を開いている間だけ非フレンドを探す(仕様書 7.2)。
  ///
  /// [silent] のときはバックグラウンドでの定期更新なので、スピナーは
  /// 出さない。初回表示と、ユーザーが「再試行」等を押したときだけ
  /// スピナーを見せる。
  Future<void> _search({bool silent = false}) async {
    _searchInFlight = true;
    if (!silent) {
      setState(() {
        _searching = true;
        _blockedBy = null;
      });
    }
    try {
      // 送信済み申請の相手には重複送信しない。resolveBeacons の discover
      // モードは「フレンドでない」だけで絞るので、申請中かどうかは
      // 別途 fetchFriendRequests().outgoing で確認する。
      final requests = await widget.api.fetchFriendRequests();

      final peers = await widget.proximity.scanOnce();
      final resolved = peers.isEmpty
          ? null
          : await widget.api.resolveBeacons(
              peers.map((p) => p.beaconId).toList(),
              discover: true,
            );

      if (!mounted) return;
      setState(() {
        _candidates = resolved?.strangers ?? const [];
        _pendingOut
          ..clear()
          ..addAll(requests.outgoing.map((p) => p.uid));
        _searching = false;
        _blockedBy = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
      if (!silent) widget.onToast('近くのユーザーを探せませんでした');
    } finally {
      _searchInFlight = false;
    }
  }

  Future<void> _request(Profile target) async {
    // 二重タップ防止。押した瞬間に「承認待ち」表示へ切り替える。
    setState(() => _pendingOut.add(target.uid));
    try {
      final status = await widget.api.requestFriend(target.uid);
      if (!mounted) return;
      if (status == 'accepted') {
        widget.onToast('${target.username}さんとフレンドになりました');
        await _search();
      } else {
        widget.onToast('${target.username}さんの承認を待っています');
      }
    } catch (_) {
      // 失敗したら候補を消さず、再試行できる状態に戻す。
      if (!mounted) return;
      setState(() => _pendingOut.remove(target.uid));
      widget.onToast('申請を送れませんでした');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
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
              '近くの人を探す',
              style: BloomText.headlineSm.copyWith(color: colors.onSurface),
            ),
            const SizedBox(height: 5),
            Text(
              '普段は自動検知。見つからないときだけ、ここから再検索します。',
              style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Flexible(child: SingleChildScrollView(child: _content(colors))),
          ],
        ),
      ),
    );
  }

  Widget _content(BloomColorsExt colors) {
    if (_blockedBy != null) return _blockedNotice(_blockedBy!, colors);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _searchState(colors),
        const SizedBox(height: 14),
        if (!_searching && _candidates.isEmpty)
          _emptyState(colors)
        else
          for (final candidate in _candidates) ...[
            _CandidateRow(
              api: widget.api,
              profile: candidate,
              waiting: _pendingOut.contains(candidate.uid),
              onAdd: () => _request(candidate),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _searchState(BloomColorsExt colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_searching) ...[
          SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 9),
        ],
        Text(
          _searching ? '近くのユーザーを探しています…' : '近くのユーザー',
          style: BloomText.bodyMd.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  /// 仕様書 10.4 / 15 の Bluetooth OFF・権限不足の表示。
  Widget _blockedNotice(ProximityStatus status, BloomColorsExt colors) {
    final message = switch (status) {
      ProximityStatus.bluetoothOff => 'Bluetoothを有効にしてください',
      ProximityStatus.permissionDenied =>
        '近くのユーザーを探すにはBluetoothの利用許可が必要です',
      _ => 'この端末では近くのユーザーを探せません',
    };
    return Container(
      padding: const EdgeInsets.all(BloomSpace.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(BloomRadius.base),
      ),
      child: Row(
        children: [
          Icon(Icons.bluetooth_disabled, color: colors.onSurfaceVariant, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: BloomText.bodySm.copyWith(color: colors.onSurface),
            ),
          ),
          TextButton(
            onPressed: _search,
            child: Text('再試行',
                style: BloomText.labelSm.copyWith(color: colors.primary)),
          ),
        ],
      ),
    );
  }

  /// 0人のとき。静かな表示で、押せば再探索できる。
  Widget _emptyState(BloomColorsExt colors) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Text(
              '近くにユーザーが見つかりませんでした',
              style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: BloomSpace.md),
            TextButton(
              onPressed: _search,
              child: Text(
                'もう一度探す',
                style: BloomText.labelMd.copyWith(color: colors.primary),
              ),
            ),
          ],
        ),
      );
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.api,
    required this.profile,
    required this.waiting,
    required this.onAdd,
  });

  final BloomApi api;
  final Profile profile;
  final bool waiting;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(BloomRadius.base),
      ),
      child: Row(
        children: [
          RemoteAvatar(api: api, path: profile.avatarPath, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              profile.username,
              style: BloomText.labelLg.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (waiting)
            Text(
              '承認待ち',
              style: BloomText.labelSm.copyWith(color: colors.onSurfaceVariant),
            )
          else
            GestureDetector(
              onTap: onAdd,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.onSurface,
                  borderRadius: BorderRadius.circular(BloomRadius.base),
                ),
                child: Text(
                  '追加',
                  style: BloomText.labelSm
                      .copyWith(color: colors.surface, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
