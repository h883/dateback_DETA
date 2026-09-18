import 'package:flutter_test/flutter_test.dart';
import 'package:sns_novahack/models/models.dart';
import 'package:sns_novahack/screens/notifications_screen.dart';

import 'support/fake_bloom_api.dart';
import 'support/test_app.dart';

/// Notifications 画面の回帰テスト(タスク仕様 9)。
void main() {
  AppNotification notif({
    required String id,
    required NotificationKind kind,
    bool read = false,
    String? actorUid,
    String? actorName,
  }) =>
      AppNotification(
        id: id,
        kind: kind,
        read: read,
        createdAt: DateTime(2026, 9, 16, 10),
        actorUid: actorUid,
        actorName: actorName,
      );

  testWidgets('friend_request / friend_accepted / proximity / like の各表示が壊れていない',
      (tester) async {
    final api = FakeBloomApi()
      ..notifications = NotificationFeed(
        unreadCount: 0,
        notifications: [
          notif(
            id: 'n1',
            kind: NotificationKind.friendRequest,
            actorUid: 'u1',
            actorName: 'りく',
          ),
          notif(id: 'n2', kind: NotificationKind.friendAccepted, actorName: 'みお'),
          notif(id: 'n3', kind: NotificationKind.proximity, actorName: 'かい'),
          notif(id: 'n4', kind: NotificationKind.like, actorName: 'ゆず'),
        ],
      );

    await tester.pumpWidget(
      wrapWithApp(NotificationsScreen(api: api, onRead: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('りく さんからフレンド申請が届きました'), findsOneWidget);
    expect(find.text('みお さんとフレンドになりました'), findsOneWidget);
    expect(find.text('かい さんとデータを共有しました'), findsOneWidget);
    expect(find.text('ゆず さんが投稿にいいねしました'), findsOneWidget);
  });

  testWidgets('friend_request通知だけ承認/拒否ボタンが出る', (tester) async {
    final api = FakeBloomApi()
      ..notifications = NotificationFeed(
        unreadCount: 0,
        notifications: [
          notif(id: 'n1', kind: NotificationKind.friendRequest, actorUid: 'u1', actorName: 'りく'),
          notif(id: 'n2', kind: NotificationKind.like, actorName: 'ゆず'),
        ],
      );

    await tester.pumpWidget(
      wrapWithApp(NotificationsScreen(api: api, onRead: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('承認'), findsOneWidget);
    expect(find.text('拒否'), findsOneWidget);
  });

  testWidgets('未読が0件超のとき既読APIを叩き、onReadを呼ぶ', (tester) async {
    final api = FakeBloomApi()
      ..notifications = NotificationFeed(
        unreadCount: 2,
        notifications: [notif(id: 'n1', kind: NotificationKind.like, actorName: 'ゆず')],
      );
    var readCalled = false;

    await tester.pumpWidget(
      wrapWithApp(NotificationsScreen(api: api, onRead: () => readCalled = true)),
    );
    await tester.pumpAndSettle();

    expect(api.markNotificationsReadCallCount, 1);
    expect(readCalled, isTrue);
  });

  testWidgets('未読が0件のときは既読APIを叩かない', (tester) async {
    final api = FakeBloomApi()
      ..notifications = NotificationFeed(
        unreadCount: 0,
        notifications: [notif(id: 'n1', kind: NotificationKind.like, actorName: 'ゆず')],
      );

    await tester.pumpWidget(
      wrapWithApp(NotificationsScreen(api: api, onRead: () {})),
    );
    await tester.pumpAndSettle();

    expect(api.markNotificationsReadCallCount, 0);
  });

  testWidgets('承認タップでacceptFriendが呼ばれ、その通知が一覧から消える', (tester) async {
    final api = FakeBloomApi()
      ..notifications = NotificationFeed(
        unreadCount: 0,
        notifications: [
          notif(id: 'n1', kind: NotificationKind.friendRequest, actorUid: 'u1', actorName: 'りく'),
        ],
      );

    await tester.pumpWidget(
      wrapWithApp(NotificationsScreen(api: api, onRead: () {})),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('承認'));
    await tester.pumpAndSettle();

    expect(api.acceptFriendCalls, ['u1']);
    expect(find.text('りく さんからフレンド申請が届きました'), findsNothing);
  });

  testWidgets('通知が0件のとき空状態を表示する', (tester) async {
    final api = FakeBloomApi()..notifications = NotificationFeed.empty;

    await tester.pumpWidget(
      wrapWithApp(NotificationsScreen(api: api, onRead: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('お知らせはまだありません'), findsOneWidget);
  });

  testWidgets('APIエラー時にエラー表示と再試行を出す', (tester) async {
    final api = FakeBloomApi()..notificationsError = Exception('boom');

    await tester.pumpWidget(
      wrapWithApp(NotificationsScreen(api: api, onRead: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('再試行'), findsOneWidget);
  });
}
