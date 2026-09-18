import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sns_novahack/proximity/proximity_service.dart';
import 'package:sns_novahack/screens/friends_screen.dart';

import 'support/fake_bloom_api.dart';
import 'support/test_app.dart';

/// FriendsScreen の回帰テスト(タスク仕様 5)。
void main() {
  Widget buildScreen(FakeBloomApi api, {ProximityService? proximity}) {
    return wrapWithApp(
      FriendsScreen(
        api: api,
        proximity: proximity ?? FakeProximityService(),
        onToast: (_) {},
      ),
    );
  }

  testWidgets('friend一覧に avatar と username が表示される', (tester) async {
    final api = FakeBloomApi()
      ..friends = [
        buildFriend(uid: 'f1', username: 'ひかり'),
        buildFriend(uid: 'f2', username: 'そら'),
      ];

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    expect(find.text('ひかり'), findsOneWidget);
    expect(find.text('そら'), findsOneWidget);
  });

  testWidgets('0人のとき空状態が出る', (tester) async {
    final api = FakeBloomApi()..friends = const [];

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    expect(find.text('まだフレンドがいません'), findsOneWidget);
  });

  testWidgets('row tap で OtherProfile へ遷移する', (tester) async {
    final api = FakeBloomApi()
      ..friends = [buildFriend(uid: 'f1', username: 'ひかり')]
      ..userProfiles['f1'] = buildProfile(uid: 'f1', username: 'ひかり')
      ..userPosts['f1'] = const [];

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ひかり'));
    await tester.pumpAndSettle();

    // OtherProfileScreen 側の投稿数表示が出ていれば遷移できている。
    expect(find.text('投稿 0件'), findsOneWidget);
  });

  testWidgets('+ ボタンで Friend Add シートが開く', (tester) async {
    final api = FakeBloomApi()..friends = const [];

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_add_alt_1_outlined).first);
    await tester.pumpAndSettle();

    expect(find.text('近くの人を探す'), findsWidgets);
  });

  testWidgets('APIエラー時にトーストで伝え、画面はクラッシュしない', (tester) async {
    final api = FakeBloomApi()..friendsError = Exception('boom');
    String? toast;

    await tester.pumpWidget(
      wrapWithApp(
        FriendsScreen(
          api: api,
          proximity: FakeProximityService(),
          onToast: (m) => toast = m,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(toast, '読み込めませんでした');
    expect(find.text('まだフレンドがいません'), findsOneWidget);
  });
}
