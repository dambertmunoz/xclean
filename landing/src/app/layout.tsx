import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "xclean — recuperá tu Mac · $10 / año",
  description:
    "App para macOS que detecta qué te está chupando GB y los libera de un click. Pago único anual de $10. Sin suscripciones renovables.",
  openGraph: {
    title: "xclean — recuperá tu Mac",
    description: "Reclamá decenas de GB de tu disco. $10 al año, sin trampas.",
    type: "website"
  }
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="es">
      <body>{children}</body>
    </html>
  );
}
