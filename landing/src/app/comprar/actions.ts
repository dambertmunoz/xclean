"use server";

import { queries } from "@/lib/db-pg";
import { saveUpload } from "@/lib/storage";

type Result = { ok: true; id: number } | { ok: false; error: string };

export async function submitPurchase(formData: FormData): Promise<Result> {
  try {
    const emailRaw = formData.get("email");
    const nameRaw = formData.get("name");
    const fileRaw = formData.get("proof");

    if (typeof emailRaw !== "string" || !emailRaw.includes("@")) {
      return { ok: false, error: "Email inválido." };
    }
    const email = emailRaw.trim().toLowerCase();
    const name =
      typeof nameRaw === "string" && nameRaw.trim().length > 0
        ? nameRaw.trim()
        : null;

    if (!(fileRaw instanceof File) || fileRaw.size === 0) {
      return { ok: false, error: "Necesitamos un screenshot del pago." };
    }

    const proofPath = await saveUpload(fileRaw);
    const submission = await queries.insertSubmission({
      email,
      name,
      proofPath,
    });
    return { ok: true, id: submission.id };
  } catch (err) {
    const message = err instanceof Error ? err.message : "Error desconocido";
    return { ok: false, error: message };
  }
}
