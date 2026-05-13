import { NextResponse } from "next/server";
import { activate } from "@/lib/license-policy";

export const runtime = "edge";

type Body = {
  key?: unknown;
  machineId?: unknown;
  machineLabel?: unknown;
};

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
  const machineLabel =
    typeof body.machineLabel === "string" ? body.machineLabel.slice(0, 80) : null;

  if (!key || !machineId) {
    return NextResponse.json(
      { error: "missing_fields", required: ["key", "machineId"] },
      { status: 400 },
    );
  }

  try {
    const result = await activate({ licenseKey: key, machineId, machineLabel });
    if (result.ok) {
      return NextResponse.json({
        ok: true,
        rebound: result.rebound,
        activatedAt: result.activation.activated_at,
        lastSeenAt: result.activation.last_seen_at,
      });
    }
    const statusByReason: Record<string, number> = {
      license_not_found: 404,
      license_not_active: 403,
      license_expired: 403,
      machine_conflict: 409,
      transfer_limit_exceeded: 429,
    };
    return NextResponse.json(
      {
        ok: false,
        reason: result.reason,
        ...(result.activeMachineId
          ? { activeMachineId: result.activeMachineId }
          : {}),
      },
      { status: statusByReason[result.reason] ?? 400 },
    );
  } catch (err) {
    console.error("/api/license/activate error", err);
    return NextResponse.json({ error: "server_error" }, { status: 500 });
  }
}
