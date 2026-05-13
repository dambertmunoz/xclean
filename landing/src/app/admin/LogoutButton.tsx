"use client";

import { useRouter } from "next/navigation";
import { useTransition } from "react";
import { logout } from "./actions";

export default function LogoutButton() {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  return (
    <button
      type="button"
      disabled={isPending}
      className="rounded-md border border-neutral-800 px-3 py-1.5 text-xs text-neutral-400 hover:border-neutral-700 hover:text-neutral-200 disabled:opacity-60"
      onClick={() => {
        startTransition(async () => {
          await logout();
          router.push("/admin/login");
          router.refresh();
        });
      }}
    >
      {isPending ? "…" : "Logout"}
    </button>
  );
}
