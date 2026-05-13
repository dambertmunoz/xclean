"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { submitPurchase } from "./actions";

/// Client component: handles file preview + optimistic loading state.
/// The actual server-side mutation lives in `actions.ts` and the route
/// receives the file via a FormData payload (Server Action).
export default function BuyForm() {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [preview, setPreview] = useState<string | null>(null);

  function onFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.currentTarget.files?.[0];
    if (!f) { setPreview(null); return; }
    const url = URL.createObjectURL(f);
    setPreview(url);
  }

  function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    const data = new FormData(e.currentTarget);
    startTransition(async () => {
      const result = await submitPurchase(data);
      if (result.ok) {
        router.push(`/comprar/gracias?ref=${result.id}`);
      } else {
        setError(result.error);
      }
    });
  }

  return (
    <form className="space-y-5" onSubmit={onSubmit}>
      <div>
        <label htmlFor="email" className="label">Email</label>
        <input
          id="email" name="email" type="email" required autoComplete="email"
          className="input" placeholder="tu@email.com"
        />
        <p className="mt-1.5 text-xs text-neutral-500">Vamos a enviarte la license a este email.</p>
      </div>

      <div>
        <label htmlFor="name" className="label">Nombre <span className="text-neutral-600">(opcional)</span></label>
        <input
          id="name" name="name" type="text" autoComplete="name"
          className="input" placeholder="Como te llamamos en el recibo"
        />
      </div>

      <div>
        <label htmlFor="proof" className="label">Screenshot del pago</label>
        <input
          id="proof" name="proof" type="file" required
          accept="image/png,image/jpeg,image/webp,image/heic"
          className="input cursor-pointer file:mr-3 file:rounded-md file:border-0 file:bg-neutral-800 file:px-3 file:py-1.5 file:text-xs file:font-medium file:text-neutral-200 hover:file:bg-neutral-700"
          onChange={onFileChange}
        />
        <p className="mt-1.5 text-xs text-neutral-500">PNG, JPG, WEBP o HEIC. Máx 10 MB.</p>

        {preview && (
          <div className="mt-3 overflow-hidden rounded-lg border border-neutral-800">
            {/* preview is a blob URL, safe to render */}
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={preview} alt="preview" className="max-h-64 w-full object-contain bg-neutral-950" />
          </div>
        )}
      </div>

      {error && (
        <div className="rounded-md border border-red-500/30 bg-red-500/10 px-3 py-2 text-sm text-red-300">
          {error}
        </div>
      )}

      <button type="submit" disabled={isPending} className="btn-primary w-full disabled:opacity-60">
        {isPending ? "Enviando…" : "Enviar para validación"}
      </button>
    </form>
  );
}
