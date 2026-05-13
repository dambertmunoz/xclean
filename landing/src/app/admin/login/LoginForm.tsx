"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { login } from "./actions";

export default function LoginForm() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    const data = new FormData(e.currentTarget);
    startTransition(async () => {
      const res = await login(data);
      if (res.ok) {
        router.push("/admin");
        router.refresh();
      } else {
        setError(res.error);
      }
    });
  }

  return (
    <form onSubmit={onSubmit} className="space-y-4">
      <div>
        <label htmlFor="password" className="label">Password</label>
        <input
          id="password" name="password" type="password" autoFocus required
          className="input" placeholder="••••••••"
        />
      </div>
      {error && (
        <div className="rounded-md border border-red-500/30 bg-red-500/10 px-3 py-2 text-sm text-red-300">
          {error}
        </div>
      )}
      <button type="submit" disabled={isPending} className="btn-primary w-full disabled:opacity-60">
        {isPending ? "Verificando…" : "Entrar"}
      </button>
    </form>
  );
}
