/**
 * 本SNS のバックエンド。
 *
 * 仕様書 4.4 のとおり、投稿が閲覧できるかどうかの判定はここで完結させる。
 * フロントには「その時点で閲覧可能な投稿」だけを返し、投稿時刻と閲覧可能時刻の
 * 突き合わせをクライアントにやらせない。
 */
import { verifyIdToken, type VerifiedUser } from './auth';

export interface Env {
  DB: D1Database;
  /**
   * メディアの実体。R2 は無料枠でもカード登録が要るため KV を使っている。
   * 1 値あたり 25MB まで。R2 に移すときは put/get をここだけ差し替えればよい。
   */
  MEDIA: KVNamespace;
  FIREBASE_PROJECT_ID: string;
}

/** 仕様書 6.3。同じ相手とこの時間内は新しい近距離イベントとして扱わない。 */
const PROXIMITY_COOLDOWN_MS = 60_000;

const MAX_MEDIA_BYTES = 25 * 1024 * 1024;
const MAX_AVATAR_BYTES = 4 * 1024 * 1024;

// ---------------------------------------------------------------- helpers

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

function fail(status: number, code: string, message: string): Response {
  return json({ error: { code, message } }, status);
}

function now(): number {
  return Date.now();
}

/** users 行を API 表現に変換する。avatar は media エンドポイントの相対パス。 */
interface UserRow {
  uid: string;
  username: string;
  bio: string;
  avatar_key: string | null;
  beacon_id?: string | null;
}

function toProfile(row: UserRow) {
  return {
    uid: row.uid,
    username: row.username,
    bio: row.bio,
    avatarPath: row.avatar_key ? `/api/media/${row.avatar_key}` : null,
  };
}

/**
 * 自分向けのプロフィール。BLE でアドバタイズする beaconId を含む。
 * 他人のプロフィールには出さない。
 */
function toSelfProfile(row: UserRow) {
  return { ...toProfile(row), beaconId: row.beacon_id ?? null };
}

/** 4 バイトの近距離識別情報。電波に載るのはこれだけ。 */
function newBeaconId(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(4));
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * beacon_id が未発行なら採番する。既存ユーザーも初回アクセスで埋まる。
 * 一意制約に当たったら引き直す。
 */
async function ensureBeaconId(env: Env, uid: string): Promise<string | null> {
  const row = await env.DB.prepare('SELECT beacon_id FROM users WHERE uid = ?')
    .bind(uid)
    .first<{ beacon_id: string | null }>();
  if (!row) return null;
  if (row.beacon_id) return row.beacon_id;

  for (let attempt = 0; attempt < 5; attempt++) {
    const candidate = newBeaconId();
    try {
      await env.DB.prepare('UPDATE users SET beacon_id = ? WHERE uid = ?')
        .bind(candidate, uid)
        .run();
      return candidate;
    } catch {
      // UNIQUE 衝突。引き直す。
    }
  }
  return null;
}

interface PostRow {
  id: string;
  uid: string;
  username: string;
  avatar_key: string | null;
  kind: string;
  media_key: string;
  created_at: number;
  liked: number;
}

function toPost(row: PostRow) {
  return {
    id: row.id,
    authorUid: row.uid,
    authorName: row.username,
    authorAvatarPath: row.avatar_key ? `/api/media/${row.avatar_key}` : null,
    kind: row.kind,
    mediaPath: `/api/media/${row.media_key}`,
    createdAt: row.created_at,
    liked: row.liked === 1,
  };
}

/**
 * 閲覧可能な投稿を引くための共通 SQL 片。
 * 自分の投稿は常に見える。他人の投稿は view_permissions に行があり、
 * かつ投稿時刻が visible_until 以前のものだけ。
 */
const VISIBLE_POSTS_SQL = `
  SELECT p.id, p.uid, u.username, u.avatar_key, p.kind, p.media_key, p.created_at,
         EXISTS (SELECT 1 FROM likes l WHERE l.post_id = p.id AND l.uid = ?1) AS liked
    FROM posts p
    JOIN users u ON u.uid = p.uid
   WHERE (
           p.uid = ?1
           OR EXISTS (
                SELECT 1 FROM view_permissions vp
                 WHERE vp.viewer_uid = ?1
                   AND vp.author_uid = p.uid
                   AND p.created_at <= vp.visible_until
              )
         )
`;

