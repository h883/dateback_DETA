import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/bloom_api.dart';
import '../../models/models.dart';
import '../../proximity/proximity_service.dart';
import '../../theme/bloom_theme.dart';
import '../../widgets/remote_image.dart';

/// フレンド追加画面（仕様書 13）。
///
/// この画面を開いている間だけ、フレンド未登録のユーザーを候補として出す
/// （仕様書 6.4 / 7.2）。BLE が入るまでは API の候補一覧で代用する。
class AddFriendTab extends StatefulWidget {
  const AddFriendTab({
    super.key,
    required this.api,
    required this.onToast,
    required this.proximity,
  });

  final BloomApi api;
  final void Function(String message) onToast;
  final ProximityService proximity;

  @override
  State<AddFriendTab> createState() => _AddFriendTabState();
}

class _AddFriendTabState extends State<AddFriendTab> {
  List<Profile> _candidates = const [];
  FriendRequests _requests = FriendRequests.empty;
  bool _searching = true;

  /// 申請を送った相手（承認待ち表示用）。
  final _pendingOut = <String>{};

  /// Bluetooth が使えないときの理由。
  ProximityStatus? _blockedBy;
  StreamSubscription<ProximityStatus>? _statusSub;

  /// この画面を開いている間は、素早く見つかるよう短い間隔で探し続ける
  /// （バックグラウンドの15秒間隔とは別に、明示的に探している間だけ速くする）。
  Timer? _autoSearchTimer;
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
    _search();
    _autoSearchTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_searchInFlight) _search();
    });
  }

  @override
  void dispose() {
    _autoSearchTimer?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  /// この画面を開いている間だけ非フレンドを探す（仕様書 7.2）。
  Future<void> _search() async {
    _searchInFlight = true;
    setState(() {
      _searching = true;
      _blockedBy = null;
    });
    try {
      final requests = await widget.api.fetchFriendRequests();

      // BLE で拾った beaconId のうち、非フレンドだけを候補にする。
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
        _requests = requests;
        _pendingOut
          ..clear()
          ..addAll(requests.outgoing.map((p) => p.uid));
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      widget.onToast('近くのユーザーを探せませんでした');
    } finally {
      _searchInFlight = false;
    }
  }

  Future<void> _request(Profile target) async {
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingOut.remove(target.uid));
      widget.onToast('申請を送れませんでした');
    }
  }

  Future<void> _accept(Profile from) async {
    try {
      await widget.api.acceptFriend(from.uid);
      if (!mounted) return;
      widget.onToast('${from.username}さんとフレンドになりました');
      await _search();
    } catch (e) {
      if (mounted) widget.onToast('承認できませんでした');
    }
  }

  Future<void> _reject(Profile from) async {
    try {
      await widget.api.cancelFriendRequest(from.uid);
      if (!mounted) return;
      await _search();
    } catch (e) {
      if (mounted) widget.onToast('操作できませんでした');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 26, 18, 26),
      children: [
        if (_blockedBy != null) _blockedNotice(_blockedBy!) else _searchState(),
        const SizedBox(height: 16),
        for (final request in _requests.incoming) ...[
          _IncomingRequest(
            api: widget.api,
            from: request,
            onAccept: () => _accept(request),
            onReject: () => _reject(request),
          ),
          const SizedBox(height: 10),
        ],
        if (!_searching && _candidates.isEmpty && _requests.incoming.isEmpty)
          _notFound()
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

  Widget _searchState() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_searching) ...[
          const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: BloomColors.primaryContainer,
            ),
          ),
          const SizedBox(width: 9),
        ],
        Text(
          _searching ? '近くのユーザーを探しています…' : '近くのユーザー',
          style: BloomText.bodyMd.copyWith(color: BloomColors.secondary),
        ),
      ],
    );
  }

  /// 仕様書 10.4 / 15 の Bluetooth OFF・権限不足の表示。
  Widget _blockedNotice(ProximityStatus status) {
    final message = switch (status) {
      ProximityStatus.bluetoothOff => 'Bluetoothを有効にしてください',
      ProximityStatus.permissionDenied =>
        '近くのユーザーを探すにはBluetoothの利用許可が必要です',
      _ => 'この端末では近くのユーザーを探せません',
    };
    return Container(
      padding: const EdgeInsets.all(BloomSpace.md),
      decoration: BoxDecoration(
        color: BloomColors.surfaceContainerLow,
        border: Border.all(color: BloomColors.outlineVariant),
        borderRadius: BorderRadius.circular(BloomRadius.base),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_disabled,
              color: BloomColors.secondary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: BloomText.bodySm.copyWith(color: BloomColors.onSurface),
            ),
          ),
          TextButton(
            onPressed: _search,
            child: Text('再試行',
                style: BloomText.labelSm.copyWith(color: BloomColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _notFound() => Column(
        children: [
          const SizedBox(height: 24),
          Text(
            '近くにユーザーが見つかりませんでした',
            style: BloomText.bodySm.copyWith(color: BloomColors.secondary),
          ),
          const SizedBox(height: BloomSpace.md),
          TextButton(
            onPressed: _search,
            child: Text(
              'もう一度探す',
              style: BloomText.labelMd.copyWith(color: BloomColors.primary),
            ),
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: BloomColors.surfaceContainerLow,
        border: Border.all(color: BloomColors.outlineVariant),
        borderRadius: BorderRadius.circular(BloomRadius.base),
      ),
      child: Row(
        children: [
          RemoteAvatar(api: api, path: profile.avatarPath, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              profile.username,
              style: BloomText.labelLg.copyWith(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (waiting)
            Text(
              '承認待ち',
              style: BloomText.labelSm.copyWith(color: BloomColors.secondary),
            )
          else
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: BloomColors.surfaceContainerHigh,
                  border: Border.all(color: const Color(0xFF8D3B0C)),
                  borderRadius: BorderRadius.circular(BloomRadius.base),
                ),
                child: Text(
                  '追加',
                  style: BloomText.labelSm
                      .copyWith(color: const Color(0xFFFFB18B)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IncomingRequest extends StatelessWidget {
  const _IncomingRequest({
    required this.api,
    required this.from,
    required this.onAccept,
    required this.onReject,
  });

  final BloomApi api;
  final Profile from;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BloomColors.surfaceContainerLow,
        border: Border.all(color: BloomColors.outlineVariant),
        borderRadius: BorderRadius.circular(BloomRadius.base),
      ),
      child: Column(
        children: [
          Row(
            children: [
              RemoteAvatar(api: api, path: from.avatarPath, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      from.username,
                      style: BloomText.labelLg
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'フレンド申請が届いています',
                      style: BloomText.labelSm
                          .copyWith(color: BloomColors.secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _action(
                  'キャンセル',
                  onReject,
                  background: BloomColors.surfaceContainerHigh,
                  foreground: BloomColors.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _action(
                  '追加する',
                  onAccept,
                  background: BloomColors.primaryContainer,
                  foreground: const Color(0xFF2D0F00),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(
    String label,
    VoidCallback onTap, {
    required Color background,
    required Color foreground,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(BloomRadius.base),
        ),
        child: Text(
          label,
          style: BloomText.labelSm
              .copyWith(color: foreground, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
