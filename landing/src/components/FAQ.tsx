export default function FAQ() {
  const items = [
    {
      q: "¿Qué pasa después de pagar?",
      a: "Subís el screenshot del pago + tu email en el form. Recibís tu license key por email dentro de las 24 horas (validación manual). En la práctica suele ser mucho menos."
    },
    {
      q: "¿Para qué sirve la license key?",
      a: "Es lo que activa la app por 365 días desde la fecha de aprobación. Pegás la key en xclean → Preferences → License. Listo."
    },
    {
      q: "¿Qué métodos de pago aceptás?",
      a: "Por ahora QR — Yape, Plin, transferencia bancaria o USDT TRC20. Por eso el flujo es de validación manual."
    },
    {
      q: "¿Borra mis archivos importantes?",
      a: "No. xclean distingue entre cache (rebuildable), instalación (Flutter SDK, Homebrew Cellar) y datos de usuario. Solo ofrece borrar las primeras dos."
    },
    {
      q: "¿Funciona en Apple Silicon? ¿Intel?",
      a: "Sí. Compatible con macOS 13.0 o superior, arm64 (M1/M2/M3/M4) e Intel x86_64."
    },
    {
      q: "¿Se renueva sola?",
      a: "No. A los 365 días la app te avisa que la licencia venció. Si te gustó, comprás otro año. Si no, queda como freeware con features limitadas."
    },
    {
      q: "¿Trial?",
      a: "La app está disponible en modo free con todas las features de inspección. La license desbloquea el bulk reclaim y el auto-schedule."
    }
  ];

  return (
    <section id="faq" className="py-20 sm:py-28">
      <div className="container-narrow max-w-3xl">
        <div className="mb-12">
          <p className="mb-3 text-sm font-medium uppercase tracking-wider text-emerald-400">FAQ</p>
          <h2 className="text-3xl font-semibold tracking-tight sm:text-4xl">Preguntas frecuentes</h2>
        </div>
        <div className="divide-y divide-neutral-900 rounded-2xl border border-neutral-800 bg-neutral-950">
          {items.map((it) => (
            <details key={it.q} className="group p-6">
              <summary className="flex cursor-pointer list-none items-center justify-between text-base font-medium">
                {it.q}
                <span className="text-neutral-500 transition group-open:rotate-45">+</span>
              </summary>
              <p className="mt-3 text-sm leading-relaxed text-neutral-400">{it.a}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}
