import Link from "next/link";

export default function Pricing() {
  const price = process.env.PRICE_USD ?? "10";

  return (
    <section id="pricing" className="py-20 sm:py-28">
      <div className="container-narrow">
        <div className="mb-12 text-center">
          <p className="mb-3 text-sm font-medium uppercase tracking-wider text-emerald-400">Precio</p>
          <h2 className="text-3xl font-semibold tracking-tight sm:text-4xl">
            Una pinta de cerveza al año.
          </h2>
          <p className="mt-3 text-neutral-400">Sin suscripción. Sin auto-renovación. Sin trampas.</p>
        </div>

        <div className="mx-auto max-w-md">
          <div className="relative overflow-hidden card p-8">
            <div className="absolute -right-12 -top-12 h-44 w-44 rounded-full bg-emerald-500/10 blur-3xl" />
            <div className="relative">
              <p className="text-xs font-medium uppercase tracking-wider text-emerald-400">xclean · anual</p>
              <div className="mt-3 flex items-baseline gap-1.5">
                <span className="text-5xl font-bold tracking-tight">${price}</span>
                <span className="text-sm text-neutral-500">USD / año</span>
              </div>
              <ul className="mt-7 space-y-3 text-sm text-neutral-300">
                {[
                  "App nativa para macOS 13+",
                  "Menu bar + CLI incluidos",
                  "Bulk reclaim + auto-schedule",
                  "Project scanner + custom paths",
                  "Updates incluidos por 365 días",
                  "Sin renovación automática"
                ].map((f) => (
                  <li key={f} className="flex items-start gap-2.5">
                    <svg className="mt-0.5 h-4 w-4 flex-shrink-0 text-emerald-400" viewBox="0 0 20 20" fill="currentColor">
                      <path fillRule="evenodd" d="M16.704 5.295a1 1 0 010 1.41L8.41 15a1 1 0 01-1.41 0L3.296 11.295a1 1 0 011.41-1.41L7.705 12.88l7.59-7.586a1 1 0 011.41 0z" clipRule="evenodd" />
                    </svg>
                    {f}
                  </li>
                ))}
              </ul>
              <Link href="/comprar" className="btn-primary mt-8 w-full">
                Comprar — ${price} / año
              </Link>
              <p className="mt-3 text-center text-xs text-neutral-500">
                Pagás via QR (Yape · Plin · Transfer). Validación manual en menos de 24 h.
              </p>
            </div>
          </div>

          <div className="mt-6 text-center text-xs text-neutral-500">
            Comparado: CleanMyMac $44.95/año · DaisyDisk $9.99 pago único pero sin auto-reclaim.
          </div>
        </div>
      </div>
    </section>
  );
}
