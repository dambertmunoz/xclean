import { NextRequest, NextResponse } from "next/server";
import crypto from "node:crypto";

// We can't import @/lib/auth here because Next's Edge middleware can't use
// Node crypto. So we duplicate the verifier in a Node-runtime middleware.
// The lift is tiny — same HMAC, same cookie name.

const COOKIE_NAME = "xclean_admin";

function verify(token: string | undefined, secret: string): boolean {
  if (!token) return false;
  const [expStr, providedSig] = token.split(".");
  if (!expStr || !providedSig) return false;
  const expiresAt = Number(expStr);
  if (!Number.isFinite(expiresAt) || expiresAt < Date.now()) return false;
  const expected = crypto
    .createHmac("sha256", secret)
    .update(`admin.${expiresAt}`)
    .digest("base64url");
  const a = Buffer.from(expected);
  const b = Buffer.from(providedSig);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;
  // Login + login API are public.
  if (pathname === "/admin/login" || pathname.startsWith("/api/admin/login")) {
    return NextResponse.next();
  }
  const secret = process.env.SESSION_SECRET ?? "";
  const token = req.cookies.get(COOKIE_NAME)?.value;
  if (!secret || !verify(token, secret)) {
    const url = req.nextUrl.clone();
    url.pathname = "/admin/login";
    return NextResponse.redirect(url);
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/admin/:path*", "/api/admin/:path*"],
  runtime: "nodejs"
};
