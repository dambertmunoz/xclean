import { NextRequest, NextResponse } from "next/server";
import { readUpload } from "@/lib/storage";

const MIME: Record<string, string> = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp",
  ".heic": "image/heic"
};

/// Streams a payment screenshot from disk. Middleware already enforces
/// admin auth on /api/admin/*, so reaching this handler implies the
/// caller is authenticated.
export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ file: string }> }
) {
  const { file } = await params;
  try {
    const { buffer, ext } = await readUpload(file);
    const ab = new ArrayBuffer(buffer.byteLength);
    new Uint8Array(ab).set(buffer);
    return new NextResponse(ab, {
      headers: {
        "Content-Type": MIME[ext] ?? "application/octet-stream",
        "Cache-Control": "private, no-store"
      }
    });
  } catch {
    return new NextResponse("not found", { status: 404 });
  }
}
