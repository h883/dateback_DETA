import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sns_novahack/screens/other_profile_screen.dart';

import 'support/fake_bloom_api.dart';
import 'support/test_app.dart';

/// OtherProfileScreen の回帰テスト(タスク仕様 4)。
///
/// 表示対象の投稿は常に fetchUserPosts が返したものだけを使うという
/// 既存仕様どおり、ここでは visible_until 等の独自判定は一切テストしない
/// (フェイク API がそのまま返す投稿一覧を検証するだけ)。
void main() {
  Widget buildScreen(FakeBloomApi api, {String uid = 'other1'}) {
    return wrapWithApp(
      OtherProfileScreen(api: api, uid: uid, onToast: (_) {}),
    );
  }

  testWidgets('avatar / username / bio / 投稿grid / post tap で Post Viewer が開く',
      (tester) async {
    final api = FakeBloomApi()
      ..userProfiles['other1'] =
          buildProfile(uid: 'other1', username: 'まこと', bio: '写真好き')
      ..userPosts['other1'] = [buildPost(id: 'op1', authorUid: 'other1')]
      ..friends = const [];

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    expect(find.text('まこと'), findsOneWidget);
    expect(find.text('写真好き'), findsOneWidget);
    expect(find.text('投稿 1件'), findsOneWidget);

    final tile = find
        .descendant(
          of: find.byType(GridView),
          matching: find.byType(GestureDetector),
        )
        .first;
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.text('縦スワイプで投稿移動'), findsOneWidget);
  });

  testWidgets('見られる投稿が0件のとき空表示になる', (tester) async {
    final api = FakeBloomApi()
      ..userProfiles['other1'] = buildProfile(uid: 'other1', username: 'まこと')
      ..userPosts['other1'] = const []
      ..friends = const [];

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    expect(find.text('まだ見られる投稿がありません'), findsOneWidget);
  });

  testWidgets('他人のプロフィールには編集・設定・ログアウト導線が出ない', (tester) async {
    final api = FakeBloomApi()
      ..userProfiles['other1'] = buildProfile(uid: 'other1', username: 'まこと')
      ..userPosts['other1'] = const []
      ..friends = const [];

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.text('ログアウト'), findsNothing);
    expect(find.text('設定'), findsNothing);
  });

  testWidgets('フレンドのときだけフレンド解除導線が出て、確認・成功で前画面に戻る',
      (tester) async {
    final api = FakeBloomApi()
      ..userProfiles['other1'] = buildProfile(uid: 'other1', username: 'まこと')
      ..userPosts['other1'] = const []
      ..friends = [buildFriend(uid: 'other1', username: 'まこと')];

    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => OtherProfileScreen(
                      api: api,
                      uid: 'other1',
                      onToast: (_) {},
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('フレンド解除'), findsOneWidget);
    await tester.tap(find.text('フレンド解除'));
    await tester.pumpAndSettle();

    expect(find.text('フレンドを解除しますか?'), findsOneWidget);
    await tester.tap(find.text('解除する'));
    await tester.pumpAndSettle();

    expect(api.removeFriendCalls, ['other1']);
    // ダイアログ+画面が両方閉じ、呼び出し元の 'open' ボタンへ戻っている。
    expect(find.text('open'), findsOneWidget);
    expect(find.text('フレンド解除'), findsNothing);
  });

  testWidgets('非フレンドにはフレンド解除導線が出ない', (tester) async {
    final api = FakeBloomApi()
      ..userProfiles['other1'] = buildProfile(uid: 'other1', username: 'まこと')
      ..userPosts['other1'] = const []
      ..friends = const [];

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    expect(find.text('フレンド解除'), findsNothing);
  });

  testWidgets('プロフィールAPIエラー時にエラー表示と再試行を出す', (tester) async {
    final api = FakeBloomApi()..userProfileError = Exception('boom');

    await tester.pumpWidget(buildScreen(api));
    await tester.pumpAndSettle();

    expect(find.text('読み込めませんでした'), findsOneWidget);
    expect(find.text('再試行'), findsOneWidget);
  });
}
