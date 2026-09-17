import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../api/bloom_api.dart';
import '../models/models.dart';
import '../theme/bloom_theme.dart';
import 'main_shell.dart';
import 'onboarding_screen.dart';
import 'profile_setup_screen.dart';

/// 起動後の行き先を決める。
///
/// 未ログイン           → チュートリアル / ログイン
/// ログイン済・未設定   → プロフィール設定
/// ログイン済・設定済み → 本体（4画面）
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.api});

  final BloomApi api;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Profile? _profile;

  /// null = まだ問い合わせていない。
  bool? _profileLoaded;
  String? _error;
  User? _lastUid;

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

  Future<void> _signOut() async {
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    setState(() {
      _profile = null;
      _profileLoaded = null;
      _lastUid = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _Splash();
        }

        final user = snapshot.data;
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
          return const OnboardingScreen();
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

        final profile = _profile;
        if (profile == null) {
          return ProfileSetupScreen(
            api: widget.api,
            suggestedName: user.displayName,
            suggestedAvatarUrl: user.photoURL,
            onDone: (saved) => setState(() => _profile = saved),
          );
        }

        return MainShell(
          api: widget.api,
          profile: profile,
          onProfileChanged: (saved) => setState(() => _profile = saved),
          onSignOut: _signOut,
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: BloomColors.surface,
      body: Center(
        child: CircularProgressIndicator(color: BloomColors.primaryContainer),
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
    return Scaffold(
      backgroundColor: BloomColors.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                style: BloomText.bodySm.copyWith(color: BloomColors.secondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: BloomSpace.md),
              TextButton(
                onPressed: onRetry,
                child: Text(
                  '再試行',
                  style: BloomText.labelMd.copyWith(color: BloomColors.primary),
                ),
              ),
              TextButton(
                onPressed: onSignOut,
                child: Text(
                  'ログアウト',
                  style:
                      BloomText.labelMd.copyWith(color: BloomColors.secondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
