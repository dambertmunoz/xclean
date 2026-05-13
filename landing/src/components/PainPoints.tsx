export default function PainPoints() {
  const items = [
    {
      n: "1",
      title: "Tu Mac de 256 GB se llena en meses",
      body: "DerivedData, node_modules, Docker, Ollama, Flutter… cada herramienta deja basura silenciosa. La sumás y son decenas de GB."
    },
    {
      n: "2",
      title: "CleanMyMac cuesta $40+ al año",
      body: "Y se llena de upsells. Pagás una suscripción cara para algo que ya hace un script de bash bien hecho."
    },
    {
      n: "3",
      title: "Las apps gratis te abandonan",
      body: "Discontinuadas, con malware, llenas de ads, o no entienden el ecosistema de desarrollo moderno."
    }
  ];

  return (
    <section className="py-20 sm:py-28">
      <div className="container-narrow">
        <div className="mb-12 max-w-2xl">
          <p className="mb-3 text-sm font-medium uppercase tracking-wider text-emerald-400">
            El problema
          </p>
          <h2 className="text-3xl font-semibold tracking-tight sm:text-4xl">
            Te estás quedando sin espacio. Otra vez.
          </h2>
        </div>
        <div className="grid gap-px overflow-hidden rounded-2xl border border-neutral-800 bg-neutral-800 sm:grid-cols-3">
          {items.map((item) => (
            <div key={item.n} className="bg-neutral-950 p-7">
              <div className="font-mono text-xs text-neutral-500">{item.n.padStart(2, "0")}</div>
              <h3 className="mt-3 text-lg font-semibold">{item.title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-neutral-400">{item.body}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
