import { DatabaseSync } from "node:sqlite";
import path from "node:path";
import fs from "node:fs";

/// Singleton DB connection backed by Node's built-in `node:sqlite`
/// (synchronous API, no native compile, no extra dependency).
/// Schema is applied on first open so the file initialises itself.
let dbInstance: DatabaseSync | null = null;

export function getDb(): DatabaseSync {
  if (dbInstance) return dbInstance;

  const dataDir = path.join(process.cwd(), "data");
  if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });

  const dbPath = path.join(dataDir, "xclean.db");
  const db = new DatabaseSync(dbPath);
  db.exec("PRAGMA journal_mode = WAL");      // concurrent reads while admin writes
  db.exec("PRAGMA foreign_keys = ON");

  db.exec(`
    CREATE TABLE IF NOT EXISTS submissions (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      email       TEXT NOT NULL,
      name        TEXT,
      proof_path  TEXT NOT NULL,
      status      TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'rejected')),
      license_key TEXT,
      notes       TEXT,
      created_at  TEXT NOT NULL,
      reviewed_at TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_submissions_status     ON submissions(status);
    CREATE INDEX IF NOT EXISTS idx_submissions_created_at ON submissions(created_at);
    CREATE INDEX IF NOT EXISTS idx_submissions_email      ON submissions(email);
  `);

  dbInstance = db;
  return db;
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

/// Coerce a node:sqlite row (which uses `string | number | bigint | null`
/// for all columns) into our strict `Submission` shape.
function asSubmission(row: unknown): Submission | undefined {
  if (!row || typeof row !== "object") return undefined;
  const r = row as Record<string, unknown>;
  return {
    id: Number(r.id),
    email: String(r.email),
    name: r.name == null ? null : String(r.name),
    proof_path: String(r.proof_path),
    status: String(r.status) as SubmissionStatus,
    license_key: r.license_key == null ? null : String(r.license_key),
    notes: r.notes == null ? null : String(r.notes),
    created_at: String(r.created_at),
    reviewed_at: r.reviewed_at == null ? null : String(r.reviewed_at)
  };
}

export const queries = {
  insert(args: { email: string; name: string | null; proofPath: string }): Submission {
    const db = getDb();
    const stmt = db.prepare(`
      INSERT INTO submissions (email, name, proof_path, created_at)
      VALUES (?, ?, ?, ?)
      RETURNING *
    `);
    const row = stmt.get(args.email, args.name, args.proofPath, new Date().toISOString());
    return asSubmission(row)!;
  },

  list(filter?: SubmissionStatus | "all"): Submission[] {
    const db = getDb();
    const rows = (!filter || filter === "all")
      ? db.prepare(`SELECT * FROM submissions ORDER BY created_at DESC`).all()
      : db.prepare(`SELECT * FROM submissions WHERE status = ? ORDER BY created_at DESC`).all(filter);
    return rows.map((r) => asSubmission(r)!);
  },

  get(id: number): Submission | undefined {
    const row = getDb().prepare(`SELECT * FROM submissions WHERE id = ?`).get(id);
    return asSubmission(row);
  },

  approve(id: number, licenseKey: string, notes?: string | null): Submission | undefined {
    const db = getDb();
    const row = db.prepare(`
      UPDATE submissions
      SET status = 'approved',
          license_key = ?,
          notes = COALESCE(?, notes),
          reviewed_at = datetime('now')
      WHERE id = ? AND status != 'approved'
      RETURNING *
    `).get(licenseKey, notes ?? null, id);
    return asSubmission(row);
  },

  reject(id: number, notes?: string | null): Submission | undefined {
    const db = getDb();
    const row = db.prepare(`
      UPDATE submissions
      SET status = 'rejected',
          notes = COALESCE(?, notes),
          reviewed_at = datetime('now')
      WHERE id = ? AND status = 'pending'
      RETURNING *
    `).get(notes ?? null, id);
    return asSubmission(row);
  },

  countByStatus(): Record<SubmissionStatus, number> {
    const db = getDb();
    const rows = db.prepare(`SELECT status, COUNT(*) as n FROM submissions GROUP BY status`).all();
    const out: Record<SubmissionStatus, number> = { pending: 0, approved: 0, rejected: 0 };
    for (const r of rows) {
      const o = r as { status: string; n: number };
      out[o.status as SubmissionStatus] = Number(o.n);
    }
    return out;
  }
};