/** 通知の種別。DB の CHECK と合わせる。 */
type NotificationKind =
  | 'friend_request'
  | 'friend_accepted'
  | 'proximity'
  | 'like';

/**
 * アプリ内通知を1件積む。
 *
 * 通知の失敗で本来の操作を落としたくないので、呼び出し側では待たずに投げる。
 */
async function notify(
  env: Env,
  uid: string,
  kind: NotificationKind,
  options: { actorUid?: string; postId?: string } = {},
): Promise<void> {
  try {
    await env.DB.prepare(
      `INSERT INTO notifications (id, uid, kind, actor_uid, post_id, created_at)
            VALUES (?, ?, ?, ?, ?, ?)`,
    )
      .bind(
        crypto.randomUUID(),
        uid,
        kind,
        options.actorUid ?? null,
        options.postId ?? null,
        now(),
      )
      .run();
  } catch {
    // 通知が積めなくても本体の操作は成功させる。
  }
}

// ---------------------------------------------------------------- routing

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }
    if (!path.startsWith('/api/')) {
      return fail(404, 'not_found', 'Unknown path');
    }

    const auth = request.headers.get('authorization') ?? '';
    if (!auth.startsWith('Bearer ')) {
      return fail(401, 'unauthenticated', 'Bearer token required');
    }

    let user: VerifiedUser | null;
    try {
      user = await verifyIdToken(auth.slice(7), env.FIREBASE_PROJECT_ID);
    } catch (e) {
      return fail(503, 'auth_unavailable', `Token verification failed: ${e}`);
    }
    if (!user) return fail(401, 'unauthenticated', 'Invalid ID token');

    try {
      const res = await route(request, env, url, user);
      for (const [k, v] of Object.entries(corsHeaders())) res.headers.set(k, v);
      return res;
    } catch (e) {
      return fail(500, 'internal', String(e));
    }
  },
} satisfies ExportedHandler<Env>;

function corsHeaders(): Record<string, string> {
  return {
    'access-control-allow-origin': '*',
    'access-control-allow-headers': 'authorization,content-type,x-post-kind',
    'access-control-allow-methods': 'GET,POST,PUT,DELETE,OPTIONS',
  };
}

async function route(
  request: Request,
  env: Env,
  url: URL,
  user: VerifiedUser,
): Promise<Response> {
  const method = request.method;
  const segments = url.pathname.split('/').filter(Boolean).slice(1); // drop "api"
  const [head, ...rest] = segments;

  switch (head) {
    case 'me':
      return handleMe(method, rest, request, env, user);
    case 'users':
      return handleUsers(method, rest, env, user);
    case 'posts':
      return handlePosts(method, rest, request, env, user);
    case 'feed':
      return method === 'GET'
        ? handleFeed(env, user)
        : fail(405, 'method_not_allowed', method);
    case 'friends':
      return handleFriends(method, rest, request, env, user);
    case 'notifications':
      return handleNotifications(method, rest, request, env, user);
    case 'proximity':
      if (rest[0] === 'resolve') {
        return method === 'POST'
          ? handleResolveBeacons(request, env, user)
          : fail(405, 'method_not_allowed', method);
      }
      return method === 'POST'
        ? handleProximity(request, env, user)
        : fail(405, 'method_not_allowed', method);
    case 'media':
      return method === 'GET'
        ? handleMedia(rest.join('/'), env)
        : fail(405, 'method_not_allowed', method);
    default:
      return fail(404, 'not_found', url.pathname);
  }
}

// ---------------------------------------------------------------- /api/me

