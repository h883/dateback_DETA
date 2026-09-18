import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../device/app_permissions.dart';
import '../theme/bloom_theme.dart';
import '../widgets/wordmark.dart';

class _PermRow {
  const _PermRow({
    required this.kind,
    required this.title,
    required this.why,
    required this.icon,
  });

  final AppPermissionKind kind;
  final String title;
  final String why;
  final IconData icon;
}

const _rows = <_PermRow>[
  _PermRow(
    kind: AppPermissionKind.camera,
    title: 'カメラ',
    why: '写真・8mm動画を撮影します',
    icon: Icons.camera_alt_outlined,
  ),
  _PermRow(
    kind: AppPermissionKind.bluetooth,
    title: 'Bluetooth',
    why: '近くで会った友達を検知します',
    icon: Icons.bluetooth_searching,
  ),
  _PermRow(
    kind: AppPermissionKind.location,
    title: '位置情報',
    why: '近くの友達を探すときに使います',
    icon: Icons.location_on_outlined,
  ),
  _PermRow(
    kind: AppPermissionKind.notification,
    title: '通知',
    why: 'フレンド申請やいいねを知らせます',
    icon: Icons.notifications_none,
  ),
];

/// 初回起動の「利用開始前セットアップ」。1画面にまとめる
/// (カメラ・Bluetooth・位置情報・通知。マイクは要求しない)。
///
/// OS の許可ダイアログは、この画面の主要アクション(「許可をリクエスト」)
/// から Camera → Bluetooth → Location → Notification の順に1回だけ
/// まとめて要求する。各行の lamp は実際の OS permission status を
/// source of truth とし、ボタンを押しただけで Granted 扱いにはしない
/// ([AppPermissions]/[lampStateFor] 参照)。
///
/// この画面より後(Tutorial/Home 到達後)は、Camera/BLE/位置情報のどの
/// service/controller も新たに OS permission dialog を出さない
/// (PostTab の lazy-init、BleProximityService の status 専用チェックを参照)。
class ConsentPermissionScreen extends StatefulWidget {
  const ConsentPermissionScreen({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  State<ConsentPermissionScreen> createState() =>
      _ConsentPermissionScreenState();
}

class _ConsentPermissionScreenState extends State<ConsentPermissionScreen>
    with WidgetsBindingObserver {
  final Map<AppPermissionKind, LampState> _lamp = {
    for (final row in _rows) row.kind: LampState.gray,
  };

  /// この画面から一度でも要求したことがある種類。denied を
  /// 「未要求(gray)」と「要求済みで拒否(warn)」で区別するために使う。
  final Set<AppPermissionKind> _requestedOnce = {};

  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAllLamps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Settings アプリから戻った場合や、OS ダイアログの裏で一瞬 inactive に
  /// なった端末でも、resumed のたびに実際の状態を取り直して lamp を
  /// 同期させる。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAllLamps();
    }
  }

  Future<void> _refreshAllLamps() async {
    final next = <AppPermissionKind, LampState>{};
    for (final row in _rows) {
      final readout = await AppPermissions.read(row.kind);
      next[row.kind] = lampStateFor(
        granted: readout.granted,
        permanentlyDenied: readout.permanentlyDenied,
        requestedOnce: _requestedOnce.contains(row.kind),
      );
    }
    if (!mounted) return;
    setState(() => _lamp
      ..clear()
      ..addAll(next));
  }

  /// 主要アクション。Camera → Bluetooth → Location → Notification の順に
  /// 1つずつ要求し、結果が返るたびに該当 lamp を即時更新する。
  Future<void> _requestAllInOrder() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    for (final row in _rows) {
      await _requestOne(row.kind);
    }
    if (mounted) setState(() => _requesting = false);
  }

  Future<void> _requestOne(AppPermissionKind kind) async {
    _requestedOnce.add(kind);
    final readout = await AppPermissions.request(kind);
    if (!mounted) return;
    setState(() {
      _lamp[kind] = lampStateFor(
        granted: readout.granted,
        permanentlyDenied: readout.permanentlyDenied,
        requestedOnce: true,
      );
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
              _PermissionTile(row: row, lamp: _lamp[row.kind]!),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 12),
            _ConsentNote(onOpenPolicy: _openPolicy),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _requesting ? null : _requestAllInOrder,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.onSurface,
                  side: BorderSide(color: colors.outlineVariant),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  _requesting ? '確認中…' : '権限をまとめて許可する',
                  style: BloomText.labelLg.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
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
  const _PermissionTile({required this.row, required this.lamp});

  final _PermRow row;
  final LampState lamp;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
              color: colors.surfaceContainer,
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Icon(row.icon, size: 17, color: colors.onSurfaceVariant),
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
          const SizedBox(width: 10),
          _Lamp(state: lamp),
        ],
      ),
    );
  }
}

/// permission 状態を表す小さなランプ。実際の OS permission status だけを
/// 反映する読み取り専用の表示(タップでは何も起きない)。
class _Lamp extends StatelessWidget {
  const _Lamp({required this.state});

  final LampState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (Color dot, String label) = switch (state) {
      LampState.gray => (colors.outlineVariant, '未許可'),
      LampState.green => (const Color(0xFF3FA772), '許可済み'),
      LampState.warn => (const Color(0xFFC98A3A), '許可されず'),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(height: 4),
        Text(label, style: BloomText.labelSm.copyWith(color: colors.onSurfaceVariant)),
      ],
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
