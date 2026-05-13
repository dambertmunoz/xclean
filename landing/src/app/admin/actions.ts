"use server";

import { revalidatePath } from "next/cache";
import { queries } from "@/lib/db";
import { clearSession } from "@/lib/auth";
import { generateLicenseKey } from "@/lib/license";

export type ApproveResult = { ok: true; licenseKey: string } | { ok: false; error: string };
export type RejectResult  = { ok: true } | { ok: false; error: string };

export async function logout(): Promise<void> {
  await clearSession();
}

export async function approveSubmission(formData: FormData): Promise<ApproveResult> {
  const idRaw = formData.get("id");
  const notesRaw = formData.get("notes");
  const id = typeof idRaw === "string" ? Number(idRaw) : NaN;
  if (!Number.isFinite(id)) return { ok: false, error: "id inválido" };
  const notes = typeof notesRaw === "string" && notesRaw.trim().length > 0 ? notesRaw.trim() : null;
  const key = generateLicenseKey();
  const row = queries.approve(id, key, notes);
  if (!row) return { ok: false, error: "no se pudo aprobar (¿ya estaba aprobada?)" };
  revalidatePath("/admin");
  revalidatePath(`/admin/submissions/${id}`);
  return { ok: true, licenseKey: key };
}

export async function rejectSubmission(formData: FormData): Promise<RejectResult> {
  const idRaw = formData.get("id");
  const notesRaw = formData.get("notes");
  const id = typeof idRaw === "string" ? Number(idRaw) : NaN;
  if (!Number.isFinite(id)) return { ok: false, error: "id inválido" };
  const notes = typeof notesRaw === "string" && notesRaw.trim().length > 0 ? notesRaw.trim() : null;
  const row = queries.reject(id, notes);
  if (!row) return { ok: false, error: "no se pudo rechazar (¿no está pending?)" };
  revalidatePath("/admin");
  revalidatePath(`/admin/submissions/${id}`);
  return { ok: true };
}
