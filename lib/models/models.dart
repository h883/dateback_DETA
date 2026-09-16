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
      );
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
    this.authorAvatarPath,
  });

  final String id;
  final String authorUid;
  final String authorName;
  final String? authorAvatarPath;
  final PostKind kind;
  final String mediaPath;
  final DateTime createdAt;
  final bool liked;

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
      );

  Post copyWith({bool? liked}) => Post(
        id: id,
        authorUid: authorUid,
        authorName: authorName,
        authorAvatarPath: authorAvatarPath,
        kind: kind,
        mediaPath: mediaPath,
        createdAt: createdAt,
        liked: liked ?? this.liked,
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