async function handleMe(
  method: string,
  rest: string[],
  request: Request,
  env: Env,
  user: VerifiedUser,
): Promise<Response> {
  if (rest[0] === 'avatar') {
    if (method !== 'PUT') return fail(405, 'method_not_allowed', method);
    return putAvatar(request, env, user);
  }
  if (rest.length > 0) return fail(404, 'not_found', rest.join('/'));

  if (method === 'GET') {
    const row = await env.DB.prepare(
      'SELECT uid, username, bio, avatar_key FROM users WHERE uid = ?',
    )
      .bind(user.uid)
      .first<UserRow>();
    // プロフィール未設定。クライアントはこれを見て設定画面へ送る。
    if (!row) return fail(404, 'profile_not_set', 'Profile is not set up yet');
    row.beacon_id = await ensureBeaconId(env, user.uid);
    return json(toSelfProfile(row));
  }

  if (method === 'PUT') {
    const body = (await request.json().catch(() => null)) as {
      username?: unknown;
      bio?: unknown;
    } | null;
    if (!body) return fail(400, 'bad_request', 'JSON body required');

    const username = String(body.username ?? '').trim();
    const bio = String(body.bio ?? '').trim();

    // Google アカウントの表示名をそのまま使えるよう、日本語も通す。
    // 制御文字だけ弾く。
    if (username.length < 1 || [...username].length > 20) {
      return fail(400, 'invalid_username', '名前は1〜20文字にしてください');
    }
    // eslint-disable-next-line no-control-regex
    if (/[ -]/.test(username)) {
      return fail(400, 'invalid_username', '使えない文字が含まれています');
    }
    if (bio.length > 160) {
      return fail(400, 'invalid_bio', '自己紹介は160文字までです');
    }

    const ts = now();
    await env.DB.prepare(
      `INSERT INTO users (uid, username, bio, created_at, updated_at)
            VALUES (?1, ?2, ?3, ?4, ?4)
       ON CONFLICT(uid) DO UPDATE SET username = ?2, bio = ?3, updated_at = ?4`,
    )
      .bind(user.uid, username, bio, ts)
      .run();

    const row = await env.DB.prepare(
      'SELECT uid, username, bio, avatar_key FROM users WHERE uid = ?',
    )
      .bind(user.uid)
      .first<UserRow>();
    row!.beacon_id = await ensureBeaconId(env, user.uid);
    return json(toSelfProfile(row!));
  }

  return fail(405, 'method_not_allowed', method);
}

async function putAvatar(
  request: Request,
  env: Env,
  user: VerifiedUser,
): Promise<Response> {
  const contentType = request.headers.get('content-type') ?? '';
  if (!contentType.startsWith('image/')) {
    return fail(400, 'bad_content_type', '画像を送ってください');
  }

  const bytes = await request.arrayBuffer();
  if (bytes.byteLength === 0) return fail(400, 'empty_body', 'Empty body');
  if (bytes.byteLength > MAX_AVATAR_BYTES) {
    return fail(413, 'too_large', 'アイコンは4MBまでです');
  }

  const key = `avatars/${user.uid}/${crypto.randomUUID()}`;
  await env.MEDIA.put(key, bytes, { metadata: { contentType } });

  const ts = now();
  // プロフィール未作成でもアイコンだけ先に置けるよう INSERT も面倒を見る。
  await env.DB.prepare(
    `INSERT INTO users (uid, username, bio, avatar_key, created_at, updated_at)
          VALUES (?1, ?2, '', ?3, ?4, ?4)
     ON CONFLICT(uid) DO UPDATE SET avatar_key = ?3, updated_at = ?4`,
  )
    .bind(user.uid, `user_${user.uid.slice(0, 8)}`, key, ts)
    .run();

  const row = await env.DB.prepare(
    'SELECT uid, username, bio, avatar_key FROM users WHERE uid = ?',
  )
    .bind(user.uid)
    .first<UserRow>();
  return json(toProfile(row!));
}

// ---------------------------------------------------------------- /api/users

