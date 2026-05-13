import { NextResponse } from "next/server";
import { validate } from "@/lib/license-policy";

export const runtime = "edge";

type Body = { key?: unknown; machineId?: unknown };

export async function POST(req: Request) {
  let body: Body;
  try {
    body = (await req.json()) as Body;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const key = typeof body.key === "string" ? body.key.trim() : "";
  const machineId =
    typeof body.machineId === "string" ? body.machineId.trim() : "";

  if (!key || !machineId) {
    return NextResponse.json(
      { error: "missing_fields", required: ["key", "machineId"] },
      { status: 400 },
    );
  }

  try {
    const result = await validate({ licenseKey: key, machineId });
    if (result.valid) {
      return NextResponse.json({
        valid: true,
        expiresAt: result.expiresAt,
        lastSeenAt: result.lastSeenAt,
      });
    }
    const statusByReason: Record<string, number> = {
      license_not_found: 404,
      license_not_active: 403,
      license_expired: 403,
      machine_conflict: 409,
      not_activated: 404,
      transfer_limit_exceeded: 429,
    };
    return NextResponse.json(
      { valid: false, reason: result.reason },
      { status: statusByReason[result.reason] ?? 400 },
    );
  } catch (err) {
    console.error("/api/license/validate error", err);
    return NextResponse.json({ error: "server_error" }, { status: 500 });
  }
}
