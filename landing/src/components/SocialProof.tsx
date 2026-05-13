import {
  recentSubscribers,
  todaySubscribers,
  weeklySubscribers,
} from "@/lib/social-proof";

export default function SocialProof() {
  const week = weeklySubscribers();
  const today = todaySubscribers();
  const recent = recentSubscribers(3);

  return (
    <section className="border-y border-neutral-900/70 bg-neutral-950/40 py-10">
      <div className="container-narrow">
        <div className="flex items-center justify-center gap-3 text-sm text-neutral-400">
          <span className="relative flex h-2 w-2">
            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-70" />
            <span className="relative inline-flex h-2 w-2 rounded-full bg-emerald-500" />
          </span>
          <span>
            <strong className="text-neutral-100">{week.toLocaleString("es")}</strong>{" "}
            personas recuperaron espacio esta semana
            <span className="ml-2 hidden text-emerald-400 sm:inline">
              · +{today} hoy
            </span>
          </span>
        </div>

        <ul className="mx-auto mt-6 grid max-w-3xl gap-3 sm:grid-cols-3">
          {recent.map((r, i) => (
            <li
              key={`${r.name}-${i}`}
              className="rounded-xl border border-neutral-900 bg-neutral-950 px-4 py-3"
            >
              <div className="flex items-center gap-3">
                <span
                  className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-full bg-emerald-500/10 text-sm font-semibold text-emerald-300"
                  aria-hidden="true"
                >
                  {r.name[0]}
                </span>
                <div className="min-w-0 flex-1">
                  <div className="truncate text-sm text-neutral-200">
                    {r.name}{" "}
                    <span className="text-neutral-500">· {r.city}</span>
                  </div>
                  <div className="truncate text-xs text-neutral-500">
                    compró xclean · hace {r.minutesAgo} min
                  </div>
                </div>
              </div>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
