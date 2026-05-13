export default function Features() {
  const features = [
    {
      title: "Heurísticas inteligentes",
      body: "Detecta caches reales, builds huérfanos, simuladores sin uso, runtimes duplicados. Nunca borra tus archivos.",
      kbd: "age · orphan · corruption · duplicate"
    },
    {
      title: "Bulk reclaim en un click",
      body: "Identificá 60+ GB recuperables, libéralos con un solo botón. Corre los comandos oficiales (uv cache clean, brew cleanup, npm cache clean, …) en secuencia.",
      kbd: "⚡ Reclaim ~62 GB"
    },
    {
      title: "Monitor en menu bar",
      body: "Indicador siempre visible con el espacio libre. Cambia a amarillo o rojo cuando bajás de 20% / 10%. Notificación nativa al cruzar umbrales.",
      kbd: "● 42 GB free · 9%"
    },
    {
      title: "Auto-reclaim semanal",
      body: "Activá la limpieza automática todos los Domingos a las 3 AM. LaunchAgent nativo, sin servicios extra corriendo.",
      kbd: "cron · launchd"
    },
    {
      title: "Project artifact scanner",
      body: "Escanea ~/code, ~/Projects, ~/Documents recursivamente. Encuentra todos los node_modules, .next, target, Pods, build de proyectos viejos.",
      kbd: "node_modules · target · Pods"
    },
    {
      title: "Predicción de espacio",
      body: "Regresión lineal sobre 7 días de muestras: te avisa si el disco se va a llenar en menos de 30 días al ritmo actual.",
      kbd: "⚠︎ fills in 11 days"
    }
  ];

  return (
    <section id="features" className="py-20 sm:py-28">
      <div className="container-narrow">
        <div className="mb-12 max-w-2xl">
          <p className="mb-3 text-sm font-medium uppercase tracking-wider text-emerald-400">
            La solución
          </p>
          <h2 className="text-3xl font-semibold tracking-tight sm:text-4xl">
            Hecho por developers, para developers.
          </h2>
          <p className="mt-4 text-neutral-400">
            Cada feature está pensada para el flujo real de un dev en macOS — no es un cleaner genérico con publicidad.
          </p>
        </div>

        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {features.map((f) => (
            <div key={f.title} className="card p-6 transition hover:border-neutral-700">
              <h3 className="text-base font-semibold">{f.title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-neutral-400">{f.body}</p>
              <div className="mt-5 inline-flex rounded-md border border-neutral-800 bg-neutral-950 px-2.5 py-1 font-mono text-[11px] text-neutral-500">
                {f.kbd}
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
