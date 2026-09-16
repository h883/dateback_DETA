/**
 * Firebase ID トークンの検証。
 *
 * Admin SDK は Workers では動かないので、Google が公開している JWKS を取って
 * WebCrypto で RS256 の署名を検証する。JWKS は max-age の間だけメモリに持つ。
 */

const JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

interface Jwk extends JsonWebKey {
  kid: string;
}

let jwkCache: { keys: Map<string, Jwk>; expiresAt: number } | null = null;

async function getJwk(kid: string): Promise<Jwk | null> {
  const now = Date.now();
  if (!jwkCache || jwkCache.expiresAt <= now) {
    const res = await fetch(JWKS_URL);
    if (!res.ok) throw new Error(`JWKS fetch failed: ${res.status}`);
    const body = (await res.json()) as { keys: Jwk[] };

    // Cache-Control の max-age を尊重する。取れなければ1時間。
    const maxAge = Number(
      /max-age=(\d+)/.exec(res.headers.get('cache-control') ?? '')?.[1] ?? 3600,
    );
    jwkCache = {
      keys: new Map(body.keys.map((k) => [k.kid, k])),
      expiresAt: now + maxAge * 1000,
    };
  }
  return jwkCache.keys.get(kid) ?? null;
}

function base64UrlToBytes(input: string): Uint8Array {
  const padded = input.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(padded.padEnd(Math.ceil(padded.length / 4) * 4, '='));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function decodeJson(segment: string): Record<string, unknown> {
  return JSON.parse(new TextDecoder().decode(base64UrlToBytes(segment)));
}

export interface VerifiedUser {
  uid: string;
  email?: string;
  name?: string;
  picture?: string;
}

/**
 * 検証に通れば uid を返す。通らなければ理由を添えて null を返す。
 */
export async function verifyIdToken(
  token: string,
  projectId: string,
): Promise<VerifiedUser | null> {
  const parts = token.split('.');
  if (parts.length !== 3) return null;

  const [rawHeader, rawPayload, rawSignature] = parts;

  let header: Record<string, unknown>;
  let payload: Record<string, unknown>;
  try {
    header = decodeJson(rawHeader);
    payload = decodeJson(rawPayload);
  } catch {
    return null;
  }

  if (header.alg !== 'RS256' || typeof header.kid !== 'string') return null;

  const jwk = await getJwk(header.kid);
  if (!jwk) return null;

  const key = await crypto.subtle.importKey(
    'jwk',
    jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );

  const signed = new TextEncoder().encode(`${rawHeader}.${rawPayload}`);
  const ok = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    base64UrlToBytes(rawSignature),
    signed,
  );
  if (!ok) return null;

  const now = Math.floor(Date.now() / 1000);
  if (payload.aud !== projectId) return null;
  if (payload.iss !== `https://securetoken.google.com/${projectId}`) return null;
  if (typeof payload.exp !== 'number' || payload.exp <= now) return null;
  if (typeof payload.iat !== 'number' || payload.iat > now + 300) return null;
  if (typeof payload.sub !== 'string' || payload.sub.length === 0) return null;

  return {
    uid: payload.sub,
    email: typeof payload.email === 'string' ? payload.email : undefined,
    name: typeof payload.name === 'string' ? payload.name : undefined,
    picture: typeof payload.picture === 'string' ? payload.picture : undefined,
  };
}
