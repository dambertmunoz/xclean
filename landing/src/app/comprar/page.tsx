import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import BuyForm from "./BuyForm";
import Image from "next/image";
import fs from "node:fs";
import path from "node:path";

export default function Page() {
  const price = process.env.PRICE_USD ?? "10";
  const paymentLabel = process.env.PAYMENT_LABEL ?? "Yape / Plin / Transferencia";

  // Show the real QR if the user dropped one at public/qr.png; otherwise a
  // styled placeholder so the page never looks broken.
  const qrPath = path.join(process.cwd(), "public", "qr.png");
  const hasRealQR = fs.existsSync(qrPath);

  return (
    <>
      <Navbar />
      <main className="container-narrow py-16 sm:py-20">
        <div className="mx-auto max-w-3xl">
          <div className="text-center">
            <p className="text-sm font-medium uppercase tracking-wider text-emerald-400">Paso 1 de 2</p>
            <h1 className="mt-3 text-4xl font-semibold tracking-tight sm:text-5xl">
              Transferí ${price} USD
            </h1>
            <p className="mt-3 text-neutral-400">
              Pagá usando el QR de abajo. Después subí el screenshot del pago + tu email para activar la licencia.
            </p>
          </div>

          <div className="mt-10 grid gap-6 lg:grid-cols-[1fr_1.15fr]">
            {/* QR card */}
            <div className="card p-7">
              <p className="text-xs font-medium uppercase tracking-wider text-neutral-400">
                Método: {paymentLabel}
              </p>
              <p className="mt-1 text-sm text-neutral-500">Monto exacto:</p>
              <p className="text-3xl font-bold text-emerald-400">${price} USD</p>

              <div className="mt-6 flex aspect-square items-center justify-center rounded-xl border border-neutral-800 bg-white p-4">
                {hasRealQR ? (
                  <Image src="/qr.png" alt="QR de pago" width={300} height={300} className="h-full w-full object-contain" />
                ) : (
                  <PlaceholderQR />
                )}
              </div>
              {!hasRealQR && (
                <p className="mt-3 text-center text-xs text-neutral-500">
                  ⓘ Reemplazá <code className="font-mono text-emerald-400">public/qr.png</code> con tu QR real.
                </p>
              )}
            </div>

            {/* Form */}
            <div className="card p-7">
              <p className="text-sm font-medium uppercase tracking-wider text-emerald-400">Paso 2 de 2</p>
              <h2 className="mt-1 text-xl font-semibold">Enviá la prueba</h2>
              <p className="mt-1 text-sm text-neutral-400">
                Tomá un screenshot del pago confirmado y subilo. Recibís la license key por email en ≤24 h.
              </p>
              <div className="mt-6">
                <BuyForm />
              </div>
            </div>
          </div>

          <p className="mx-auto mt-10 max-w-2xl text-center text-xs text-neutral-500">
            Tus datos no se comparten con terceros. La imagen del pago se almacena cifrada en disco y se
            borra después de 90 días. Solo el admin puede verla.
          </p>
        </div>
      </main>
      <Footer />
    </>
  );
}

function PlaceholderQR() {
  return (
    <div className="grid h-full w-full grid-cols-12 grid-rows-12 gap-[2px]">
      {Array.from({ length: 144 }).map((_, i) => {
        const v = (i * 9301 + 49297) % 233280;
        const fill = (v / 233280) > 0.5;
        return <div key={i} className={fill ? "bg-black" : ""} />;
      })}
    </div>
  );
}
