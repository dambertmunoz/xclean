import Link from "next/link";
import { notFound } from "next/navigation";
import { queries } from "@/lib/db-pg";
import DecisionPanel from "./DecisionPanel";

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const submissionId = Number(id);
  if (!Number.isFinite(submissionId)) notFound();

  const submission = await queries.getSubmission(submissionId);
  if (!submission) notFound();

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <Link href="/admin" className="text-sm text-neutral-400 hover:text-neutral-100">
          ← volver
        </Link>
        <div className="font-mono text-xs text-neutral-500">
          #{String(submission.id).padStart(5, "0")}
        </div>
      </div>

      <div className="grid gap-6 lg:grid-cols-[1.4fr_1fr]">
        <div className="card overflow-hidden">
          <div className="border-b border-neutral-900 px-5 py-3 text-xs uppercase tracking-wider text-neutral-500">
            Screenshot del pago
          </div>
          <div className="bg-black p-4">
            {/* served by the protected admin route — never linked publicly */}
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={`/api/admin/uploads/${encodeURIComponent(submission.proof_path)}`}
              alt="comprobante"
              className="mx-auto max-h-[70vh] w-auto rounded-md"
            />
          </div>
        </div>

        <div className="space-y-4">
          <div className="card p-5 space-y-3">
            <div>
              <div className="label">Email</div>
              <div className="text-sm text-neutral-100">{submission.email}</div>
            </div>
            <div>
              <div className="label">Nombre</div>
              <div className="text-sm text-neutral-300">{submission.name ?? "—"}</div>
            </div>
            <div>
              <div className="label">Recibido</div>
              <div className="text-sm text-neutral-300">{new Date(submission.created_at).toLocaleString()}</div>
            </div>
            <div>
              <div className="label">Estado</div>
              <div className="text-sm">
                <span className={statusClass(submission.status)}>{submission.status}</span>
              </div>
            </div>
            {submission.license_key && (
              <div>
                <div className="label">License key</div>
                <div className="rounded border border-neutral-800 bg-neutral-950 px-3 py-2 font-mono text-sm text-emerald-300">
                  {submission.license_key}
                </div>
              </div>
            )}
            {submission.notes && (
              <div>
                <div className="label">Notas</div>
                <div className="rounded border border-neutral-800 bg-neutral-950 px-3 py-2 text-sm text-neutral-400">
                  {submission.notes}
                </div>
              </div>
            )}
          </div>

          {submission.status === "pending" && (
            <DecisionPanel id={submission.id} email={submission.email} />
          )}
        </div>
      </div>
    </div>
  );
}

function statusClass(s: string): string {
  if (s === "pending") return "inline-flex rounded-full border border-yellow-500/30 bg-yellow-500/10 px-2 py-0.5 text-xs text-yellow-300";
  if (s === "approved") return "inline-flex rounded-full border border-emerald-500/30 bg-emerald-500/10 px-2 py-0.5 text-xs text-emerald-300";
  return "inline-flex rounded-full border border-red-500/30 bg-red-500/10 px-2 py-0.5 text-xs text-red-300";
}
