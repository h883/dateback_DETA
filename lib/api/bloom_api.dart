import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Cloudflare Workers 上の本SNS API を叩くクライアント。
///
/// 閲覧可否の判定はサーバー側で完結している（仕様書 4.4）ので、
/// ここでは投稿時刻と閲覧可能時刻を突き合わせない。返ってきた投稿は
/// すべて「今このユーザーが見てよい投稿」である。
class BloomApi {
  BloomApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// 例: `https://bloom-api.<subdomain>.workers.dev`
  final String baseUrl;
  final http.Client _client;

  /// `wrangler deploy` 後に出る URL をここに入れる。
  /// --dart-define=BLOOM_API_BASE_URL=... でも上書きできる。
  static const defaultBaseUrl = String.fromEnvironment(
    'BLOOM_API_BASE_URL',
    defaultValue: 'https://bloom-api.example.workers.dev',
  );

  Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const BloomApiException('unauthenticated', 'ログインが必要です');
    final token = await user.getIdToken();
    return {'authorization': 'Bearer $token'};
  }

  /// 画像・動画を読むときに `Image.network` などへ渡すヘッダ。
  Future<Map<String, String>> mediaHeaders() => _authHeaders();

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// メディアの相対パスを絶対 URL にする。
  String mediaUrl(String path) => '$baseUrl$path';

  Never _throw(http.Response res) {
    String code = 'http_${res.statusCode}';
    String message = res.body;
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final error = body['error'] as Map<String, dynamic>?;
      if (error != null) {
        code = error['code'] as String? ?? code;
        message = error['message'] as String? ?? message;
      }
    } catch (_) {
      // JSON でないときは本文をそのまま使う。
    }
    throw BloomApiException(code, message);
  }

  Future<Map<String, dynamic>> _json(http.Response res) {
    if (res.statusCode >= 400) _throw(res);
    return Future.value(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  // ------------------------------------------------------------ プロフィール

  /// 自分のプロフィール。未設定なら null（設定画面へ送る合図）。
  Future<Profile?> fetchMyProfile() async {
    final res = await _client.get(_uri('/api/me'), headers: await _authHeaders());
    if (res.statusCode == 404) return null;
    return Profile.fromJson(await _json(res));
  }

  Future<Profile> saveMyProfile({
    required String username,
    required String bio,
  }) async {
    final res = await _client.put(
      _uri('/api/me'),
      headers: {...await _authHeaders(), 'content-type': 'application/json'},
      body: jsonEncode({'username': username, 'bio': bio}),
    );
    return Profile.fromJson(await _json(res));
  }

  Future<Profile> uploadAvatar(Uint8List bytes, String contentType) async {
    final res = await _client.put(
      _uri('/api/me/avatar'),
      headers: {...await _authHeaders(), 'content-type': contentType},
      body: bytes,
    );
    return Profile.fromJson(await _json(res));
  }

  /// 他ユーザーのプロフィール(uid/username/avatarPath/bio。beaconId 等の
  /// 内部情報は含まれない)。面識のない相手には `not_visible`(403)が返る
  /// (`canViewProfile` による既存の可視性制御をそのまま利用)。
  Future<Profile> fetchUserProfile(String uid) async {
    final res = await _client.get(
      _uri('/api/users/$uid'),
      headers: await _authHeaders(),
    );
    return Profile.fromJson(await _json(res));
  }

  // ------------------------------------------------------------ 投稿

  /// 撮影したメディアを投稿する。投稿時刻はサーバーが決める。
  ///
  /// [locationLabel] は撮影地(粗いエリア名、B2)。設定でOFFのとき・
  /// 位置取得に失敗したときは null のまま渡せばよい(その場合ヘッダー
  /// 自体を送らない)。緯度経度はここでは扱わない。
  Future<void> createPost({
    required Uint8List bytes,
    required PostKind kind,
    required String contentType,
    String? locationLabel,
  }) async {
    final res = await _client.post(
      _uri('/api/posts'),
      headers: {
        ...await _authHeaders(),
        'content-type': contentType,
        'x-post-kind': kind.wire,
        if (locationLabel != null && locationLabel.isNotEmpty)
          'x-location-label': Uri.encodeComponent(locationLabel),
      },
      body: bytes,
    );
    if (res.statusCode >= 400) _throw(res);
  }

  /// 自分の投稿。自分のものは常に全部見える。
  Future<List<Post>> fetchMyPosts() async {
    final res =
        await _client.get(_uri('/api/posts/mine'), headers: await _authHeaders());
    final body = await _json(res);
    return (body['posts'] as List)
        .map((e) => Post.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// ホーム画面のフィード。投稿者ごとにまとまって返る。
  Future<List<AuthorFeed>> fetchFeed() async {
    final res = await _client.get(_uri('/api/feed'), headers: await _authHeaders());
    final body = await _json(res);
    return (body['authors'] as List)
        .map((e) => AuthorFeed.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> setLiked(String postId, bool liked) async {
    final uri = _uri('/api/posts/$postId/like');
    final headers = await _authHeaders();
    final res = liked
        ? await _client.post(uri, headers: headers)
        : await _client.delete(uri, headers: headers);
    if (res.statusCode >= 400) _throw(res);
  }

  /// この投稿にいいねしたユーザー一覧(B1)。
  ///
  /// この投稿を閲覧できる場合だけサーバーが返す。件数(♥ N)は既存の
  /// [Post.likeCount] にすでに含まれているので、これは一覧を開いた
  /// ときだけ叩く(投稿一覧取得時にまとめて先読みしない)。
  Future<List<Profile>> fetchLikers(String postId) async {
    final res = await _client.get(
      _uri('/api/posts/$postId/likers'),
      headers: await _authHeaders(),
    );
    final body = await _json(res);
    return (body['likers'] as List)
        .map((e) => Profile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 他ユーザーの、今の自分から閲覧可能な投稿一覧。
  ///
  /// 近距離イベント成立の前後でこれを比較し、新しく増えた投稿があるかを
  /// クライアント側で判定するために使う（既存の `GET /api/users/:uid/posts`
  /// をそのまま叩くだけで、バックエンドは変更していない）。
  Future<List<Post>> fetchUserPosts(String uid) async {
    final res = await _client.get(
      _uri('/api/users/$uid/posts'),
      headers: await _authHeaders(),
    );
    final body = await _json(res);
    return (body['posts'] as List)
        .map((e) => Post.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ------------------------------------------------------------ フレンド

  Future<List<Friend>> fetchFriends() async {
    final res = await _client.get(_uri('/api/friends'), headers: await _authHeaders());
    final body = await _json(res);
    return (body['friends'] as List)
        .map((e) => Friend.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 成立済みのフレンド関係を解除する。pending 申請の取消/却下には
  /// [cancelFriendRequest] を使う(こちらとは別の API)。
  /// フレンドでない相手を指定すると `not_found`(404)。
  Future<void> removeFriend(String uid) async {
    final res = await _client.delete(
      _uri('/api/friends/$uid'),
      headers: await _authHeaders(),
    );
    if (res.statusCode >= 400) _throw(res);
  }

  Future<FriendRequests> fetchFriendRequests() async {
    final res = await _client.get(
      _uri('/api/friends/requests'),
      headers: await _authHeaders(),
    );
    return FriendRequests.fromJson(await _json(res));
  }

  /// 申請を送る。相手から先に申請が来ていればその場で成立する。
  Future<String> requestFriend(String uid) async {
    final res = await _client.post(
      _uri('/api/friends/requests'),
      headers: {...await _authHeaders(), 'content-type': 'application/json'},
      body: jsonEncode({'uid': uid}),
    );
    final body = await _json(res);
    return body['status'] as String;
  }

  Future<void> acceptFriend(String uid) async {
    final res = await _client.post(
      _uri('/api/friends/requests/$uid/accept'),
      headers: await _authHeaders(),
    );
    if (res.statusCode >= 400) _throw(res);
  }

  Future<void> cancelFriendRequest(String uid) async {
    final res = await _client.delete(
      _uri('/api/friends/requests/$uid'),
      headers: await _authHeaders(),
    );
    if (res.statusCode >= 400) _throw(res);
  }

  // ------------------------------------------------------------ 通知

  Future<NotificationFeed> fetchNotifications() async {
    final res = await _client.get(
      _uri('/api/notifications'),
      headers: await _authHeaders(),
    );
    return NotificationFeed.fromJson(await _json(res));
  }

  /// 既読にする。[ids] を省略すると全件。
  Future<void> markNotificationsRead([List<String>? ids]) async {
    final res = await _client.post(
      _uri('/api/notifications/read'),
      headers: {...await _authHeaders(), 'content-type': 'application/json'},
      body: jsonEncode({'ids': ?ids}),
    );
    if (res.statusCode >= 400) _throw(res);
  }

  // ------------------------------------------------------------ 近距離イベント

  /// BLE で拾った beaconId をユーザーに解決する。
  ///
  /// [discover] が true のときだけ非フレンドも返る（仕様書 6.4 / 7.2）。
  Future<ResolvedPeers> resolveBeacons(
    List<String> beaconIds, {
    bool discover = false,
  }) async {
    final res = await _client.post(
      _uri('/api/proximity/resolve'),
      headers: {...await _authHeaders(), 'content-type': 'application/json'},
      body: jsonEncode({
        'beaconIds': beaconIds,
        if (discover) 'mode': 'discover',
      }),
    );
    return ResolvedPeers.fromJson(await _json(res));
  }

  /// フレンドを近距離で見つけたときに呼ぶ。双方の閲覧可能時刻が「今」に更新される。
  /// 同じ相手と続けて呼んでも、サーバー側のクールダウンで交換は繰り返されない。
  ///
  /// [peerUid] と [beaconId] はどちらか一方を渡す。
  Future<ProximityResult> reportProximity({
    String? peerUid,
    String? beaconId,
  }) async {
    assert(peerUid != null || beaconId != null);
    final res = await _client.post(
      _uri('/api/proximity'),
      headers: {...await _authHeaders(), 'content-type': 'application/json'},
      body: jsonEncode({
        'peerUid': ?peerUid,
        'beaconId': ?beaconId,
      }),
    );
    return ProximityResult.fromJson(await _json(res));
  }

  void dispose() => _client.close();
}

class BloomApiException implements Exception {
  const BloomApiException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'BloomApiException($code): $message';
}
