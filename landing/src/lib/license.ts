import crypto from "node:crypto";

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no I/O/0/1 to avoid OCR pain

/// Generates a license key of the form `XCL-XXXX-XXXX-XXXX-XXXX` (4 groups
/// of 4 chars after the prefix). 16 alphanumeric chars from a 32-letter
/// alphabet → ~80 bits of entropy. Collisions are negligible.
export function generateLicenseKey(): string {
  const bytes = crypto.randomBytes(16);
  const chars: string[] = [];
  for (const b of bytes) chars.push(ALPHABET[b % ALPHABET.length]);
  return [
    "XCL",
    chars.slice(0, 4).join(""),
    chars.slice(4, 8).join(""),
    chars.slice(8, 12).join(""),
    chars.slice(12, 16).join("")
  ].join("-");
}
