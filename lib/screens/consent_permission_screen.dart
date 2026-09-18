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
    why: '近くで会った友達を検知します(古い端末では位置情報の確認も一緒に表示されることがあります)',
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

/// 初回起動の「利用開始前セットアップ」。
///
/// Camera → Bluetooth → Location → Notification の順に、1つ決着(許可 or
/// 拒否)したら次の permission が現れる step-by-step 形式。将来の step は
/// 到達するまで画面に出さない。完了済みの step は上に残り、lamp
/// (green=許可済み / warn=許可されず)で状態が分かる。
///
/// 現在 step の説明(icon/title/理由)がユーザーに一度見えてから、
/// [WidgetsBinding.instance.addPostFrameCallback] + 短い delay を挟んで
/// **自動的に** その permission 1件だけの OS ダイアログを要求する
/// ([_maybeScheduleAutoRequest] / [_requestCurrent])。ユーザーが押す
/// 「許可する」ボタンは存在しない。4つをまとめて連続 request する方式や、
/// initState 直後に画面が見える前に即 request する実装は禁止
/// (どちらも実機での「今何を許可しているか分からない」問題の原因になる)。
///
/// 自動 request は画面 session 内で permission ごとに最大1回だけ
/// scheduleする([_scheduledAuto])。resume(Settings アプリから戻る等)の
/// たびに実行される [_refreshAllLamps] は実際の OS status を取り直す
/// だけで、denied/permanentlyDenied を再 request することはない。
///
/// lamp は実際の OS permission status を source of truth とする
/// ([AppPermissions]/[lampStateFor] 参照)。
///
/// この画面より後(Tutorial/Home 到達後)は、Camera/BLE/位置情報のどの
/// service/controller も新たに OS permission dialog を出さない
/// (PostTab の lazy-init、BleProximityService の status 専用チェックを参照)。
class ConsentPermissionScreen extends StatefulWidget {
  const ConsentPermissionScreen({
    super.key,
    required this.onNext,
    this.debugRead,
    this.debugRequest,
    this.autoRequestDelay = const Duration(milliseconds: 400),
  });

  final VoidCallback onNext;

  /// テスト専用の差し替えフック。本番では常に [AppPermissions.read] を使う。
  @visibleForTesting
  final Future<PermissionReadout> Function(AppPermissionKind)? debugRead;

  /// テスト専用の差し替えフック。本番では常に [AppPermissions.request] を使う。
  @visibleForTesting
  final Future<PermissionReadout> Function(AppPermissionKind)? debugRequest;

  /// 現在 step の UI が描画されてから、自動で OS ダイアログを要求するまでの
  /// 待ち時間。「OS ダイアログが出る直前に何の許可を求めているか見える」
  /// ことが目的の短い delay(本番は 300〜500ms 程度)。widget test では
  /// [Duration.zero] に差し替えて即座に発火させる。
  @visibleForTesting
  final Duration autoRequestDelay;

  @override
  State<ConsentPermissionScreen> createState() =>
      _ConsentPermissionScreenState();
}