async function handleUsers(
  method: string,
  rest: string[],
  env: Env,
  user: VerifiedUser,
): Promise<Response> {
  if (method !== 'GET') return fail(405, 'method_not_allowed', method);

  // 仕様書 7.2 フレンド追加モードの候補。
  // BLE が未実装の間は「自分ともフレンドでもない既存ユーザー」を候補として返す。
  if (rest[0] === 'nearby' || rest.length === 0) {
    const { results } = await env.DB.prepare(
      `SELECT u.uid, u.username, u.bio, u.avatar_key
         FROM users u
        WHERE u.uid <> ?1
          AND NOT EXISTS (
                SELECT 1 FROM friendships f
                 WHERE (f.requester = ?1 AND f.addressee = u.uid)
                    OR (f.requester = u.uid AND f.addressee = ?1)
              )
        ORDER BY u.updated_at DESC
        LIMIT 20`,
    )
      .bind(user.uid)
      .all<UserRow>();
    return json({ users: results.map(toProfile) });
  }

  const uid = rest[0];

  if (rest[1] === 'posts') {
    const { results } = await env.DB.prepare(
      `${VISIBLE_POSTS_SQL} AND p.uid = ?2 ORDER BY p.created_at DESC LIMIT 100`,
    )
      .bind(user.uid, uid)
      .all<PostRow>();
    return json({ posts: results.map(toPost) });
  }

  if (rest.length === 1) {
    const row = await env.DB.prepare(
      'SELECT uid, username, bio, avatar_key FROM users WHERE uid = ?',
    )
      .bind(uid)
      .first<UserRow>();
    if (!row) return fail(404, 'not_found', 'No such user');
    return json(toProfile(row));
  }

  return fail(404, 'not_found', rest.join('/'));
}

// ---------------------------------------------------------------- /api/posts

async function handlePosts(
  method: string,
  rest: string[],
  request: Request,
  env: Env,
  user: VerifiedUser,
): Promise<Response> {
  // POST /api/posts — 本文は生のメディア、種別は X-Post-Kind ヘッダ。
  if (method === 'POST' && rest.length === 0) {
    const kind = request.headers.get('x-post-kind') ?? '';
    if (kind !== '35mm' && kind !== '8mm') {
      return fail(400, 'bad_kind', 'X-Post-Kind must be 35mm or 8mm');
    }
    const contentType = request.headers.get('content-type') ?? '';
    const wantsVideo = kind === '8mm';
    if (wantsVideo !== contentType.startsWith('video/')) {
      return fail(400, 'bad_content_type', `${kind} に合わない content-type です`);
    }

    const profile = await env.DB.prepare('SELECT uid FROM users WHERE uid = ?')
      .bind(user.uid)
      .first<{ uid: string }>();
    if (!profile) {
      return fail(409, 'profile_not_set', '先にプロフィールを設定してください');
    }

    const bytes = await request.arrayBuffer();
    if (bytes.byteLength === 0) return fail(400, 'empty_body', 'Empty body');
    if (bytes.byteLength > MAX_MEDIA_BYTES) {
      return fail(413, 'too_large', 'メディアは25MBまでです');
    }

    const id = crypto.randomUUID();
    const key = `posts/${user.uid}/${id}`;
    await env.MEDIA.put(key, bytes, { metadata: { contentType } });

    // 投稿時刻はサーバー時刻。端末時計のずれで閲覧制御が狂わないようにする。
    const createdAt = now();
    await env.DB.prepare(
      `INSERT INTO posts (id, uid, kind, media_key, content_type, created_at)
            VALUES (?, ?, ?, ?, ?, ?)`,
    )
      .bind(id, user.uid, kind, key, contentType, createdAt)
      .run();

    return json({ id, kind, mediaPath: `/api/media/${key}`, createdAt }, 201);
  }

  // GET /api/posts/mine — 自分の投稿は常に全部見える。
  if (method === 'GET' && rest[0] === 'mine') {
    const { results } = await env.DB.prepare(
      `SELECT p.id, p.uid, u.username, u.avatar_key, p.kind, p.media_key, p.created_at,
              EXISTS (SELECT 1 FROM likes l WHERE l.post_id = p.id AND l.uid = ?1) AS liked
         FROM posts p JOIN users u ON u.uid = p.uid
        WHERE p.uid = ?1
        ORDER BY p.created_at DESC
        LIMIT 100`,
    )
      .bind(user.uid)
      .all<PostRow>();
    return json({ posts: results.map(toPost) });
  }

  // /api/posts/:id/like
  if (rest[1] === 'like') {
    const postId = rest[0];
    if (method === 'POST') {
      // 閲覧できない投稿にいいねは付けられない。
      const visible = await env.DB.prepare(
        `SELECT p.id FROM (${VISIBLE_POSTS_SQL}) p WHERE p.id = ?2`,
      )
        .bind(user.uid, postId)
        .first<{ id: string }>();
      if (!visible) return fail(403, 'not_visible', 'その投稿は閲覧できません');

      const inserted = await env.DB.prepare(
        'INSERT OR IGNORE INTO likes (post_id, uid, created_at) VALUES (?, ?, ?)',
      )
        .bind(postId, user.uid, now())
        .run();

      // 初回のいいねだけ通知する。連打で増やさない。
      if (inserted.meta.changes) {
        const author = await env.DB.prepare(
          'SELECT uid FROM posts WHERE id = ?',
        )
          .bind(postId)
          .first<{ uid: string }>();
        if (author && author.uid !== user.uid) {
          await notify(env, author.uid, 'like', {
            actorUid: user.uid,
            postId,
          });
        }
      }
      return json({ liked: true });
    }
    if (method === 'DELETE') {
      await env.DB.prepare('DELETE FROM likes WHERE post_id = ? AND uid = ?')
        .bind(postId, user.uid)
        .run();
      return json({ liked: false });
    }
    return fail(405, 'method_not_allowed', method);
  }

  return fail(404, 'not_found', rest.join('/'));
}

