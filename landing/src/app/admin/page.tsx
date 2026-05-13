import Link from "next/link";
import { queries, type SubmissionStatus } from "@/lib/db";

const TABS: { value: SubmissionStatus | "all"; label: string }[] = [
  { value: "pending", label: "Pendientes" },
  { value: "approved", label: "Aprobadas" },
  { value: "rejected", label: "Rechazadas" },
  { value: "all", label: "Todas" }
];

export default async function Page({ searchParams }: { searchParams: Promise<{ tab?: string }> }) {
  const { tab } = await searchParams;
  const active = (TABS.find((t) => t.value === tab)?.value ?? "pending") as SubmissionStatus | "all";
  const list = queries.list(active);
  const counts = queries.countByStatus();

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-2xl font-semibold">Submissions</h1>
        <p className="mt-1 text-sm text-neutral-500">
          {counts.pending} pendientes · {counts.approved} aprobadas · {counts.rejected} rechazadas
        </p>
      </header>

      <nav className="inline-flex rounded-lg border border-neutral-800 bg-neutral-950 p-1">
        {TABS.map((t) => (
          <Link
            key={t.value}
            href={`/admin?tab=${t.value}`}
            className={
              "rounded-md px-3 py-1.5 text-sm transition " +
              (active === t.value
                ? "bg-neutral-800 text-neutral-100"
                : "text-neutral-500 hover:text-neutral-200")
            }
          >
            {t.label}
            {t.value !== "all" && (
              <span className="ml-1.5 inline-block rounded bg-neutral-900 px-1.5 text-xs text-neutral-500">
                {counts[t.value as SubmissionStatus]}
              </span>
            )}
          </Link>
        ))}
      </nav>

      {list.length === 0 ? (
        <div className="card p-10 text-center text-sm text-neutral-500">
          No hay submissions {active === "all" ? "todavía" : `en estado ${active}`}.
        </div>
      ) : (
        <div className="card overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-neutral-950 text-xs uppercase tracking-wider text-neutral-500">
              <tr>
                <th className="px-4 py-3 text-left font-medium">#</th>
                <th className="px-4 py-3 text-left font-medium">Email</th>
                <th className="px-4 py-3 text-left font-medium">Nombre</th>
                <th className="px-4 py-3 text-left font-medium">Estado</th>
                <th className="px-4 py-3 text-left font-medium">Recibido</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody className="divide-y divide-neutral-900">
              {list.map((s) => (
                <tr key={s.id} className="hover:bg-neutral-900/50">
                  <td className="px-4 py-3 font-mono text-xs text-neutral-500">
                    #{String(s.id).padStart(5, "0")}
                  </td>
                  <td className="px-4 py-3 text-neutral-200">{s.email}</td>
                  <td className="px-4 py-3 text-neutral-400">{s.name ?? "—"}</td>
                  <td className="px-4 py-3"><StatusBadge status={s.status} /></td>
                  <td className="px-4 py-3 text-xs text-neutral-500">{formatRelative(s.created_at)}</td>
                  <td className="px-4 py-3 text-right">
                    <Link href={`/admin/submissions/${s.id}`} className="btn-ghost !py-1.5 !px-3 !text-xs">
                      Ver
                    </Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function StatusBadge({ status }: { status: SubmissionStatus }) {
  const styles: Record<SubmissionStatus, string> = {
    pending:  "border-yellow-500/30 bg-yellow-500/10 text-yellow-300",
    approved: "border-emerald-500/30 bg-emerald-500/10 text-emerald-300",
    rejected: "border-red-500/30 bg-red-500/10 text-red-300"
  };
  return (
    <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-medium ${styles[status]}`}>
      {status}
    </span>
  );
}

function formatRelative(iso: string): string {
  const then = new Date(iso).getTime();
  const ms = Date.now() - then;
  if (ms < 60_000) return "hace un momento";
  if (ms < 3_600_000) return `hace ${Math.floor(ms / 60_000)} min`;
  if (ms < 86_400_000) return `hace ${Math.floor(ms / 3_600_000)} h`;
  return `hace ${Math.floor(ms / 86_400_000)} d`;
}
