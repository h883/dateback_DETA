import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sns_novahack/proximity/proximity_service.dart';
import 'package:sns_novahack/screens/notifications_screen.dart';
import 'package:sns_novahack/screens/tabs/profile_tab.dart';

import 'support/fake_bloom_api.dart';
import 'support/test_app.dart';

/// 固定 dark テーマ前提にしないための smoke test(タスク仕様 10)。
/// 代表的な2画面だけを Light / Dark 双方で build し、例外が出ないことを
/// 確認する(大量の golden test は作らない)。
void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('ProfileTab は $brightness でも例外なくbuildできる', (tester) async {
      final api = FakeBloomApi()
        ..myPosts = [buildPost(id: 'p1')]
        ..friends = [buildFriend(uid: 'f1')];

      await tester.pumpWidget(
        wrapWithApp(
          ProfileTab(
            api: api,
            profile: buildProfile(uid: 'me', username: '自分'),
            onProfileChanged: (_) {},
            onToast: (_) {},
            proximity: FakeProximityService(),
            onOpenSettings: () {},
          ),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('NotificationsScreen は $brightness でも例外なくbuildできる',
        (tester) async {
      final api = FakeBloomApi();

      await tester.pumpWidget(
        wrapWithApp(
          NotificationsScreen(api: api, onRead: () {}),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}