// ---------------------------------------------------------------- /api/feed

async function handleFeed(env: Env, user: VerifiedUser): Promise<Response> {
  const { results } = await env.DB.prepare(
    `${VISIBLE_POSTS_SQL} AND p.uid <> ?1 ORDER BY p.created_at DESC LIMIT 200`,
  )
    .bind(user.uid)
    .all<PostRow>();

  // ホーム画面は「ユーザーごとに縦に切り替え、そのユーザーの過去を辿る」構造なので
  // 投稿者ごとにまとめて返す。
  const byAuthor = new Map<string, ReturnType<typeof toPost>[]>();
  for (const row of results) {
    const post = toPost(row);
    const list = byAuthor.get(post.authorUid);
    if (list) list.push(post);
    else byAuthor.set(post.authorUid, [post]);
  }

  return json({
    authors: [...byAuthor.entries()].map(([uid, posts]) => ({
      uid,
      username: posts[0].authorName,
      avatarPath: posts[0].authorAvatarPath,
      posts,
    })),
  });
}

// ---------------------------------------------------------------- /api/friends

async function handleFriends(
  method: string,
  rest: string[],
  request: Request,
  env: Env,
  user: VerifiedUser,
): Promise<Response> {
  // GET /api/friends
  if (method === 'GET' && rest.length === 0) {
    const { results } = await env.DB.prepare(
      `SELECT u.uid, u.username, u.bio, u.avatar_key
         FROM friendships f
         JOIN users u
           ON u.uid = CASE WHEN f.requester = ?1 THEN f.addressee ELSE f.requester END
        WHERE f.status = 'accepted' AND (f.requester = ?1 OR f.addressee = ?1)
        ORDER BY u.username COLLATE NOCASE`,
    )
      .bind(user.uid)
      .all<UserRow>();

    // 各フレンドについて現在の閲覧可能時刻も返す（プロフィール画面の表示用）。
    const { results: perms } = await env.DB.prepare(
      'SELECT author_uid, visible_until FROM view_permissions WHERE viewer_uid = ?',
    )
      .bind(user.uid)
      .all<{ author_uid: string; visible_until: number }>();
    const permMap = new Map(perms.map((p) => [p.author_uid, p.visible_until]));

    return json({
      friends: results.map((r) => ({
        ...toProfile(r),
        visibleUntil: permMap.get(r.uid) ?? null,
      })),
    });
  }

  if (rest[0] !== 'requests') return fail(404, 'not_found', rest.join('/'));

  // GET /api/friends/requests — 自分宛ての未承認申請（仕様書 13.3 受信側）。
  if (method === 'GET' && rest.length === 1) {
    const { results } = await env.DB.prepare(
      `SELECT u.uid, u.username, u.bio, u.avatar_key
         FROM friendships f JOIN users u ON u.uid = f.requester
        WHERE f.addressee = ? AND f.status = 'pending'
        ORDER BY f.created_at DESC`,
    )
      .bind(user.uid)
      .all<UserRow>();

    // 自分が送って承認待ちのものも返す（13.3 送信側の「承認を待っています」）。
    const { results: outgoing } = await env.DB.prepare(
      `SELECT u.uid, u.username, u.bio, u.avatar_key
         FROM friendships f JOIN users u ON u.uid = f.addressee
        WHERE f.requester = ? AND f.status = 'pending'`,
    )
      .bind(user.uid)
      .all<UserRow>();

    return json({
      incoming: results.map(toProfile),
      outgoing: outgoing.map(toProfile),
    });
  }

  // POST /api/friends/requests — 申請する。
  if (method === 'POST' && rest.length === 1) {
    const body = (await request.json().catch(() => null)) as { uid?: string } | null;
    const target = body?.uid;
    if (!target) return fail(400, 'bad_request', 'uid required');
    if (target === user.uid) return fail(400, 'bad_request', '自分には申請できません');

    const exists = await env.DB.prepare('SELECT uid FROM users WHERE uid = ?')
      .bind(target)
      .first<{ uid: string }>();
    if (!exists) return fail(404, 'not_found', 'No such user');

    const ts = now();
    // 相手から既に申請が来ていれば、この操作で成立とみなす（仕様書 7.3）。
    const reverse = await env.DB.prepare(
      `SELECT status FROM friendships WHERE requester = ? AND addressee = ?`,
    )
      .bind(target, user.uid)
      .first<{ status: string }>();

    if (reverse) {
      await env.DB.prepare(
        `UPDATE friendships SET status = 'accepted', updated_at = ?
          WHERE requester = ? AND addressee = ?`,
      )
        .bind(ts, target, user.uid)
        .run();
      await notify(env, target, 'friend_accepted', { actorUid: user.uid });
      return json({ status: 'accepted' });
    }

    const created = await env.DB.prepare(
      `INSERT INTO friendships (requester, addressee, status, created_at, updated_at)
            VALUES (?1, ?2, 'pending', ?3, ?3)
       ON CONFLICT(requester, addressee) DO NOTHING`,
    )
      .bind(user.uid, target, ts)
      .run();
    // 同じ相手に連続で申請しても通知は増やさない。
    if (created.meta.changes) {
      await notify(env, target, 'friend_request', { actorUid: user.uid });
    }
    return json({ status: 'pending' });
  }

  const peer = rest[1];
  if (!peer) return fail(404, 'not_found', rest.join('/'));

  // POST /api/friends/requests/:uid/accept
  if (method === 'POST' && rest[2] === 'accept') {
    const res = await env.DB.prepare(
      `UPDATE friendships SET status = 'accepted', updated_at = ?
        WHERE requester = ? AND addressee = ? AND status = 'pending'`,
    )
      .bind(now(), peer, user.uid)
      .run();
    if (!res.meta.changes) return fail(404, 'not_found', '申請が見つかりません');
    await notify(env, peer, 'friend_accepted', { actorUid: user.uid });
    return json({ status: 'accepted' });
  }

  // DELETE /api/friends/requests/:uid — 申請の取り消し / 却下。
  if (method === 'DELETE') {
    await env.DB.prepare(
      `DELETE FROM friendships
        WHERE status = 'pending'
          AND ((requester = ?1 AND addressee = ?2) OR (requester = ?2 AND addressee = ?1))`,
    )
      .bind(user.uid, peer)
      .run();
    return json({ status: 'none' });
  }

  return fail(405, 'method_not_allowed', method);
}

