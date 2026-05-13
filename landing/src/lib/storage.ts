import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

const UPLOADS_DIR = path.join(process.cwd(), "data", "uploads");
const MAX_BYTES = 10 * 1024 * 1024;                 // 10 MB cap per upload
const ALLOWED_EXT = new Set([".png", ".jpg", ".jpeg", ".webp", ".heic"]);

/// Persists an uploaded payment screenshot to `data/uploads/<random>.<ext>`.
/// Returns the **relative** path (so we can store it in SQLite without
/// leaking the user's $CWD).
///
/// Validates:
///   - extension via the original filename
///   - byte length cap so a malicious client can't fill the disk
export async function saveUpload(file: File): Promise<string> {
  if (file.size > MAX_BYTES) {
    throw new Error(`Image exceeds ${MAX_BYTES / 1024 / 1024} MB`);
  }
  const ext = path.extname(file.name).toLowerCase();
  if (!ALLOWED_EXT.has(ext)) {
    throw new Error(`Unsupported extension ${ext}. Use PNG, JPG, WEBP or HEIC.`);
  }

  await fs.mkdir(UPLOADS_DIR, { recursive: true });

  const rand = crypto.randomBytes(12).toString("hex");
  const filename = `${Date.now()}-${rand}${ext}`;
  const destination = path.join(UPLOADS_DIR, filename);
  const buffer = Buffer.from(await file.arrayBuffer());
  await fs.writeFile(destination, buffer);

  // Return relative-to-uploads (consumed by the admin route, never sent to
  // the public client).
  return filename;
}

/// Reads a saved upload by filename. Throws if the name escapes the
/// uploads dir (defence against `../` traversal even though we never
/// build user-controlled names).
export async function readUpload(filename: string): Promise<{ buffer: Buffer; ext: string }> {
  const safeName = path.basename(filename);
  const ext = path.extname(safeName).toLowerCase();
  if (!ALLOWED_EXT.has(ext)) throw new Error("bad ext");

  const target = path.join(UPLOADS_DIR, safeName);
  // Confirm we resolved inside UPLOADS_DIR.
  if (!target.startsWith(UPLOADS_DIR + path.sep)) {
    throw new Error("path escape");
  }
  const buffer = await fs.readFile(target);
  return { buffer, ext };
}
