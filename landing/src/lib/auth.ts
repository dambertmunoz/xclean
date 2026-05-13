import crypto from "node:crypto";
import { cookies } from "next/headers";

/// Cookie-based single-admin auth. The cookie holds a payload + HMAC-SHA256
/// signature so we never trust the client. No DB session table needed —
/// re-signing on every request is microseconds.
///
/// Layout: `<expiresAt>.<sigBase64Url>`
/// where sig = HMAC(SESSION_SECRET, "admin." + expiresAt).

const COOKIE_NAME = "xclean_admin";
const SESSION_TTL_MS = 1000 * 60 * 60 * 24 * 30; // 30 days

function getSecret(): string {
  const s = process.env.SESSION_SECRET;
  if (!s || s.length < 16) {
    throw new Error("SESSION_SECRET missing or too short. Set it in .env.local.");
  }
  return s;
}

function sign(payload: string): string {
  return crypto
    .createHmac("sha256", getSecret())
    .update(payload)
    .digest("base64url");
}

function buildToken(expiresAt: number): string {
  const payload = `admin.${expiresAt}`;
  return `${expiresAt}.${sign(payload)}`;
}

function verifyToken(token: string | undefined): boolean {
  if (!token) return false;
  const [expStr, providedSig] = token.split(".");
  if (!expStr || !providedSig) return false;
  const expiresAt = Number(expStr);
  if (!Number.isFinite(expiresAt) || expiresAt < Date.now()) return false;

  const expected = sign(`admin.${expiresAt}`);
  const a = Buffer.from(expected);
  const b = Buffer.from(providedSig);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/// Returns true if the password matches `ADMIN_PASSWORD`. Uses
/// timing-safe equality so a length leak doesn't help an attacker.
export function checkPassword(input: string): boolean {
  const expected = process.env.ADMIN_PASSWORD;
  if (!expected) return false;
  const a = Buffer.from(expected);
  const b = Buffer.from(input);
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

export async function issueSession(): Promise<void> {
  const expiresAt = Date.now() + SESSION_TTL_MS;
  const token = buildToken(expiresAt);
  (await cookies()).set(COOKIE_NAME, token, {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/",
    expires: new Date(expiresAt)
  });
}

export async function clearSession(): Promise<void> {
  (await cookies()).delete(COOKIE_NAME);
}

export async function isAdmin(): Promise<boolean> {
  const token = (await cookies()).get(COOKIE_NAME)?.value;
  return verifyToken(token);
}
