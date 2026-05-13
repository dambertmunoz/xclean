import { neon, neonConfig, type NeonQueryFunction } from "@neondatabase/serverless";

neonConfig.fetchConnectionCache = true;

let sqlInstance: NeonQueryFunction<false, false> | null = null;
let schemaReady: Promise<void> | null = null;

function getSql(): NeonQueryFunction<false, false> {
  if (sqlInstance) return sqlInstance;
  const url =
    process.env.POSTGRES_URL ??
    process.env.DATABASE_URL ??
    process.env.POSTGRES_PRISMA_URL;
  if (!url) {
    throw new Error(
      "POSTGRES_URL not set. Provision Vercel Postgres at https://vercel.com/dashboard → Storage → Create.",
    );
  }
  sqlInstance = neon(url);
  return sqlInstance;
}

async function ensureSchema(): Promise<void> {
  if (schemaReady) return schemaReady;
  schemaReady = (async () => {
    const sql = getSql();
    await sql`
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
      )
    `;
    await sql`CREATE INDEX IF NOT EXISTS idx_submissions_status ON submissions(status)`;
    await sql`CREATE INDEX IF NOT EXISTS idx_submissions_created_at ON submissions(created_at DESC)`;
    await sql`CREATE INDEX IF NOT EXISTS idx_submissions_email ON submissions(email)`;

    await sql`
      CREATE TABLE IF NOT EXISTS licenses (
        key         TEXT PRIMARY KEY,
        email       TEXT NOT NULL,
        plan        TEXT NOT NULL DEFAULT 'annual',
        status      TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'revoked', 'expired')),
        issued_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        expires_at  TIMESTAMPTZ NOT NULL
      )
    `;
    await sql`CREATE INDEX IF NOT EXISTS idx_licenses_email ON licenses(email)`;
    await sql`CREATE INDEX IF NOT EXISTS idx_licenses_status ON licenses(status)`;

    await sql`
      CREATE TABLE IF NOT EXISTS activations (
        id              BIGSERIAL PRIMARY KEY,
        license_key     TEXT NOT NULL REFERENCES licenses(key) ON DELETE CASCADE,
        machine_id      TEXT NOT NULL,
        machine_label   TEXT,
        activated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deactivated_at  TIMESTAMPTZ
      )
    `;
    await sql`
      CREATE UNIQUE INDEX IF NOT EXISTS activations_one_active
        ON activations (license_key)
        WHERE deactivated_at IS NULL
    `;
    await sql`CREATE INDEX IF NOT EXISTS idx_activations_machine ON activations(machine_id)`;
  })().catch((e) => {
    schemaReady = null;
    throw e;
  });
  return schemaReady;
}

export type SubmissionStatus = "pending" | "approved" | "rejected";

export interface Submission {
  id: number;
  email: string;
  name: string | null;
  proof_path: string;
  status: SubmissionStatus;
  license_key: string | null;
  notes: string | null;
  created_at: string;
  reviewed_at: string | null;
}

export interface License {
  key: string;
  email: string;
  plan: string;
  status: "active" | "revoked" | "expired";
  issued_at: string;
  expires_at: string;
}

export interface Activation {
  id: number;
  license_key: string;
  machine_id: string;
  machine_label: string | null;
  activated_at: string;
  last_seen_at: string;
  deactivated_at: string | null;
}

function rowToSubmission(r: Record<string, unknown>): Submission {
  return {
    id: Number(r.id),
    email: String(r.email),
    name: r.name == null ? null : String(r.name),
    proof_path: String(r.proof_path),
    status: String(r.status) as SubmissionStatus,
    license_key: r.license_key == null ? null : String(r.license_key),
    notes: r.notes == null ? null : String(r.notes),
    created_at:
      r.created_at instanceof Date
        ? r.created_at.toISOString()
        : String(r.created_at),
    reviewed_at:
      r.reviewed_at == null
        ? null
        : r.reviewed_at instanceof Date
          ? r.reviewed_at.toISOString()
          : String(r.reviewed_at),
  };
}

function rowToLicense(r: Record<string, unknown>): License {
  return {
    key: String(r.key),
    email: String(r.email),
    plan: String(r.plan),
    status: String(r.status) as License["status"],
    issued_at:
      r.issued_at instanceof Date
        ? r.issued_at.toISOString()
        : String(r.issued_at),
    expires_at:
      r.expires_at instanceof Date
        ? r.expires_at.toISOString()
        : String(r.expires_at),
  };
}

function rowToActivation(r: Record<string, unknown>): Activation {
  return {
    id: Number(r.id),
    license_key: String(r.license_key),
    machine_id: String(r.machine_id),
    machine_label: r.machine_label == null ? null : String(r.machine_label),
    activated_at:
      r.activated_at instanceof Date
        ? r.activated_at.toISOString()
        : String(r.activated_at),
    last_seen_at:
      r.last_seen_at instanceof Date
        ? r.last_seen_at.toISOString()
        : String(r.last_seen_at),
    deactivated_at:
      r.deactivated_at == null
        ? null
        : r.deactivated_at instanceof Date
          ? r.deactivated_at.toISOString()
          : String(r.deactivated_at),
  };
}

