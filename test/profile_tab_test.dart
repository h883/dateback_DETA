import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:sns_novahack/api/bloom_api.dart';
import 'package:sns_novahack/models/models.dart';
import 'package:sns_novahack/proximity/proximity_service.dart';
import 'package:sns_novahack/screens/tabs/profile_tab.dart';
import 'package:sns_novahack/theme/bloom_theme.dart';

/// ネットワーク/Firebase に触れずに ProfileTab を検証するためのテスト用 API。
///
/// [fetchMyPosts] / [fetchFriends] だけ固定値を返すよう差し替える。
/// [mediaHeaders] も本物の FirebaseAuth を呼ばないよう上書きする
/// (RemoteAvatar/PostMedia が使う)。
class _FakeApi extends BloomApi {
  _FakeApi({required this.posts, required this.friends})
      : super(baseUrl: 'https://example.invalid', client: http.Client());

  final List<Post> posts;
  final List<Friend> friends;

  @override
  Future<List<Post>> fetchMyPosts() async => posts;

  @override
  Future<List<Friend>> fetchFriends() async => friends;

  @override
  Future<Map<String, String>> mediaHeaders() async => const {};
}

Profile _profile() =>
    const Profile(uid: 'u1', username: 'ゆい', bio: '', avatarPath: null);

Post _post(String id) => Post(
      id: id,
      authorUid: 'u1',
      authorName: 'ゆい',
      kind: PostKind.film35mm,
      mediaPath: '/api/media/posts/$id',
      createdAt: DateTime(2026, 9, 18),
      liked: false,
      likeCount: 0,
    );

Widget _app(BloomApi api, {VoidCallback? onOpenSettings}) => MaterialApp(
      theme: buildBloomTheme(),
      home: Scaffold(
        body: ProfileTab(
          api: api,
          profile: _profile(),
          onProfileChanged: (_) {},
          onToast: (_) {},
          proximity: FakeProximityService(),
          onOpenSettings: onOpenSettings ?? () {},
        ),
      ),
    );

void main() {
  testWidgets('投稿3件のとき「投稿 3」と表示する', (tester) async {
    final api = _FakeApi(
      posts: [_post('a'), _post('b'), _post('c')],
      friends: const [],
    );
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('投稿 3'), findsOneWidget);
  });

  testWidgets('投稿0件のとき「投稿 0」と表示する（架空の値ではない）', (tester) async {
    final api = _FakeApi(posts: const [], friends: const []);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('投稿 0'), findsOneWidget);
    expect(find.text('まだ投稿がありません'), findsOneWidget);
  });

  testWidgets('フレンド数が stats に表示される', (tester) async {
    final api = _FakeApi(
      posts: const [],
      friends: [
        Friend(profile: const Profile(uid: 'f1', username: 'A', bio: '')),
        Friend(profile: const Profile(uid: 'f2', username: 'B', bio: '')),
      ],
    );
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('フレンド 2'), findsOneWidget);
  });

  testWidgets('Profile本文に「ログアウト」の文言が存在しない', (tester) async {
    final api = _FakeApi(posts: const [], friends: const []);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('ログアウト'), findsNothing);
  });

  testWidgets('ハンバーガーをタップすると onOpenSettings が呼ばれる（Logoutの入口はSettings側）',
      (tester) async {
    var opened = false;
    final api = _FakeApi(posts: const [], friends: const []);
    await tester.pumpWidget(_app(api, onOpenSettings: () => opened = true));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('フレンドstatをタップするとFriends導線(FriendsScreen)が開く', (tester) async {
    final api = _FakeApi(posts: const [], friends: const []);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('フレンド 0'));
    await tester.pumpAndSettle();

    // FriendsScreen 側のタイトル文言まで検証すると密結合になるので、
    // ここでは ProfileTab が画面遷移した(=元の画面が見えなくなった)ことだけ確認する。
    expect(find.byType(ProfileTab), findsNothing);
  });
}
