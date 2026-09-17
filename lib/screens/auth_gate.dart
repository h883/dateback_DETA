import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../api/bloom_api.dart';
import '../models/models.dart';
import '../settings/settings_store.dart';
import '../theme/bloom_theme.dart';
import '../theme/theme_controller.dart';
import 'consent_permission_screen.dart';
import 'login_screen.dart';
import 'main_shell.dart';
import 'tutorial_completion.dart';
import 'tutorial_screen.dart';

/// 起動後の行き先を決める。
///
/// 未ログイン           → Login
/// ログイン済・未設定   → プロフィールを Google の情報から自動作成
/// 初回チュートリアル未完了 → 同意・権限セットアップ → チュートリアル
/// それ以外              → 本体
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.api,
    required this.themeController,
    required this.settingsStore,
  });

  final BloomApi api;
  final ThemeController themeController;
  final SettingsStore settingsStore;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Profile? _profile;

  /// null = まだ問い合わせていない。
  bool? _profileLoaded;
  String? _error;
  User? _lastUid;
  bool _autoCreatingProfile = false;

  /// null = まだ確認していない。uid ごとに保存されているため、
  /// [_tutorialCheckedUid] と異なる uid になったら必ず確認し直す。
  bool? _tutorialDone;
  String? _tutorialCheckedUid;
  String? _tutorialCheckInFlightUid;

  /// authStateChanges() が一瞬 null を流すことがある(トークンの裏側での
  /// 更新など)。即座にサインアウト扱いにすると MainShell が壊れて作り
  /// 直され、ホームタブに戻ってしまう。少し待って本当に null のままなら
  /// サインアウトとみなす。
  User? _lastSeenUser;
  Timer? _signOutDebounce;
  bool _confirmedSignedOut = false;

  static const _signOutDebounceDuration = Duration(milliseconds: 1200);

  @override
  void dispose() {
    _signOutDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile(User user) async {
    if (_lastUid?.uid == user.uid && _profileLoaded == true) return;
    _lastUid = user;
    try {
      final profile = await widget.api.fetchMyProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _profileLoaded = true;
        _error = null;
      });
    } on BloomApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _profileLoaded = true;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _profileLoaded = true;
        _error = 'サーバーに接続できませんでした: $e';
      });
    }
  }

  /// 強制的なプロフィール設定画面は初回フローに置かない。Google の
  /// 表示名・アイコンで自動的に作成する(不足分・変更は後からプロフィール
  /// 編集で行う)。
  Future<void> _autoCreateProfile(User user) async {
    if (_autoCreatingProfile) return;
    _autoCreatingProfile = true;
    try {
      final displayName = (user.displayName ?? '').trim();
      var profile = await widget.api.saveMyProfile(
        username: displayName.isEmpty ? 'dateback' : displayName,
        bio: '',
      );

      final photoUrl = user.photoURL;
      if (photoUrl != null && photoUrl.isNotEmpty) {
        try {
          final res = await http.get(Uri.parse(photoUrl));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            profile = await widget.api.uploadAvatar(
              res.bodyBytes,
              res.headers['content-type'] ?? 'image/jpeg',
            );
          }
        } catch (_) {
          // アイコンが取れなくても致命的ではない。あとから編集できる。
        }
      }

      if (!mounted) return;
      setState(() => _profile = profile);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'プロフィールを作成できませんでした: $e');
    } finally {
      _autoCreatingProfile = false;
    }
  }

  /// [uid] ごとに完了状態を確認する。別アカウントでログインしたときは
  /// 必ずこれが uid の変化を検知して再確認し、Consent/Tutorial を
  /// 飛ばさないようにする([_tutorialCheckedUid] 参照)。
  Future<void> _checkTutorial(String uid) async {
    if (_tutorialCheckInFlightUid == uid) return;
    _tutorialCheckInFlightUid = uid;
    final done = await TutorialCompletion.isCompleted(uid);
    if (!mounted) return;
    setState(() {
      _tutorialDone = done;
      _tutorialCheckedUid = uid;
    });
  }

  Future<void> _signOut() async {
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    _signOutDebounce?.cancel();
    _signOutDebounce = null;
    setState(() {
      _profile = null;
      _profileLoaded = null;
      _lastUid = null;
      _error = null;
      _lastSeenUser = null;
      _confirmedSignedOut = true;
      // 永続化した完了状態はそのまま。次回ログイン時に uid ごとに
      // 再確認するだけ(別アカウントなら必ず Consent/Tutorial を通す)。
      _tutorialDone = null;
      _tutorialCheckedUid = null;
      _tutorialCheckInFlightUid = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            _lastSeenUser == null) {
          return const _Splash();
        }

        final streamUser = snapshot.data;
        if (streamUser != null) {
          _signOutDebounce?.cancel();
          _signOutDebounce = null;
          _confirmedSignedOut = false;
          _lastSeenUser = streamUser;
        } else if (_lastSeenUser != null &&
            !_confirmedSignedOut &&
            _signOutDebounce == null) {
          // 一瞬の null かもしれないので、少し待ってから確定させる。
          _signOutDebounce = Timer(_signOutDebounceDuration, () {
            _signOutDebounce = null;
            if (mounted) setState(() => _confirmedSignedOut = true);
          });
        }

        final user = _confirmedSignedOut ? null : (streamUser ?? _lastSeenUser);
        if (user == null) {
          // サインアウト直後に古いプロフィールが残らないようにする。
          if (_profileLoaded != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _profile = null;
                  _profileLoaded = null;
                  _lastUid = null;
                });
              }
            });
          }
          return const LoginScreen();
        }

        if (_profileLoaded != true) {
          _loadProfile(user);
          return const _Splash();
        }

        final error = _error;
        if (error != null) {
          return _ErrorScreen(
            message: error,
            onRetry: () {
              setState(() {
                _profileLoaded = null;
                _lastUid = null;
              });
            },
            onSignOut: _signOut,
          );
        }

        // 同意/権限(Consent)より前に Google 由来のプロフィール情報を
        // 送らない。チュートリアル未完了(=初回フロー中)なら、プロフィール
        // の有無に関わらずまず Consent → Tutorial を通し、自動作成は
        // Consent の「次へ」が押された後に行う([_FirstRunFlow] 参照)。
        //
        // 完了状態は uid ごとに保存しているので、uid が変わった
        // (別アカウントでログインした)場合は必ず確認し直す。
        if (_tutorialCheckedUid != user.uid) {
          _checkTutorial(user.uid);
          return const _Splash();
        }
        if (_tutorialDone != true) {
          return _FirstRunFlow(
            hasProfile: _profile != null,
            autoCreateProfile: () => _autoCreateProfile(user),
            onDone: () async {
              await TutorialCompletion.markCompleted(user.uid);
              if (mounted) setState(() => _tutorialDone = true);
            },
          );
        }

        final profile = _profile;
        if (profile == null) {
          // 通常はここに来ない(初回フローの Consent 後に作成済みのはず)。
          // 別端末で初回チュートリアルだけ既完了扱いになっている等の
          // 想定外に備えたフォールバック。
          _autoCreateProfile(user);
          return const _Splash();
        }

        return MainShell(
          api: widget.api,
          profile: profile,
          onProfileChanged: (saved) => setState(() => _profile = saved),
          onSignOut: _signOut,
          themeController: widget.themeController,
          settingsStore: widget.settingsStore,
        );
      },
    );
  }
}