// ---------------------------------------------------------------- /api/proximity

/**
 * BLE で拾った beaconId をまとめてユーザーに解決する。
 *
 * 仕様書 6.4：通常の自動検知では非フレンドを画面に出さない。
 * フレンド追加モードのときだけ mode=discover で非フレンドも返す。
 */
async function handleResolveBeacons(
  request: Request,
  env: Env,
  user: VerifiedUser,
): Promise<Response> {
  const body = (await request.json().catch(() => null)) as {
    beaconIds?: unknown;
    mode?: unknown;
  } | null;

  const ids = Array.isArray(body?.beaconIds)
    ? body.beaconIds.filter((v): v is string => typeof v === 'string').slice(0, 30)
    : [];
  if (ids.length === 0) return json({ friends: [], strangers: [] });

  const placeholders = ids.map(() => '?').join(',');
  const { results } = await env.DB.prepare(
    `SELECT u.uid, u.username, u.bio, u.avatar_key, u.beacon_id,
            EXISTS (
              SELECT 1 FROM friendships f
               WHERE f.status = 'accepted'
                 AND ((f.requester = ?1 AND f.addressee = u.uid)
                   OR (f.requester = u.uid AND f.addressee = ?1))
            ) AS is_friend
       FROM users u
      WHERE u.beacon_id IN (${placeholders})
        AND u.uid <> ?1`,
  )
    .bind(user.uid, ...ids)
    .all<UserRow & { is_friend: number }>();

  const friends = results.filter((r) => r.is_friend === 1).map(toProfile);
  const strangers =
    body?.mode === 'discover'
      ? results.filter((r) => r.is_friend !== 1).map(toProfile)
      : [];

  return json({ friends, strangers });
}



