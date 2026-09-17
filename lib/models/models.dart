// API のレスポンスに対応するモデル。
//
// 閲覧可否はサーバーが判断済みなので、ここに「見てよいか」を持たせない。

/// 投稿の種別。35mm は静止画、8mm は2秒の動画。
enum PostKind {
  film35mm('35mm'),
  film8mm('8mm');

  const PostKind(this.wire);

  /// API とやり取りする文字列表現。
  final String wire;

  static PostKind fromWire(String value) =>
      value == '8mm' ? PostKind.film8mm : PostKind.film35mm;

  bool get isVideo => this == PostKind.film8mm;
}

class Profile {
  const Profile({
    required this.uid,
    required this.username,
    required this.bio,
    this.avatarPath,
    this.beaconId,
  });

  final String uid;
  final String username;
  final String bio;

  /// API の相対パス。表示時に BloomApi.mediaUrl で絶対 URL にする。
  final String? avatarPath;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        uid: json['uid'] as String,
        username: json['username'] as String,
        bio: json['bio'] as String? ?? '',
        avatarPath: json['avatarPath'] as String?,
        beaconId: json['beaconId'] as String?,
      );

  /// BLE でアドバタイズする 4 バイトの識別子（仕様書 3.15）。
  /// 自分のプロフィールにしか入らない。
  final String? beaconId;
}

class Post {
  const Post({
    required this.id,
    required this.authorUid,
    required this.authorName,
    required this.kind,
    required this.mediaPath,
    required this.createdAt,
    required this.liked,
    required this.likeCount,
    this.authorAvatarPath,
    this.locationLabel,
  });

  final String id;
  final String authorUid;
  final String authorName;
  final String? authorAvatarPath;
  final PostKind kind;
  final String mediaPath;
  final DateTime createdAt;
  final bool liked;

  /// この投稿にいいねした人数(B1)。
  final int likeCount;

  /// 撮影地(粗いエリア名、例: "大阪市 中央区")(B2)。設定でOFFにしていた・
  /// 位置取得に失敗した場合は null。緯度経度そのものはここに入らない。
  final String? locationLabel;

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: json['id'] as String,
        authorUid: json['authorUid'] as String,
        authorName: json['authorName'] as String? ?? '',
        authorAvatarPath: json['authorAvatarPath'] as String?,
        kind: PostKind.fromWire(json['kind'] as String),
        mediaPath: json['mediaPath'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        liked: json['liked'] as bool? ?? false,
        likeCount: json['likeCount'] as int? ?? 0,
        locationLabel: json['locationLabel'] as String?,
      );

  Post copyWith({bool? liked, int? likeCount}) => Post(
        id: id,
        authorUid: authorUid,
        authorName: authorName,
        authorAvatarPath: authorAvatarPath,
        kind: kind,
        mediaPath: mediaPath,
        createdAt: createdAt,
        liked: liked ?? this.liked,
        likeCount: likeCount ?? this.likeCount,
        locationLabel: locationLabel,
      );

  /// デザインのフィルムスタンプ表記（'26 9 16）。
  String get stamp {
    final y = createdAt.year % 100;
    return "'${y.toString().padLeft(2, '0')} ${createdAt.month} "
        "${createdAt.day.toString().padLeft(2, '0')}";
  }
}

/// ホーム画面は投稿者ごとに縦で切り替えるので、投稿者単位でまとめて受け取る。
class AuthorFeed {
  const AuthorFeed({
    required this.uid,
    required this.username,
    required this.posts,
    this.avatarPath,
  });

  final String uid;
  final String username;
  final String? avatarPath;
  final List<Post> posts;

