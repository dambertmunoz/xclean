import { queries, type Activation, type License } from "./db-pg";

export type ActivationOutcome =
  | { ok: true; activation: Activation; rebound: boolean }
  | { ok: false; reason: ActivationFailureReason; activeMachineId?: string };

export type ActivationFailureReason =
  | "license_not_found"
  | "license_not_active"
  | "license_expired"
  | "machine_conflict"
  | "transfer_limit_exceeded";

const MAX_TRANSFERS_PER_30_DAYS = 2;

function isValidMachineId(id: string): boolean {
  return typeof id === "string" && id.length >= 32 && id.length <= 128;
}

export function isValidLicenseFormat(key: string): boolean {
  return /^XCL(-[A-Z2-9]{4}){4}$/.test(key);
}

async function checkLicense(
  key: string,
): Promise<{ license: License } | { failure: ActivationFailureReason }> {
  const license = await queries.getLicense(key);
  if (!license) return { failure: "license_not_found" };
  if (license.status !== "active") return { failure: "license_not_active" };
  if (new Date(license.expires_at).getTime() < Date.now()) {
    return { failure: "license_expired" };
  }
  return { license };
}

export async function activate(args: {
  licenseKey: string;
  machineId: string;
  machineLabel?: string | null;
}): Promise<ActivationOutcome> {
  if (!isValidLicenseFormat(args.licenseKey)) {
    return { ok: false, reason: "license_not_found" };
  }
  if (!isValidMachineId(args.machineId)) {
    return { ok: false, reason: "machine_conflict" };
  }

  const check = await checkLicense(args.licenseKey);
  if ("failure" in check) return { ok: false, reason: check.failure };

  const current = await queries.getActiveActivation(args.licenseKey);
  if (current) {
    if (current.machine_id === args.machineId) {
      const refreshed = await queries.heartbeatActivation(
        args.licenseKey,
        args.machineId,
      );
      return { ok: true, activation: refreshed ?? current, rebound: false };
    }
    return {
      ok: false,
      reason: "machine_conflict",
      activeMachineId: current.machine_id,
    };
  }

  const recentDeactivations = await queries.countRecentDeactivations(
    args.licenseKey,
  );
  if (recentDeactivations >= MAX_TRANSFERS_PER_30_DAYS) {
    return { ok: false, reason: "transfer_limit_exceeded" };
  }

  const created = await queries.insertActivation({
    licenseKey: args.licenseKey,
    machineId: args.machineId,
    machineLabel: args.machineLabel ?? null,
  });
  return { ok: true, activation: created, rebound: recentDeactivations > 0 };
}

export type ValidationOutcome =
  | { valid: true; expiresAt: string; lastSeenAt: string }
  | { valid: false; reason: ActivationFailureReason | "not_activated" };

export async function validate(args: {
  licenseKey: string;
  machineId: string;
}): Promise<ValidationOutcome> {
  if (!isValidLicenseFormat(args.licenseKey)) {
    return { valid: false, reason: "license_not_found" };
  }
  if (!isValidMachineId(args.machineId)) {
    return { valid: false, reason: "machine_conflict" };
  }

  const check = await checkLicense(args.licenseKey);
  if ("failure" in check) return { valid: false, reason: check.failure };

  const beat = await queries.heartbeatActivation(
    args.licenseKey,
    args.machineId,
  );
  if (!beat) return { valid: false, reason: "not_activated" };

  return {
    valid: true,
    expiresAt: check.license.expires_at,
    lastSeenAt: beat.last_seen_at,
  };
}

export async function deactivate(args: {
  licenseKey: string;
  machineId: string;
}): Promise<{ ok: boolean }> {
  if (!isValidLicenseFormat(args.licenseKey)) return { ok: false };
  if (!isValidMachineId(args.machineId)) return { ok: false };
  const row = await queries.deactivateActivation(
    args.licenseKey,
    args.machineId,
  );
  return { ok: !!row };
}