/**
 * 近距離イベントの記録と閲覧権限交換（仕様書 3.13 / 4.3 / 6.3）。
 *
 * BLE で相手を見つけたクライアントがこれを叩く。双方向に閲覧可能時刻を
 * 「今」へ更新するので、片側が呼べば両者の権限が揃う。
 */
async function handleProximity(
  request: Request,
  env: Env,
  user: VerifiedUser,
): Promise<Response> {
  const body = (await request.json().catch(() => null)) as {
    peerUid?: string;
    beaconId?: string;
  } | null;

  // BLE で拾えるのは beaconId だけ。uid への解決はここで行う。
  let peer = body?.peerUid ?? null;
  if (!peer && body?.beaconId) {
    const row = await env.DB.prepare('SELECT uid FROM users WHERE beacon_id = ?')
      .bind(body.beaconId)
      .first<{ uid: string }>();
    if (!row) return fail(404, 'unknown_beacon', '相手が特定できませんでした');
    peer = row.uid;
  }

  if (!peer) return fail(400, 'bad_request', 'peerUid or beaconId required');
  if (peer === user.uid) return fail(400, 'bad_request', '自分とは交換できません');

  // 仕様書 6.4 / 10.3：交換はフレンド同士に限る。
  const friend = await env.DB.prepare(
    `SELECT 1 AS ok FROM friendships
      WHERE status = 'accepted'
        AND ((requester = ?1 AND addressee = ?2) OR (requester = ?2 AND addressee = ?1))`,
  )
    .bind(user.uid, peer)
    .first<{ ok: number }>();
  if (!friend) return fail(403, 'not_friends', 'フレンドではありません');

  const ts = now();

  // 仕様書 6.3：同じ近距離状態が続いている間は交換も通知も繰り返さない。
  const [a, b] = user.uid < peer ? [user.uid, peer] : [peer, user.uid];
  const recent = await env.DB.prepare(
    `SELECT occurred_at FROM proximity_events
      WHERE uid_a = ? AND uid_b = ? AND occurred_at > ?
      ORDER BY occurred_at DESC LIMIT 1`,
  )
    .bind(a, b, ts - PROXIMITY_COOLDOWN_MS)
    .first<{ occurred_at: number }>();

  if (recent) {
    return json({ exchanged: false, reason: 'cooldown', occurredAt: recent.occurred_at });
  }

  const upsert = `INSERT INTO view_permissions (viewer_uid, author_uid, visible_until, updated_at)
                       VALUES (?1, ?2, ?3, ?3)
                  ON CONFLICT(viewer_uid, author_uid)
                  DO UPDATE SET visible_until = ?3, updated_at = ?3`;

  await env.DB.batch([
    env.DB.prepare(
      'INSERT INTO proximity_events (id, uid_a, uid_b, occurred_at) VALUES (?, ?, ?, ?)',
    ).bind(crypto.randomUUID(), a, b, ts),
    env.DB.prepare(upsert).bind(user.uid, peer, ts),
    env.DB.prepare(upsert).bind(peer, user.uid, ts),
  ]);

  // 仕様書 F-12。交換が成立したことを双方に残す。
  // 呼んだ側は戻り値で知れるが、相手はアプリを見ていないかもしれない。
  await notify(env, peer, 'proximity', { actorUid: user.uid });
  await notify(env, user.uid, 'proximity', { actorUid: peer });

  const peerRow = await env.DB.prepare('SELECT username FROM users WHERE uid = ?')
    .bind(peer)
    .first<{ username: string }>();

  return json({
    exchanged: true,
    occurredAt: ts,
    peerUid: peer,
    peerName: peerRow?.username ?? '',
  });
}

