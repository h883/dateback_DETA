import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sns_novahack/screens/post_viewer_screen.dart';

import 'support/fake_bloom_api.dart';
import 'support/test_app.dart';

/// Own Post Viewer の Like / Likers 回帰テスト(タスク仕様 6)。
void main() {
  setUp(useTallTestSurface);

  Future<void> openViewer(
    WidgetTester tester,
    FakeBloomApi api,
    List<dynamic> posts, {
    bool isOwn = true,
  }) async {
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showPostViewer(
                  context,
                  api: api,
                  posts: posts.cast(),
                  initialIndex: 0,
                  onToast: (_) {},
                  isOwn: isOwn,
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
  }

  testWidgets('♥ N は Post.likeCount を表示する(0件)', (tester) async {
    final api = FakeBloomApi();
    await openViewer(tester, api, [buildPost(id: 'p1', likeCount: 0)]);

    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('♥ N は Post.likeCount を表示する(複数件)', (tester) async {
    final api = FakeBloomApi();
    await openViewer(tester, api, [buildPost(id: 'p1', likeCount: 7)]);

    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('画面表示時点では likers を取得しない(heart/countタップで初めて取得)',
      (tester) async {
    final api = FakeBloomApi()
      ..likers['p1'] = [buildProfile(uid: 'l1', username: 'いいね太郎')];
    await openViewer(tester, api, [buildPost(id: 'p1', likeCount: 1)]);

    expect(api.fetchLikersCallCount, 0);

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pumpAndSettle();

    expect(api.fetchLikersCallCount, 1);
  });

  testWidgets('heart・count tap で likers sheet に avatar + username が出る',
      (tester) async {
    final api = FakeBloomApi()
      ..likers['p1'] = [buildProfile(uid: 'l1', username: 'いいね太郎')];
    await openViewer(tester, api, [buildPost(id: 'p1', likeCount: 1)]);

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pumpAndSettle();

    expect(find.text('いいねした人'), findsOneWidget);
    expect(find.text('いいね太郎'), findsOneWidget);
  });

  testWidgets('likers sheetのliker row tapでOtherProfileへ遷移する', (tester) async {
    final api = FakeBloomApi()
      ..likers['p1'] = [buildProfile(uid: 'l1', username: 'いいね太郎')]
      ..userProfiles['l1'] = buildProfile(uid: 'l1', username: 'いいね太郎')
      ..userPosts['l1'] = const [];
    await openViewer(tester, api, [buildPost(id: 'p1', likeCount: 1)]);

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pumpAndSettle();

    await tester.tap(find.text('いいね太郎'));
    await tester.pumpAndSettle();

    expect(find.text('投稿 0件'), findsOneWidget);
  });

  testWidgets('likersが0件のとき専用の空表示が出る', (tester) async {
    final api = FakeBloomApi()..likers['p1'] = const [];
    await openViewer(tester, api, [buildPost(id: 'p1', likeCount: 0)]);

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pumpAndSettle();

    expect(find.text('まだいいねがありません'), findsOneWidget);
  });

  testWidgets('他人の投稿ビュー(isOwn:false)では♥表示自体が出ない', (tester) async {
    final api = FakeBloomApi();
    await openViewer(
      tester,
      api,
      [buildPost(id: 'p1', likeCount: 5)],
      isOwn: false,
    );

    expect(find.byIcon(Icons.favorite), findsNothing);
  });
}
