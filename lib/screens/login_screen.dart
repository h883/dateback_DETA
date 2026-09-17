import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../theme/bloom_theme.dart';
import '../widgets/google_logo.dart';
import '../widgets/wordmark.dart';

/// ログイン画面(v15 / Quiet Analog)。
///
/// Google 認証のロジックは既存のまま変更していない。Apple は最終仕様では
/// 両対応予定だが、バックエンドが Google のみのため今回は見た目だけ用意し、
/// 動作しない機能を完成済みに見せないよう「近日対応」で応答する。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  Future<void> _signInWithGoogle() async {
    // 非同期の合間に context を跨がないよう、先に握っておく。
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    var dialogShown = false;

    // 「認証連携中」ダイアログは自分では閉じない。開いた側が必ず閉じる。
    void closeDialog() {
      if (!dialogShown) return;
      dialogShown = false;
      if (navigator.mounted) navigator.pop();
    }

    try {
      // アカウント選択(Google のネイティブピッカー)。
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        // キャンセル。無反応だと固まったように見えるので必ず知らせる。
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('ログインをキャンセルしました')),
          );
        }
        return;
      }
      if (!mounted) return;

      dialogShown = true;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          // closeDialog の navigator と同じものに積むため root は使わない。
          useRootNavigator: false,
          barrierColor: context.colors.scrim.withValues(alpha: 0.6),
          builder: (_) => const _ConnectingDialog(
            message: 'Googleアカウントで安全にログインしています...',
          ),
        ),
      );

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);

      closeDialog();
      if (!mounted) return;
      // 行き先は AuthGate が決める。
      navigator.popUntil((route) => route.isFirst);
    } catch (e) {
      closeDialog();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('ログインに失敗しました: $e')),
        );
      }
    }
  }

  void _appleComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Appleでのログインは近日対応します')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: 1.5,
                    child: const Wordmark(),
                  ),
                  const SizedBox(height: 44),
                  _AuthButton(
                    label: 'Googleで続ける',
                    icon: const GoogleLogo(size: 20),
                    onTap: _signInWithGoogle,
                  ),
                  const SizedBox(height: 10),
                  _AuthButton(
                    label: 'Appleで続ける',
                    icon: Icon(Icons.apple, size: 22, color: colors.onSurface),
                    onTap: _appleComingSoon,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Google または Apple でログイン',
                    style: BloomText.labelSm.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  const _AuthButton({required this.label, required this.icon, required this.onTap});

  final String label;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 10),
              Text(
                label,
                style: BloomText.labelLg.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 認証連携中のモーダル。
/// 自分では閉じない。閉じるのは表示した側(_signInWithGoogle)の責務。
class _ConnectingDialog extends StatelessWidget {
  const _ConnectingDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BloomRadius.lg),
      ),
      insetPadding: const EdgeInsets.all(BloomSpace.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(BloomSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '認証連携中',
                style: BloomText.headlineSm.copyWith(color: colors.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                style: BloomText.bodySm.copyWith(color: colors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
