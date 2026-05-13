import { NextResponse } from "next/server";
import { deactivate } from "@/lib/license-policy";

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
    const result = await deactivate({ licenseKey: key, machineId });
    return NextResponse.json(
      { ok: result.ok },
      { status: result.ok ? 200 : 404 },
    );
  } catch (err) {
    console.error("/api/license/deactivate error", err);
    return NextResponse.json({ error: "server_error" }, { status: 500 });
  }
}