// ---------------------------------------------------------------- /api/notifications

interface NotificationRow {
  id: string;
  kind: string;
  actor_uid: string | null;
  actor_name: string | null;
  actor_avatar_key: string | null;
  post_id: string | null;
  read_at: number | null;
  created_at: number;
}

async function handleNotifications(
  method: string,
  rest: string[],
  request: Request,
  env: Env,
  user: VerifiedUser,
): Promise<Response> {
  // GET /api/notifications — 一覧と未読件数。
  if (method === 'GET' && rest.length === 0) {
    const { results } = await env.DB.prepare(
      `SELECT n.id, n.kind, n.actor_uid, n.post_id, n.read_at, n.created_at,
              a.username AS actor_name, a.avatar_key AS actor_avatar_key
         FROM notifications n
         LEFT JOIN users a ON a.uid = n.actor_uid
        WHERE n.uid = ?
        ORDER BY n.created_at DESC
        LIMIT 100`,
    )
      .bind(user.uid)
      .all<NotificationRow>();

    const unread = await env.DB.prepare(
      'SELECT COUNT(*) AS c FROM notifications WHERE uid = ? AND read_at IS NULL',
    )
      .bind(user.uid)
      .first<{ c: number }>();

    return json({
      unreadCount: unread?.c ?? 0,
      notifications: results.map((row) => ({
        id: row.id,
        kind: row.kind,
        actorUid: row.actor_uid,
        actorName: row.actor_name,
        actorAvatarPath: row.actor_avatar_key
          ? `/api/media/${row.actor_avatar_key}`
          : null,
        postId: row.post_id,
        read: row.read_at !== null,
        createdAt: row.created_at,
      })),
    });
  }

  // POST /api/notifications/read — まとめて既読にする。
  // id を渡さなければ全件。
  if (method === 'POST' && rest[0] === 'read') {
    const body = (await request.json().catch(() => null)) as {
      ids?: unknown;
    } | null;
    const ids = Array.isArray(body?.ids)
      ? body.ids.filter((v): v is string => typeof v === 'string').slice(0, 100)
      : null;

    const ts = now();
    if (ids && ids.length > 0) {
      const placeholders = ids.map(() => '?').join(',');
      await env.DB.prepare(
        `UPDATE notifications SET read_at = ?
          WHERE uid = ? AND read_at IS NULL AND id IN (${placeholders})`,
      )
        .bind(ts, user.uid, ...ids)
        .run();
    } else {
      await env.DB.prepare(
        'UPDATE notifications SET read_at = ? WHERE uid = ? AND read_at IS NULL',
      )
        .bind(ts, user.uid)
        .run();
    }
    return json({ ok: true });
  }

  return fail(404, 'not_found', rest.join('/'));
}

// ---------------------------------------------------------------- /api/media

async function handleMedia(key: string, env: Env): Promise<Response> {
  if (!key) return fail(404, 'not_found', 'No key');

  const { value, metadata } = await env.MEDIA.getWithMetadata<{
    contentType?: string;
  }>(key, 'stream');
  if (!value) return fail(404, 'not_found', 'No such object');

  return new Response(value, {
    headers: {
      'content-type': metadata?.contentType ?? 'application/octet-stream',
      // キーは UUID なので推測できない。端末側でキャッシュさせる。
      'cache-control': 'private, max-age=86400',
    },
  });
}
