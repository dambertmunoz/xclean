import Link from "next/link";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";

export default async function Page({ searchParams }: { searchParams: Promise<{ ref?: string }> }) {
  const { ref } = await searchParams;
  return (
    <>
      <Navbar />
      <main className="container-narrow flex min-h-[70vh] items-center py-16">
        <div className="mx-auto max-w-xl text-center">
          <div className="mx-auto mb-6 inline-flex h-14 w-14 items-center justify-center rounded-full bg-emerald-500/15 text-2xl text-emerald-400">
            ✓
          </div>
          <h1 className="text-4xl font-semibold tracking-tight">¡Recibimos tu pago!</h1>
          <p className="mt-3 text-neutral-400">
            Vamos a validar el comprobante manualmente y enviarte la license key a tu email
            en menos de 24 horas. En la mayoría de los casos es mucho más rápido.
          </p>
          {ref && (
            <p className="mt-6 inline-block rounded-md border border-neutral-800 bg-neutral-950 px-3 py-1.5 font-mono text-xs text-neutral-400">
              Referencia: #{ref.padStart(5, "0")}
            </p>
          )}
          <div className="mt-10">
            <Link href="/" className="btn-ghost">Volver al inicio</Link>
          </div>
          <p className="mt-8 text-xs text-neutral-500">
            ¿Algo se ve raro? Escribinos a <a className="underline hover:text-neutral-300" href="mailto:dev@wasyra.com">dev@wasyra.com</a>.
          </p>
        </div>
      </main>
      <Footer />
    </>
  );
}
