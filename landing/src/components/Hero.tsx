import Link from "next/link";

export default function Hero() {
  return (
    <section className="relative pt-20 pb-20 sm:pt-28 sm:pb-28">
      <div className="container-narrow text-center animate-rise">
        <span className="inline-flex items-center gap-2 rounded-full border border-neutral-800 bg-neutral-950 px-3 py-1 text-xs text-neutral-400">
          <span className="inline-block h-1.5 w-1.5 rounded-full bg-emerald-500" />
          macOS · 13.0+
        </span>

        <h1 className="mt-6 text-balance text-5xl font-semibold leading-[1.05] tracking-tight sm:text-7xl">
          Recuperá tu Mac.
          <br />
          <span className="text-emerald-400">Sin pagar suscripciones.</span>
        </h1>

        <p className="mx-auto mt-6 max-w-2xl text-balance text-base text-neutral-400 sm:text-lg">
          <strong className="text-neutral-200">xclean</strong> te muestra qué carpetas
          están comiéndose tu disco — caches de Docker, Ollama, node_modules de
          proyectos viejos — y las libera de un click. Pagás <strong className="text-neutral-200">$10 una vez al año</strong>, listo.
        </p>

        <div className="mt-10 flex items-center justify-center gap-3">
          <Link href="/comprar" className="btn-primary">
            Comprar — $10 / año
          </Link>
          <Link href="#features" className="btn-ghost">
            Cómo funciona
          </Link>
        </div>

        <p className="mt-6 text-xs text-neutral-500">
          Sin renovación automática · Pagás una vez, válido 365 días · Updates incluidos
        </p>

        {/* Mock window preview */}
        <div className="relative mx-auto mt-16 max-w-3xl">
          <div className="absolute -inset-x-12 -inset-y-8 -z-10 rounded-[40px] bg-gradient-to-b from-emerald-500/10 via-transparent to-transparent blur-2xl" />
          <div className="card overflow-hidden text-left shadow-2xl shadow-black/40">
            <div className="flex h-9 items-center gap-1.5 border-b border-neutral-800 bg-neutral-950 px-4">
              <span className="h-2.5 w-2.5 rounded-full bg-neutral-700" />
              <span className="h-2.5 w-2.5 rounded-full bg-neutral-700" />
              <span className="h-2.5 w-2.5 rounded-full bg-neutral-700" />
              <span className="ml-3 font-mono text-[11px] text-neutral-500">xclean menu</span>
            </div>
            <div className="grid grid-cols-1 gap-px bg-neutral-800 sm:grid-cols-[1fr_1.2fr]">
              <div className="space-y-3 bg-neutral-950 p-5">
                <div className="text-xs uppercase tracking-wider text-neutral-500">Disk pressure</div>
                <div className="flex items-baseline gap-2">
                  <span className="text-3xl font-semibold text-emerald-400">●</span>
                  <span className="text-3xl font-semibold">42 GB</span>
                  <span className="text-sm text-neutral-500">free</span>
                </div>
                <div className="font-mono text-xs text-neutral-500">
                  9% of 494 GB · ▂▃▄▄▅▅▆▆▇▆▅▅
                </div>
                <div className="rounded-md bg-red-500/10 px-3 py-2 text-xs text-red-300">
                  ⚠︎ At current rate, disk fills in 11 days
                </div>
              </div>
              <div className="space-y-2 bg-neutral-950 p-5 text-sm">
                <div className="text-xs uppercase tracking-wider text-neutral-500">Top consumers</div>
                {[
                  ["27.92 GB", "uv cache", "+2.1 GB"],
                  ["13.61 GB", "Docker Desktop", ""],
                  ["8.94 GB", "Ollama models", ""],
                  ["8.88 GB", "Gradle caches", "−0.4 GB"],
                  ["8.60 GB", "npm cache", ""]
                ].map(([size, label, delta]) => (
                  <div key={label} className="flex items-center justify-between rounded-md px-2 py-1.5 hover:bg-neutral-900">
                    <div className="flex items-center gap-3">
                      <span className="font-mono text-xs text-neutral-300">{size}</span>
                      <span className="text-neutral-200">{label}</span>
                    </div>
                    {delta && (
                      <span className={`text-xs ${delta.startsWith("+") ? "text-orange-400" : "text-emerald-400"}`}>
                        {delta}
                      </span>
                    )}
                  </div>
                ))}
                <div className="mt-2 rounded-md bg-emerald-500/10 px-3 py-2 text-xs font-semibold text-emerald-300">
                  ⚡ Reclaim ~62 GB · 7 safe actions
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
