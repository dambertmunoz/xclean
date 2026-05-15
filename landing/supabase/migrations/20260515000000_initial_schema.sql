-- xclean initial schema.
--
-- Authoritative declaration of the three tables the landing + Edge
-- API routes assume. Run via `supabase db push`.
--
-- Mirrors the lazy CREATE TABLE IF NOT EXISTS that db-pg.ts also issues
-- on first request — kept in sync so a brand-new Supabase project is
-- usable without the lazy bootstrap ever running, and so anyone can read
-- the schema from a single file instead of grepping queries.

CREATE TABLE IF NOT EXISTS submissions (
  id          BIGSERIAL PRIMARY KEY,
  email       TEXT NOT NULL,
  name        TEXT,
  proof_path  TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'pending'
              CHECK (status IN ('pending', 'approved', 'rejected')),
  license_key TEXT,
  notes       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_submissions_status     ON submissions(status);
CREATE INDEX IF NOT EXISTS idx_submissions_created_at ON submissions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_submissions_email      ON submissions(email);

CREATE TABLE IF NOT EXISTS licenses (
  key         TEXT PRIMARY KEY,
  email       TEXT NOT NULL,
  plan        TEXT NOT NULL DEFAULT 'annual',
  status      TEXT NOT NULL DEFAULT 'active'
              CHECK (status IN ('active', 'revoked', 'expired')),
  issued_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at  TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_licenses_email  ON licenses(email);
CREATE INDEX IF NOT EXISTS idx_licenses_status ON licenses(status);

CREATE TABLE IF NOT EXISTS activations (
  id              BIGSERIAL PRIMARY KEY,
  license_key     TEXT NOT NULL REFERENCES licenses(key) ON DELETE CASCADE,
  machine_id      TEXT NOT NULL,
  machine_label   TEXT,
  activated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deactivated_at  TIMESTAMPTZ
);

-- DB-enforced "one active activation per license". The partial index
-- means INSERTs racing each other can't both succeed.
CREATE UNIQUE INDEX IF NOT EXISTS activations_one_active
  ON activations (license_key)
  WHERE deactivated_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_activations_machine ON activations(machine_id);
