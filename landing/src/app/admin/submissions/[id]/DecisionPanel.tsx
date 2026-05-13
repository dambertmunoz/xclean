"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { approveSubmission, rejectSubmission } from "@/app/admin/actions";

export default function DecisionPanel({ id, email }: { id: number; email: string }) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [notes, setNotes] = useState("");
  const [issued, setIssued] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  function approve() {
    setError(null);
    const data = new FormData();
    data.set("id", String(id));
    if (notes) data.set("notes", notes);
    startTransition(async () => {
      const res = await approveSubmission(data);
      if (res.ok && res.licenseKey) {
        setIssued(res.licenseKey);
        router.refresh();
      } else if (!res.ok) {
        setError(res.error);
      }
    });
  }

  function reject() {
    setError(null);
    if (!confirm("Rechazar esta submission?")) return;
    const data = new FormData();
    data.set("id", String(id));
    if (notes) data.set("notes", notes);
    startTransition(async () => {
      const res = await rejectSubmission(data);
      if (!res.ok) setError(res.error);
      else router.refresh();
    });
  }

  function copyKey() {
    if (issued) navigator.clipboard.writeText(issued);
  }

  function copyEmailBody() {
    if (!issued) return;
    const body = `Hola!\n\nGracias por tu compra de xclean. Acá va tu license key:\n\n${issued}\n\nPegala en xclean → Preferences → License. Vale por 365 días.\n\nCualquier cosa, escribime.\n\n— dev@wasyra.com`;
    navigator.clipboard.writeText(body);
  }

  return (
    <div className="card p-5 space-y-4">
      <div>
        <div className="label">Notas (opcional)</div>
        <textarea
          rows={2}
          value={notes}
          onChange={(e) => setNotes(e.currentTarget.value)}
          className="input resize-none"
          placeholder="Comentario interno o motivo de rechazo"
        />
      </div>
      {error && (
        <div className="rounded-md border border-red-500/30 bg-red-500/10 px-3 py-2 text-sm text-red-300">
          {error}
        </div>
      )}

      {issued ? (
        <div className="space-y-3 rounded-md border border-emerald-500/30 bg-emerald-500/10 p-4">
          <div className="text-sm font-medium text-emerald-300">
            ✓ Aprobada. License emitida:
          </div>
          <div className="rounded bg-neutral-950 px-3 py-2 font-mono text-sm text-emerald-300">
            {issued}
          </div>
          <p className="text-xs text-neutral-400">
            Enviá esto a <span className="font-medium text-neutral-200">{email}</span>.
          </p>
          <div className="flex flex-wrap gap-2">
            <button type="button" onClick={copyKey} className="btn-ghost !py-2 !px-3 !text-xs">
              Copiar key
            </button>
            <button type="button" onClick={copyEmailBody} className="btn-ghost !py-2 !px-3 !text-xs">
              Copiar email template
            </button>
            <a
              href={`mailto:${encodeURIComponent(email)}?subject=${encodeURIComponent("xclean — tu license key")}&body=${encodeURIComponent(`Hola!\n\nGracias por tu compra de xclean. Acá va tu license key:\n\n${issued}\n\nPegala en xclean → Preferences → License. Vale por 365 días.\n\n— dev@wasyra.com`)}`}
              className="btn-primary !py-2 !px-3 !text-xs"
            >
              Abrir Mail
            </a>
          </div>
        </div>
      ) : (
        <div className="flex flex-wrap gap-2">
          <button type="button" onClick={approve} disabled={isPending} className="btn-primary disabled:opacity-60">
            {isPending ? "…" : "Aprobar + emitir license"}
          </button>
          <button type="button" onClick={reject} disabled={isPending} className="btn-ghost text-red-300 disabled:opacity-60">
            Rechazar
          </button>
        </div>
      )}
    </div>
  );
}
