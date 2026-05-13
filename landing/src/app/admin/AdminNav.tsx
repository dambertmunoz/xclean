import Link from "next/link";
import LogoutButton from "./LogoutButton";

export default function AdminNav() {
  return (
    <header className="border-b border-neutral-900 bg-neutral-950">
      <div className="container-narrow flex h-14 items-center justify-between">
        <Link href="/admin" className="flex items-center gap-2 text-sm font-semibold">
          <span className="inline-block h-2 w-2 rounded-full bg-emerald-500" />
          xclean · admin
        </Link>
        <div className="flex items-center gap-2 text-sm">
          <Link href="/admin" className="px-3 py-1.5 text-neutral-300 hover:text-neutral-100">
            Submissions
          </Link>
          <Link href="/" className="px-3 py-1.5 text-neutral-500 hover:text-neutral-100">
            Site ↗
          </Link>
          <LogoutButton />
        </div>
      </div>
    </header>
  );
}