export const queries = {
  async insertSubmission(args: {
    email: string;
    name: string | null;
    proofPath: string;
  }): Promise<Submission> {
    await ensureSchema();
    const sql = getSql();
    const rows = (await sql`
      INSERT INTO submissions (email, name, proof_path)
      VALUES (${args.email}, ${args.name}, ${args.proofPath})
      RETURNING *
    `) as Record<string, unknown>[];
    return rowToSubmission(rows[0]);
  },

  async listSubmissions(
    filter?: SubmissionStatus | "all",
  ): Promise<Submission[]> {
    await ensureSchema();
    const sql = getSql();
    const rows = (!filter || filter === "all"
      ? await sql`SELECT * FROM submissions ORDER BY created_at DESC`
      : await sql`SELECT * FROM submissions WHERE status = ${filter} ORDER BY created_at DESC`) as Record<
      string,
      unknown
    >[];
    return rows.map(rowToSubmission);
  },

  async getSubmission(id: number): Promise<Submission | undefined> {
    await ensureSchema();
    const sql = getSql();
    const rows = (await sql`
      SELECT * FROM submissions WHERE id = ${id}
    `) as Record<string, unknown>[];
    return rows[0] ? rowToSubmission(rows[0]) : undefined;
  },

  async approveSubmission(
    id: number,
    licenseKey: string,
    notes?: string | null,
  ): Promise<Submission | undefined> {
    await ensureSchema();
    const sql = getSql();
    const rows = (await sql`
      UPDATE submissions
      SET status = 'approved',
          license_key = ${licenseKey},
          notes = COALESCE(${notes ?? null}, notes),
          reviewed_at = NOW()
      WHERE id = ${id} AND status != 'approved'
      RETURNING *
    `) as Record<string, unknown>[];
    return rows[0] ? rowToSubmission(rows[0]) : undefined;
  },

  async rejectSubmission(
    id: number,
    notes?: string | null,
  ): Promise<Submission | undefined> {
    await ensureSchema();
    const sql = getSql();
    const rows = (await sql`
      UPDATE submissions
      SET status = 'rejected',
          notes = COALESCE(${notes ?? null}, notes),
          reviewed_at = NOW()
      WHERE id = ${id} AND status = 'pending'
      RETURNING *
    `) as Record<string, unknown>[];
    return rows[0] ? rowToSubmission(rows[0]) : undefined;
  },

  async countByStatus(): Promise<Record<SubmissionStatus, number>> {
    await ensureSchema();
    const sql = getSql();
    const rows = (await sql`
      SELECT status, COUNT(*)::int AS n FROM submissions GROUP BY status
    `) as { status: string; n: number }[];
    const out: Record<SubmissionStatus, number> = {
      pending: 0,
      approved: 0,
      rejected: 0,
    };
    for (const r of rows) out[r.status as SubmissionStatus] = Number(r.n);
    return out;
  },

  async upsertLicense(args: {
    key: string;
    email: string;
    plan?: string;
    expiresAt: Date;
  }): Promise<License> {
    await ensureSchema();
    const sql = getSql();
    const rows = (await sql`
      INSERT INTO licenses (key, email, plan, expires_at)
      VALUES (${args.key}, ${args.email}, ${args.plan ?? "annual"}, ${args.expiresAt.toISOString()})
      ON CONFLICT (key) DO UPDATE
        SET email = EXCLUDED.email,
            plan = EXCLUDED.plan,
            expires_at = EXCLUDED.expires_at
      RETURNING *
    `) as Record<string, unknown>[];
    return rowToLicense(rows[0]);
  },

  async getLicense(key: string): Promise<License | undefined> {
    await ensureSchema();
    const sql = getSql();
    const rows = (await sql`
      SELECT * FROM licenses WHERE key = ${key}
    `) as Record<string, unknown>[];
    return rows[0] ? rowToLicense(rows[0]) : undefined;
  },

  async getActiveActivation(
    licenseKey: string,
  ): Promise<Activation | undefined> {
    await ensureSchema();
    const sql = getSql();
    const rows = (await sql`
      SELECT * FROM activations
      WHERE license_key = ${licenseKey} AND deactivated_at IS NULL
      LIMIT 1
    `) as Record<string, unknown>[];
    return rows[0] ? rowToActivation(rows[0]) : undefined;
  },

  async countRecentDeactivations(
    licenseKey: string,
    sinceDays = 30,
  ): Promise<number> {
    await ensureSchema();
    const sql = getSql();
    const rows = (await sql`
      SELECT COUNT(*)::int AS n FROM activations
      WHERE license_key = ${licenseKey}
        AND deactivated_at IS NOT NULL
        AND deactivated_at > NOW() - (${sinceDays}::int * INTERVAL '1 day')
    `) as { n: number }[];
    return Number(rows[0]?.n ?? 0);
  },

  async insertActivation(args: {
    licenseKey: string;
    machineId: string;
    machineLabel: string | null;
  }): Promise<Activation> {
    await ensureSchema();
    const sql = getSql();
    const rows = (await sql`
      INSERT INTO activations (license_key, machine_id, machine_label)
      VALUES (${args.licenseKey}, ${args.machineId}, ${args.machineLabel})
      RETURNING *
    `) as Record<string, unknown>[];
    return rowToActivation(rows[0]);
  },

  async heartbeatActivation(
    licenseKey: string,
    machineId: string,
  ): Promise<Activation | undefined> {
    await ensureSchema();
    const sql = getSql();
    const rows = (await sql`
      UPDATE activations
      SET last_seen_at = NOW()
      WHERE license_key = ${licenseKey}
        AND machine_id = ${machineId}
        AND deactivated_at IS NULL
      RETURNING *
    `) as Record<string, unknown>[];
    return rows[0] ? rowToActivation(rows[0]) : undefined;
  },

  async deactivateActivation(
    licenseKey: string,
    machineId: string,
  ): Promise<Activation | undefined> {
    await ensureSchema();
    const sql = getSql();
    const rows = (await sql`
      UPDATE activations
      SET deactivated_at = NOW()
      WHERE license_key = ${licenseKey}
        AND machine_id = ${machineId}
        AND deactivated_at IS NULL
      RETURNING *
    `) as Record<string, unknown>[];
    return rows[0] ? rowToActivation(rows[0]) : undefined;
  },
};
