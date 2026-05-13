"use server";

import { checkPassword, issueSession } from "@/lib/auth";

type Result = { ok: true } | { ok: false; error: string };

export async function login(formData: FormData): Promise<Result> {
  const pw = formData.get("password");
  if (typeof pw !== "string") return { ok: false, error: "Password requerido." };
  if (!checkPassword(pw)) return { ok: false, error: "Password incorrecto." };
  await issueSession();
  return { ok: true };
}
