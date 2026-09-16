import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/bloom_theme.dart';

/// ログイン後の仮ホーム画面。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: BloomColors.surface,
      appBar: AppBar(
        backgroundColor: BloomColors.surface,
        title: const Text('Bloom'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ようこそ', style: BloomText.headlineLg),
            const SizedBox(height: 8),
            Text(
              user?.displayName ?? user?.email ?? '',
              style: BloomText.bodySm.copyWith(color: BloomColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
