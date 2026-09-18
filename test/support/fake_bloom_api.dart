import 'package:sns_novahack/api/bloom_api.dart';
import 'package:sns_novahack/models/models.dart';

/// SNS/UI の widget test 用フェイク API。
///
/// [BloomApi] は具象クラスだが `_client`(private)以外はすべて素直な
/// public メソッドなので、ここではオーバーライドして固定のレスポンス /
/// 例外を返すだけにする。実際の HTTP・Firebase 認証には一切触れない。
class FakeBloomApi extends BloomApi {
  FakeBloomApi() : super(baseUrl: 'https://fake.test');

  // ---- 呼び出し記録(「叩かれていないこと」を確認するテスト用) ----
  int fetchLikersCallCount = 0;
  int fetchMyPostsCallCount = 0;
  int fetchFriendsCallCount = 0;
  int fetchNotificationsCallCount = 0;
  int markNotificationsReadCallCount = 0;
  final List<String> setLikedCalls = [];
  final List<String> removeFriendCalls = [];
  final List<String> acceptFriendCalls = [];
  final List<String> cancelFriendRequestCalls = [];
  final List<String> requestFriendCalls = [];

  // ---- 差し替え可能なレスポンス ----
  Profile? myProfile;
  Object? myProfileError;

  List<Post> myPosts = const [];
  Object? myPostsError;

  List<Friend> friends = const [];
  Object? friendsError;

  Map<String, Profile> userProfiles = {};
  Object? userProfileError;

  Map<String, List<Post>> userPosts = {};

  List<AuthorFeed> feed = const [];
  Object? feedError;

  Map<String, List<Profile>> likers = {};
  Object? likersError;

  NotificationFeed notifications = NotificationFeed.empty;
  Object? notificationsError;

  Object? removeFriendError;
  Object? setLikedError;
  String requestFriendStatus = 'pending';

  ResolvedPeers resolvedPeers = const ResolvedPeers(friends: [], strangers: []);
  ProximityResult proximityResult = const ProximityResult(exchanged: false);

  @override
  Future<ResolvedPeers> resolveBeacons(
    List<String> beaconIds, {
    bool discover = false,
  }) async =>
      resolvedPeers;

  @override
  Future<ProximityResult> reportProximity({
    String? peerUid,
    String? beaconId,
  }) async =>
      proximityResult;

  @override
  Future<Profile?> fetchMyProfile() async {
    if (myProfileError != null) throw myProfileError!;
    return myProfile;
  }

  @override
  Future<List<Post>> fetchMyPosts() async {
    fetchMyPostsCallCount++;
    if (myPostsError != null) throw myPostsError!;
    return myPosts;
  }

  @override
  Future<List<Friend>> fetchFriends() async {
    fetchFriendsCallCount++;
    if (friendsError != null) throw friendsError!;
    return friends;
  }

  @override
  Future<Profile> fetchUserProfile(String uid) async {
    if (userProfileError != null) throw userProfileError!;
    final p = userProfiles[uid];
    if (p == null) throw const BloomApiException('not_found', 'not found');
    return p;
  }

  @override
  Future<List<Post>> fetchUserPosts(String uid) async {
    return userPosts[uid] ?? const [];
  }

  @override
  Future<List<AuthorFeed>> fetchFeed() async {
    if (feedError != null) throw feedError!;
    return feed;
  }

  @override
  Future<void> setLiked(String postId, bool liked) async {
    setLikedCalls.add('$postId:$liked');
    if (setLikedError != null) throw setLikedError!;
  }

  @override
  Future<List<Profile>> fetchLikers(String postId) async {
    fetchLikersCallCount++;
    if (likersError != null) throw likersError!;
    return likers[postId] ?? const [];
  }

  @override
  Future<void> removeFriend(String uid) async {
    removeFriendCalls.add(uid);
    if (removeFriendError != null) throw removeFriendError!;
  }

  @override
  Future<FriendRequests> fetchFriendRequests() async => FriendRequests.empty;

  @override
  Future<String> requestFriend(String uid) async {
    requestFriendCalls.add(uid);
    return requestFriendStatus;
  }

  @override
  Future<void> acceptFriend(String uid) async {
    acceptFriendCalls.add(uid);
  }

  @override
  Future<void> cancelFriendRequest(String uid) async {
    cancelFriendRequestCalls.add(uid);
  }

  @override
  Future<NotificationFeed> fetchNotifications() async {
    fetchNotificationsCallCount++;
    if (notificationsError != null) throw notificationsError!;
    return notifications;
  }

  @override
  Future<void> markNotificationsRead([List<String>? ids]) async {
    markNotificationsReadCallCount++;
  }

  // メディアは常にプレースホルダに落ちればよいので、これらは呼ばれても
  // 実ネットワークに出ない値にしておく(RemoteImage の errorBuilder が拾う)。
  @override
  Future<Map<String, String>> mediaHeaders() async => const {};

  @override
  String mediaUrl(String path) => 'https://fake.test$path';
}

// ---- テストデータ生成ヘルパー ----

Profile buildProfile({
  String uid = 'u1',
  String username = 'ゆき',
  String bio = '',
  String? avatarPath,
}) =>
    Profile(uid: uid, username: username, bio: bio, avatarPath: avatarPath);

Post buildPost({
  String id = 'p1',
  String authorUid = 'u1',
  String authorName = 'ゆき',
  DateTime? createdAt,
  bool liked = false,
  int likeCount = 0,
  String? locationLabel,
  PostKind kind = PostKind.film35mm,
}) =>
    Post(
      id: id,
      authorUid: authorUid,
      authorName: authorName,
      kind: kind,
      mediaPath: '/api/media/posts/$id',
      createdAt: createdAt ?? DateTime(2026, 9, 16, 12),
      liked: liked,
      likeCount: likeCount,
      locationLabel: locationLabel,
    );

Friend buildFriend({
  String uid = 'f1',
  String username = 'とも',
  DateTime? visibleUntil,
}) =>
    Friend(profile: Profile(uid: uid, username: username, bio: ''), visibleUntil: visibleUntil);