/// 初回フロー: 同意・権限セットアップ(1画面) → チュートリアル(3ページ)。
/// どちらも単体の画面として作ってあり、ここは順序を決めるだけの薄い層。
///
/// プロフィールの自動作成(Google の表示名・アイコンを保存する)は、
/// 利用規約・プライバシーポリシーへの同意を意味する Consent の「次へ」が
/// 押された**後**にだけ行う。強制的な入力画面は挟まず、作成中は簡潔な
/// ローディングだけを見せる。
class _FirstRunFlow extends StatefulWidget {
  const _FirstRunFlow({
    required this.hasProfile,
    required this.autoCreateProfile,
    required this.onDone,
  });

  final bool hasProfile;
  final Future<void> Function() autoCreateProfile;
  final VoidCallback onDone;

  @override
  State<_FirstRunFlow> createState() => _FirstRunFlowState();
}

class _FirstRunFlowState extends State<_FirstRunFlow> {
  bool _consentDone = false;
  bool _creatingProfile = false;

  Future<void> _onConsentNext() async {
    if (widget.hasProfile) {
      setState(() => _consentDone = true);
      return;
    }
    setState(() => _creatingProfile = true);
    await widget.autoCreateProfile();
    // 失敗時は呼び出し元(AuthGate)が _error をセットして
    // 別画面(エラー/再試行)に差し替えるので、ここでは自分の状態だけ戻す。
    if (!mounted) return;
    setState(() {
      _creatingProfile = false;
      _consentDone = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_creatingProfile) return const _Splash();
    if (!_consentDone) {
      return ConsentPermissionScreen(onNext: _onConsentNext);
    }
    return TutorialScreen(onFinished: widget.onDone);
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.surface,
      body: Center(
        child: CircularProgressIndicator(color: colors.primaryContainer),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                style: BloomText.bodySm.copyWith(color: colors.secondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: BloomSpace.md),
              TextButton(
                onPressed: onRetry,
                child: Text(
                  '再試行',
                  style: BloomText.labelMd.copyWith(color: colors.primary),
                ),
              ),
              TextButton(
                onPressed: onSignOut,
                child: Text(
                  'ログアウト',
                  style:
                      BloomText.labelMd.copyWith(color: colors.secondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
