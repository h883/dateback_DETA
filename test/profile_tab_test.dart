import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sns_novahack/proximity/proximity_service.dart';
import 'package:sns_novahack/screens/tabs/profile_tab.dart';

import 'support/fake_bloom_api.dart';
import 'support/test_app.dart';

/// Own Profile (ProfileTab) の回帰テスト。
///
/// v15 で「フレンド N人」の行ボタン + 本文内ログアウト行のレイアウトから、
/// 「投稿 N」「フレンド N」を横並びにした stats 行(ログアウトは Settings
/// ドロワーのみ)へ変更された(origin/main コミット e58b417)。
/// このテストは v15 マージ後の実装を回帰基準として固定する。
void main() {
  setUp(useTallTestSurface);

  Widget buildTab(FakeBloomApi api, {VoidCallback? onOpenSettings}) {
    return wrapWithApp(
      ProfileTab(
        api: api,
        profile: buildProfile(uid: 'me', username: '自分', bio: '自己紹介文'),
        onProfileChanged: (_) {},
        onToast: (_) {},
        proximity: FakeProximityService(),
        onOpenSettings: onOpenSettings ?? () {},
      ),
    );
  }

  group('Own Profile stats', () {
    testWidgets('投稿0件・フレンド0人のとき「投稿 0」「フレンド 0」と表示する(架空の値ではない)',
        (tester) async {
      final api = FakeBloomApi()
        ..myPosts = const []
        ..friends = const [];

      await tester.pumpWidget(buildTab(api));
      await tester.pumpAndSettle();

      expect(find.text('投稿 0'), findsOneWidget);
      expect(find.text('フレンド 0'), findsOneWidget);
    });

    testWidgets('投稿3件・フレンド2人のとき件数どおりに表示する', (tester) async {
      final api = FakeBloomApi()
        ..myPosts = [
          buildPost(id: 'p1'),
          buildPost(id: 'p2'),
          buildPost(id: 'p3'),
        ]
        ..friends = [buildFriend(uid: 'f1'), buildFriend(uid: 'f2')];

      await tester.pumpWidget(buildTab(api));
      await tester.pumpAndSettle();

      expect(find.text('投稿 3'), findsOneWidget);
      expect(find.text('フレンド 2'), findsOneWidget);
    });
  });

  group('Own Profile posts grid', () {
    testWidgets('own post 0件のとき空表示になる', (tester) async {
      final api = FakeBloomApi()
        ..myPosts = const []
        ..friends = const [];

      await tester.pumpWidget(buildTab(api));
      await tester.pumpAndSettle();

      expect(find.text('まだ投稿がありません'), findsOneWidget);
    });

    testWidgets('own post 3件のとき3枚グリッド表示される', (tester) async {
      final api = FakeBloomApi()
        ..myPosts = [
          buildPost(id: 'p1'),
          buildPost(id: 'p2'),
          buildPost(id: 'p3'),
        ]
        ..friends = const [];

      await tester.pumpWidget(buildTab(api));
      await tester.pumpAndSettle();

      expect(find.text('まだ投稿がありません'), findsNothing);
      // GridView.builder は itemCount:3 を渡している。GridTile 相当の
      // タップ領域(GestureDetector)が3つ生成されていることで枚数を確認する。
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect(grid.childrenDelegate.estimatedChildCount, 3);
    });

    testWidgets('投稿grid tap で Own Post Viewer が開く', (tester) async {
      final api = FakeBloomApi()
        ..myPosts = [buildPost(id: 'p1')]
        ..friends = const [];

      await tester.pumpWidget(buildTab(api));
      await tester.pumpAndSettle();

      // グリッドの1枚目をタップ。
      final tile = find
          .descendant(
            of: find.byType(GridView),
            matching: find.byType(GestureDetector),
          )
          .first;
      await tester.tap(tile);
      await tester.pumpAndSettle();

      // Post Viewer は「縦スワイプで投稿移動」ヘッダーを持つ。
      expect(find.text('縦スワイプで投稿移動'), findsOneWidget);
    });
  });

  group('Own Profile navigation', () {
    testWidgets('フレンドstatタップで Friends 一覧へ進める', (tester) async {
      final api = FakeBloomApi()
        ..myPosts = const []
        ..friends = [buildFriend(uid: 'f1', username: 'とも1')];

      await tester.pumpWidget(buildTab(api));
      await tester.pumpAndSettle();

      await tester.tap(find.text('フレンド 1'));
      await tester.pumpAndSettle();

      expect(find.text('フレンド'), findsWidgets); // FriendsScreen のタイトル
      expect(find.text('とも1'), findsOneWidget);
    });

    testWidgets('投稿statはタップしても遷移しない(タップ不可)', (tester) async {
      final api = FakeBloomApi()
        ..myPosts = [buildPost(id: 'p1')]
        ..friends = const [];

      await tester.pumpWidget(buildTab(api));
      await tester.pumpAndSettle();

      await tester.tap(find.text('投稿 1'));
      await tester.pumpAndSettle();

      // 画面遷移していないことを ProfileTab が残っていることで確認する。
      expect(find.byType(ProfileTab), findsOneWidget);
    });

    testWidgets('ハンバーガーをタップすると onOpenSettings が呼ばれる(Logoutの入口はSettings側)',
        (tester) async {
      var opened = false;
      final api = FakeBloomApi()
        ..myPosts = const []
        ..friends = const [];

      await tester.pumpWidget(buildTab(api, onOpenSettings: () => opened = true));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pump();

      expect(opened, isTrue);
    });
  });

  group('Own Profile error handling', () {
    testWidgets('プロフィールAPIエラー時にエラー表示と再試行を出す', (tester) async {
      final api = FakeBloomApi()
        ..myPostsError = Exception('network down')
        ..friendsError = Exception('network down');

      await tester.pumpWidget(buildTab(api));
      await tester.pumpAndSettle();

      expect(find.text('読み込めませんでした'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
    });

    testWidgets('エラー中は stats がプレースホルダ「—」になる(架空の0を出さない)', (tester) async {
      final api = FakeBloomApi()
        ..myPostsError = Exception('network down')
        ..friendsError = Exception('network down');

      await tester.pumpWidget(buildTab(api));
      await tester.pumpAndSettle();

      expect(find.text('投稿 —'), findsOneWidget);
      expect(find.text('フレンド —'), findsOneWidget);
      expect(find.text('投稿 0'), findsNothing);
      expect(find.text('フレンド 0'), findsNothing);
    });

    testWidgets('再試行タップで再読み込みされ、成功すれば投稿が表示される', (tester) async {
      final api = FakeBloomApi()
        ..myPostsError = Exception('network down')
        ..friendsError = Exception('network down');

      await tester.pumpWidget(buildTab(api));
      await tester.pumpAndSettle();
      expect(find.text('再試行'), findsOneWidget);

      // 次の読み込みは成功させる。
      api.myPostsError = null;
      api.friendsError = null;
      api.myPosts = [buildPost(id: 'p1')];

      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();

      expect(find.text('読み込めませんでした'), findsNothing);
      expect(find.byType(GridView), findsOneWidget);
      expect(find.text('投稿 1'), findsOneWidget);
    });
  });

  group('Own Profile logout affordance', () {
    testWidgets('本文に「ログアウト」の文言は存在しない(v15: Settingsドロワーのみに移動)',
        (tester) async {
      final api = FakeBloomApi()
        ..myPosts = const []
        ..friends = const [];

      await tester.pumpWidget(buildTab(api));
      await tester.pumpAndSettle();

      expect(find.text('ログアウト'), findsNothing);
    });
  });
}
