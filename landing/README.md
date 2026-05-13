# xclean — landing & purchase flow

Minimalist Next.js landing page for the xclean macOS app with a manual-validation
buy flow (user pays via QR, uploads screenshot, admin approves).

## Stack

- **Next.js 15** (App Router, Server Components, TypeScript)
- **Tailwind CSS v4**
- **better-sqlite3** — single-file DB at `data/xclean.db`
- **Local file storage** — uploaded screenshots in `data/uploads/`
- **Cookie + HMAC-SHA256** admin session (no auth library)
- Zero external services for the MVP

## Quickstart

```sh
cd landing
cp .env.example .env.local
# edit ADMIN_PASSWORD + SESSION_SECRET

npm install
npm run dev
# → http://localhost:3000
# Admin → http://localhost:3000/admin/login
```

## Replace the payment QR

Drop your real QR image at `public/qr.png` (square, transparent or white bg).
The landing also reads `PAYMENT_LABEL` from `.env.local` to render the
"pay via" string above it.

## Deployment

Two practical paths:

1. **Self-host on a VPS / Fly.io / Railway** — keeps better-sqlite3 + local
   uploads working as-is. Recommended for the MVP.

2. **Vercel** — Vercel filesystems are read-only, so swap the storage layer
   to Vercel Blob (or Cloudflare R2 / S3) and use a managed Postgres
   (Vercel Postgres, Supabase, Neon). Only `src/lib/db.ts` and
   `src/lib/storage.ts` need to change.

## Data layout

```
data/
  xclean.db                 ← SQLite (single file)
  uploads/                  ← payment screenshots (one file per submission)
```

Submissions table:

| column        | type    | notes |
| ---           | ---     | ---   |
| id            | INTEGER | PK |
| email         | TEXT    | required |
| name          | TEXT    | optional |
| proof_path    | TEXT    | relative path under `data/uploads/` |
| status        | TEXT    | `pending` / `approved` / `rejected` |
| license_key   | TEXT    | issued on approve |
| notes         | TEXT    | admin notes |
| created_at    | TEXT    | ISO 8601 |
| reviewed_at   | TEXT    | ISO 8601 once approved/rejected |

## License keys

Generated as `XCL-XXXX-XXXX-XXXX-XXXX` (base32 of 16 random bytes) at the
moment of approval. The admin copies it from the dashboard and emails it
manually for now — wire SMTP or Resend later if you want auto-send.
