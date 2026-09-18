import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sns_novahack/models/models.dart';
import 'package:sns_novahack/proximity/proximity_service.dart';
import 'package:sns_novahack/screens/tabs/home_tab.dart';

import 'support/fake_bloom_api.dart';
import 'support/test_app.dart';

void main() {
  setUp(useTallTestSurface);

  Widget buildHome(
    FakeBloomApi api, {
    ProximityService? proximity,
    void Function(String)? onToast,
    void Function(String, int)? onBleSuccess,
    int unread = 0,
  }) {
    return wrapWithApp(
      HomeTab(
        api: api,
        onToast: onToast ?? (_) {},
        proximity: proximity ?? FakeProximityService(scenario: FakeScenario.notFound),
        myBeaconId: 'me-beacon',
        unreadNotifications: unread,
        onOpenNotifications: () {},
        onBleSuccess: onBleSuccess ?? (_, _) {},
      ),
    );
  }

  testWidgets('APIが返した投稿とauthorのavatar/usernameが表示される', (tester) async {
    final api = FakeBloomApi()
      ..feed = [
        AuthorFeed(
          uid: 'a1',
          username: 'あおい',
          posts: [buildPost(id: 'p1', authorUid: 'a1')],
        ),
      ];

    await tester.pumpWidget(buildHome(api));
    await tester.pumpAndSettle();

    expect(find.text('あおい'), findsOneWidget);
  });

  testWidgets('locationLabelがあるとき表示される', (tester) async {
    final api = FakeBloomApi()
      ..feed = [
        AuthorFeed(
          uid: 'a1',
          username: 'あおい',
          posts: [buildPost(id: 'p1', authorUid: 'a1', locationLabel: '大阪市 中央区')],
        ),
      ];

    await tester.pumpWidget(buildHome(api));
    await tester.pumpAndSettle();

    expect(find.text('大阪市 中央区'), findsOneWidget);
  });

  testWidgets('locationLabelがnullのとき不自然な空白/null文字列を出さない', (tester) async {
    final api = FakeBloomApi()
      ..feed = [
        AuthorFeed(
          uid: 'a1',
          username: 'あおい',
          posts: [buildPost(id: 'p1', authorUid: 'a1', locationLabel: null)],
        ),
      ];

    await tester.pumpWidget(buildHome(api));
    await tester.pumpAndSettle();

    expect(find.textContaining('null'), findsNothing);
    expect(find.byIcon(Icons.place_outlined), findsNothing);
  });

  testWidgets('avatar/username tap で OtherProfile へ遷移する', (tester) async {
    final api = FakeBloomApi()
      ..feed = [
        AuthorFeed(
          uid: 'a1',
          username: 'あおい',
          posts: [buildPost(id: 'p1', authorUid: 'a1')],
        ),
      ]
      ..userProfiles['a1'] = buildProfile(uid: 'a1', username: 'あおい')
      ..userPosts['a1'] = const [];

    await tester.pumpWidget(buildHome(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('あおい'));
    await tester.pumpAndSettle();

    expect(find.text('投稿 0件'), findsOneWidget);
  });

  testWidgets('like操作でAPIのsetLikedが呼ばれ、ハートの見た目が変わる', (tester) async {
    final api = FakeBloomApi()
      ..feed = [
        AuthorFeed(
          uid: 'a1',
          username: 'あおい',
          posts: [buildPost(id: 'p1', authorUid: 'a1', liked: false)],
        ),
      ];

    await tester.pumpWidget(buildHome(api));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();

    expect(api.setLikedCalls, ['p1:true']);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  // NOTE(タスク仕様 8): HomeTab の pull-to-search 経由での
  // 「newlyVisibleCount > 0 のときだけ onBleSuccess を呼ぶ」境界も
  // フェイクの ProximityService/BloomApi だけで確認しようとしたが、
  // 縦方向 pull ジェスチャー(GestureDetector の onVerticalDrag*と
  // 手動の _PullPhase 状態遷移が絡む)を widget test の合成ドラッグで
  // 安定して `_searchNearby()` まで到達させられなかった
  // (`tester.drag` では onBleSuccess/onToast どちらも呼ばれず、
  // 原因切り分けに実装変更が必要になりそうだった)。
  // MainShell 側の自動検知(_onPeersFound)経由の境界も、BLE実装
  // (BleProximityService/TiltWatcher)に触れずに再現するには MainShell
  // 自体を widget test で起動する必要があり、これは他メンバーが並行編集中
  // の領域と衝突するリスクがあるため今回は見送った。
  // → 「0件→onBleSuccessなし / 1件以上→onBleSuccessあり」の境界条件
  // 自体は HomeTab._searchNearby / MainShell._onPeersFound のコードを
  // 読んで確認済み(いずれも newCount > 0 のときだけ呼ぶ)だが、
  // 自動テスト化はスキップした。次回、HomeTab に「テスト用に
  // _searchNearby を直接叩けるフック」のような最小限の変更が許容できる
  // なら安定化できる見込み。
}
