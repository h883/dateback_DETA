import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/bloom_theme.dart';
import '../widgets/wordmark.dart';

enum _PermKind { camera, bluetooth, location, notification }

class _PermRow {
  const _PermRow({
    required this.kind,
    required this.title,
    required this.why,
    required this.icon,
  });

  final _PermKind kind;
  final String title;
  final String why;
  final IconData icon;
}

const _rows = <_PermRow>[
  _PermRow(
    kind: _PermKind.camera,
    title: 'カメラ',
    why: '写真・8mm動画を撮影します',
    icon: Icons.camera_alt_outlined,
  ),
  _PermRow(
    kind: _PermKind.bluetooth,
    title: 'Bluetooth',
    why: '近くで会った友達を検知します',
    icon: Icons.bluetooth_searching,
  ),
  _PermRow(
    kind: _PermKind.location,
    title: '位置情報',
    why: '近くの友達を探すときに使います',
    icon: Icons.location_on_outlined,
  ),
  _PermRow(
    kind: _PermKind.notification,
    title: '通知',
    why: 'フレンド申請やいいねを知らせます',
    icon: Icons.notifications_none,
  ),
];

/// 初回起動の「利用開始前セットアップ」。1画面にまとめる
/// (カメラ・Bluetooth・位置情報・通知。マイクは要求しない)。
///
/// 各 permission は OS の作法どおり1回だけ要求する。拒否されても
/// この画面で何度も要求し直したり足止めしたりはせず、「次へ」で進める。
class ConsentPermissionScreen extends StatefulWidget {
  const ConsentPermissionScreen({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  State<ConsentPermissionScreen> createState() =>
      _ConsentPermissionScreenState();
}

class _ConsentPermissionScreenState extends State<ConsentPermissionScreen> {
  /// null = まだ要求していない。
  final Map<_PermKind, bool?> _granted = {
    for (final row in _rows) row.kind: null,
  };
  final Set<_PermKind> _requesting = {};

  Future<void> _request(_PermKind kind) async {
    if (_requesting.contains(kind)) return;
    setState(() => _requesting.add(kind));
    bool granted;
    try {
      switch (kind) {
        case _PermKind.camera:
          granted = (await Permission.camera.request()).isGranted;
        case _PermKind.bluetooth:
          // 仕様書 5.5: Android 12+ は個別権限、12未満は位置情報が要る。
          // BleProximityService の要求内容と揃えている。
          final statuses = await [
            Permission.bluetoothScan,
            Permission.bluetoothAdvertise,
            Permission.bluetoothConnect,
            Permission.locationWhenInUse,
          ].request();
          granted = statuses[Permission.bluetoothScan]?.isGranted != false &&
              statuses[Permission.bluetoothAdvertise]?.isGranted != false;
        case _PermKind.location:
          granted = (await Permission.locationWhenInUse.request()).isGranted;
        case _PermKind.notification:
          granted = (await Permission.notification.request()).isGranted;
      }
    } catch (_) {
      granted = false;
    }
    if (!mounted) return;
    setState(() {
      _requesting.remove(kind);
      _granted[kind] = granted;
    });
  }

  void _openPolicy(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$labelは近日公開します')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          children: [
            const Wordmark(),
            const SizedBox(height: 22),
            Text(
              'はじめる前に',
              style: BloomText.headlineLg.copyWith(color: colors.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              '近くの友達との交換や撮影に使う権限です。あとから設定でも変更できます。',
              style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            for (final row in _rows) ...[
              _PermissionTile(
                row: row,
                granted: _granted[row.kind],
                busy: _requesting.contains(row.kind),
                onTap: () => _request(row.kind),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 12),
            _ConsentNote(onOpenPolicy: _openPolicy),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: widget.onNext,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.onSurface,
                  foregroundColor: colors.surface,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  '次へ',
                  style: BloomText.labelLg.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.row,
    required this.granted,
    required this.busy,
    required this.onTap,
  });

  final _PermRow row;
  final bool? granted;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final done = granted != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(BloomRadius.base),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: granted == true
                  ? colors.primary.withValues(alpha: 0.16)
                  : colors.surfaceContainer,
              border: Border.all(
                color: granted == true ? colors.primary : colors.outlineVariant,
              ),
            ),
            child: Icon(
              granted == true ? Icons.check : row.icon,
              size: 17,
              color: granted == true ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  style: BloomText.labelLg.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                Text(
                  row.why,
                  style: BloomText.labelSm.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: (busy || done) ? null : onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                border: Border.all(color: colors.outlineVariant),
                borderRadius: BorderRadius.circular(BloomRadius.pill),
              ),
              child: Text(
                granted == true
                    ? '許可済み'
                    : granted == false
                        ? '許可されず'
                        : (busy ? '確認中…' : '許可'),
                style: BloomText.labelSm.copyWith(color: colors.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentNote extends StatelessWidget {
  const _ConsentNote({required this.onOpenPolicy});

  final void Function(String label) onOpenPolicy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final linkStyle = BloomText.labelSm.copyWith(
      color: colors.onSurface,
      decoration: TextDecoration.underline,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(BloomRadius.base),
      ),
      child: Text.rich(
        TextSpan(
          style: BloomText.labelSm.copyWith(color: colors.onSurfaceVariant),
          children: [
            const TextSpan(text: '次へ進むことで '),
            TextSpan(
              text: '利用規約',
              style: linkStyle,
              recognizer: (TapGestureRecognizer()
                ..onTap = () => onOpenPolicy('利用規約')),
            ),
            const TextSpan(text: ' / '),
            TextSpan(
              text: 'プライバシーポリシー',
              style: linkStyle,
              recognizer: (TapGestureRecognizer()
                ..onTap = () => onOpenPolicy('プライバシーポリシー')),
            ),
            const TextSpan(text: ' に同意したものとします。'),
          ],
        ),
      ),
    );
  }
}