  factory AuthorFeed.fromJson(Map<String, dynamic> json) => AuthorFeed(
        uid: json['uid'] as String,
        username: json['username'] as String? ?? '',
        avatarPath: json['avatarPath'] as String?,
        posts: (json['posts'] as List)
            .map((e) => Post.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Friend {
  const Friend({required this.profile, this.visibleUntil});

  final Profile profile;

  /// 自分から見たこのフレンドの閲覧可能時刻（仕様書 3.12）。
  /// null なら一度も近距離イベントが成立していない。
  final DateTime? visibleUntil;

  factory Friend.fromJson(Map<String, dynamic> json) {
    final until = json['visibleUntil'] as int?;
    return Friend(
      profile: Profile.fromJson(json),
      visibleUntil:
          until == null ? null : DateTime.fromMillisecondsSinceEpoch(until),
    );
  }
}

class FriendRequests {
  const FriendRequests({required this.incoming, required this.outgoing});

  /// 自分宛ての未承認申請。
  final List<Profile> incoming;

  /// 自分が送って承認待ちのもの。
  final List<Profile> outgoing;

  factory FriendRequests.fromJson(Map<String, dynamic> json) => FriendRequests(
        incoming: (json['incoming'] as List)
            .map((e) => Profile.fromJson(e as Map<String, dynamic>))
            .toList(),
        outgoing: (json['outgoing'] as List)
            .map((e) => Profile.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static const empty = FriendRequests(incoming: [], outgoing: []);
}

/// 近距離イベント報告の結果。
class ProximityResult {
  const ProximityResult({
    required this.exchanged,
    this.peerName,
    this.reason,
  });

  /// 閲覧権限を交換したか。クールダウン中は false（仕様書 6.3）。
  final bool exchanged;
  final String? peerName;
  final String? reason;

  factory ProximityResult.fromJson(Map<String, dynamic> json) => ProximityResult(
        exchanged: json['exchanged'] as bool? ?? false,
        peerName: json['peerName'] as String?,
        reason: json['reason'] as String?,
      );
}

/// beaconId をユーザーに解決した結果。
class ResolvedPeers {
  const ResolvedPeers({required this.friends, required this.strangers});

  /// 既存フレンド。閲覧権限の交換対象。
  final List<Profile> friends;

  /// フレンド未登録の相手。フレンド追加モードのときだけ入る（仕様書 6.4）。
  final List<Profile> strangers;

  factory ResolvedPeers.fromJson(Map<String, dynamic> json) => ResolvedPeers(
        friends: (json['friends'] as List)
            .map((e) => Profile.fromJson(e as Map<String, dynamic>))
            .toList(),
        strangers: (json['strangers'] as List)
            .map((e) => Profile.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  bool get isEmpty => friends.isEmpty && strangers.isEmpty;
}

/// アプリ内通知の種別。
enum NotificationKind {
  friendRequest('friend_request'),
  friendAccepted('friend_accepted'),
  proximity('proximity'),
  like('like'),
  unknown('');

  const NotificationKind(this.wire);

  final String wire;

  static NotificationKind fromWire(String value) => values.firstWhere(
        (k) => k.wire == value,
        orElse: () => NotificationKind.unknown,
      );
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.read,
    required this.createdAt,
    this.actorUid,
    this.actorName,
    this.actorAvatarPath,
    this.postId,
  });

  final String id;
  final NotificationKind kind;
  final bool read;
  final DateTime createdAt;

  /// きっかけになった相手。退会済みなら名前が null になる。
  final String? actorUid;
  final String? actorName;
  final String? actorAvatarPath;
  final String? postId;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        kind: NotificationKind.fromWire(json['kind'] as String),
        read: json['read'] as bool? ?? false,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        actorUid: json['actorUid'] as String?,
        actorName: json['actorName'] as String?,
        actorAvatarPath: json['actorAvatarPath'] as String?,
        postId: json['postId'] as String?,
      );

  /// 一覧に出す文。相手が消えていても読める文にする。
  String get message {
    final who = actorName ?? '相手';
    return switch (kind) {
      NotificationKind.friendRequest => '$who さんからフレンド申請が届きました',
      NotificationKind.friendAccepted => '$who さんとフレンドになりました',
      NotificationKind.proximity => '$who さんとデータを共有しました',
      NotificationKind.like => '$who さんが投稿にいいねしました',
      NotificationKind.unknown => '新しいお知らせがあります',
    };
  }
}

/// 通知一覧と未読件数。
class NotificationFeed {
  const NotificationFeed({
    required this.notifications,
    required this.unreadCount,
  });

  final List<AppNotification> notifications;
  final int unreadCount;

  factory NotificationFeed.fromJson(Map<String, dynamic> json) =>
      NotificationFeed(
        unreadCount: json['unreadCount'] as int? ?? 0,
        notifications: (json['notifications'] as List)
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static const empty = NotificationFeed(notifications: [], unreadCount: 0);
}