class _ConsentPermissionScreenState extends State<ConsentPermissionScreen>
    with WidgetsBindingObserver {
  final Map<AppPermissionKind, LampState> _lamp = {
    for (final row in _rows) row.kind: LampState.gray,
  };

  /// この画面から一度でも実際に request したことがある種類。denied を
  /// 「未要求(gray)」と「要求済みで拒否(warn)」で区別するために使う。
  final Set<AppPermissionKind> _requestedOnce = {};

  /// 自動 request を一度でも schedule した種類(結果を問わない)。
  /// 画面 session 内で同じ kind を二度と自動 schedule しないための
  /// ガード(resume での再発火防止)。
  final Set<AppPermissionKind> _scheduledAuto = {};

  /// 現在表示している step の index。[_rows.length] になったら全 step
  /// 完了で、以降は permission の説明ではなく「次へ」だけを出す。
  int _currentIndex = 0;

  /// 現在 request 中の kind。null なら request 中の permission はない。
  AppPermissionKind? _requestingKind;

  /// 起動直後、最初の [_refreshAllLamps] が終わるまでは実際の
  /// current step が確定していない。確定前に自動 request を schedule
  /// して間違った kind を要求しないためのガード。
  bool _initialized = false;

  Future<PermissionReadout> Function(AppPermissionKind) get _read =>
      widget.debugRead ?? AppPermissions.read;

  Future<PermissionReadout> Function(AppPermissionKind) get _request =>
      widget.debugRequest ?? AppPermissions.request;

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
  /// なった端末でも、resumed のたびに実際の状態を取り直して lamp と
  /// current step を同期させる。[_scheduledAuto] は消さないので、
  /// 既に自動 request 済みの kind がここで再 request されることはない。
  ///
  /// ただし、まさに今 request が in-flight のとき([_requestingKind] が
  /// 非null)は例外的にスキップする。OS の許可ダイアログ自体が
  /// resumed/inactive を発生させることがあり、そのタイミングで読み直すと
  /// 「_requestedOnce には入っているがまだ OS の結果は返っていない」
  /// permission を denied 確定と誤認して次 step へ進めてしまい、前の
  /// ダイアログが開いたままなのに次の permission を request する事故に
  /// なり得る。in-flight の結果反映は [_requestCurrent] 自身が
  /// resolve 後に呼ぶ [_refreshAllLamps] に任せる。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _requestingKind == null) {
      _refreshAllLamps();
    }
  }

  Future<void> _refreshAllLamps() async {
    final next = <AppPermissionKind, LampState>{};
    for (final row in _rows) {
      final readout = await _read(row.kind);
      next[row.kind] = lampStateFor(
        granted: readout.granted,
        permanentlyDenied: readout.permanentlyDenied,
        requestedOnce: _requestedOnce.contains(row.kind),
      );
    }
    if (!mounted) return;
    setState(() {
      _lamp
        ..clear()
        ..addAll(next);
      _currentIndex = _computeCurrentIndex();
      _initialized = true;
    });
  }

  /// まだ一度も決着していない(gray の)最初の permission を現在 step と
  /// する。Bluetooth の request が副作用で位置情報も一緒に確定させた
  /// 場合など、実際の OS status を都度読み直すことで自動的に飛ばし、
  /// Location step での重複 request を避ける。逆に Bluetooth 側で
  /// 位置情報がまだ確定していなければ、Location step は gray のまま
  /// current になり、そこで改めて明示的に request される。
  int _computeCurrentIndex() {
    final idx = _rows.indexWhere((row) => _lamp[row.kind] == LampState.gray);
    return idx == -1 ? _rows.length : idx;
  }

  /// 現在 step が確定していて、まだ自動 request を schedule していなければ、
  /// 1フレーム後(=現在 step の説明が画面に描画された後)+ 短い delay で
  /// 自動的に [_requestCurrent] を1回だけ発火するよう予約する。
  ///
  /// build() のたびに呼んでよい: [_scheduledAuto] へ同期的に登録してから
  /// 予約するため、同じ kind を二重に schedule することはない。
  void _maybeScheduleAutoRequest() {
    if (!_initialized || _currentIndex >= _rows.length) return;
    final kind = _rows[_currentIndex].kind;
    if (_scheduledAuto.contains(kind)) return;
    _scheduledAuto.add(kind);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(widget.autoRequestDelay, () {
        if (!mounted) return;
        // schedule 後に状態が進んでいたら(通常は起きないが)何もしない。
        if (_currentIndex >= _rows.length) return;
        if (_rows[_currentIndex].kind != kind) return;
        if (_requestingKind != null) return;
        _requestCurrent();
      });
    });
  }

  /// 現在 step の permission だけを request する。他の permission には
  /// 一切触れない(=まとめて連続 request しない)。
  Future<void> _requestCurrent() async {
    if (_requestingKind != null || _currentIndex >= _rows.length) return;
    final kind = _rows[_currentIndex].kind;
    setState(() => _requestingKind = kind);
    _requestedOnce.add(kind);
    await _request(kind);
    await _refreshAllLamps();
    if (!mounted) return;
    setState(() => _requestingKind = null);
  }

  void _openPolicy(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$labelは近日公開します')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 現在 step の説明を実際に描画してから自動 request する。setState を
    // 同期的に呼ばないので build 中に呼んでも安全。
    _maybeScheduleAutoRequest();

    final colors = context.colors;
    final done = _initialized && _currentIndex >= _rows.length;
    final stepNumber = done ? _rows.length : _currentIndex + 1;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Wordmark(),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'はじめる前に',
                        style:
                            BloomText.headlineLg.copyWith(color: colors.onSurface),
                      ),
                      Text(
                        '$stepNumber / ${_rows.length}',
                        style: BloomText.labelSm
                            .copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '近くの友達との交換や撮影に使う権限です。あとから設定でも変更できます。',
                    style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            Expanded(
              child: !_initialized
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      children: [
                        for (var i = 0; i < _currentIndex; i++) ...[
                          _PermissionTile(
                            row: _rows[i],
                            lamp: _lamp[_rows[i].kind]!,
                            onOpenSettings: _lamp[_rows[i].kind] == LampState.warn
                                ? AppPermissions.openSettings
                                : null,
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (!done)
                          _CurrentStepCard(
                            row: _rows[_currentIndex],
                            requesting: _requestingKind == _rows[_currentIndex].kind,
                          ),
                        const SizedBox(height: 16),
                        _ConsentNote(onOpenPolicy: _openPolicy),
                      ],
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: done
          ? SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: colors.outlineVariant)),
                ),
                child: SizedBox(
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
              ),
            )
          : null,
    );
  }
}

/// これから許可を求める現在 step の説明カード。lamp はまだ決着していない
/// (gray)ので表示しない。ユーザーが押す CTA は無く、[requesting] が
/// true になった時点で「OS の確認を表示しています」に切り替わるだけ
/// ([_maybeScheduleAutoRequest] が自動で発火させる)。
class _CurrentStepCard extends StatelessWidget {
  const _CurrentStepCard({required this.row, required this.requesting});

  final _PermRow row;
  final bool requesting;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(BloomRadius.base),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surfaceContainerLow,
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Icon(row.icon, size: 18, color: colors.onSurface),
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
                const SizedBox(height: 4),
                Text(
                  row.why,
                  style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (requesting) ...[
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      requesting ? 'OSの確認を表示しています…' : 'まもなくOSの確認が表示されます',
                      style: BloomText.labelSm.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 完了済み(green/warn)の permission 行。実際の OS permission status を
/// 反映する読み取り専用の lamp を出す(タップでは何も起きない)。denied
/// の場合のみ、OS 設定アプリを開く小さな導線を出す(自動再 request はしない)。
class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.row,
    required this.lamp,
    this.onOpenSettings,
  });

  final _PermRow row;
  final LampState lamp;
  final Future<void> Function()? onOpenSettings;

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
                if (onOpenSettings != null) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: onOpenSettings,
                    child: Text(
                      '設定を開く',
                      style: BloomText.labelSm.copyWith(
                        color: colors.onSurface,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
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
