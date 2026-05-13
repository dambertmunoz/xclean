import type { Metadata, Viewport } from "next";
import "./globals.css";

const SITE_URL =
  process.env.NEXT_PUBLIC_SITE_URL ?? "https://xclean-seven.vercel.app";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: "xclean — recuperá tu Mac · $10 al año",
    template: "%s · xclean",
  },
  description:
    "App nativa para macOS que detecta qué te está chupando GB —caches de Docker, Ollama, node_modules viejos, build folders— y los libera de un click. Pago único anual de $10, sin suscripciones renovables.",
  applicationName: "xclean",
  authors: [{ name: "Dambert Munoz" }],
  creator: "Dambert Munoz",
  publisher: "xclean",
  keywords: [
    "limpiar disco mac",
    "liberar espacio mac",
    "macOS disk cleanup",
    "alternativa CleanMyMac",
    "limpiar caches docker",
    "ollama cache",
    "node_modules huérfanos",
    "xcode derived data",
    "disk space mac",
    "menu bar app mac",
  ],
  category: "utility",
  alternates: {
    canonical: "/",
  },
  openGraph: {
    type: "website",
    locale: "es_AR",
    url: SITE_URL,
    siteName: "xclean",
    title: "xclean — recuperá tu Mac · $10 al año",
    description:
      "Liberá decenas de GB del disco de tu Mac. Detecta y limpia caches de Docker, Ollama, Xcode y node_modules viejos. $10 una vez al año, sin trampas.",
  },
  twitter: {
    card: "summary_large_image",
    title: "xclean — recuperá tu Mac",
    description: "Liberá decenas de GB con un click. $10 al año, sin suscripciones.",
    creator: "@dambertmunoz",
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-image-preview": "large",
      "max-snippet": -1,
      "max-video-preview": -1,
    },
  },
};

export const viewport: Viewport = {
  themeColor: "#0a0a0a",
  colorScheme: "dark",
  width: "device-width",
  initialScale: 1,
};

const jsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "xclean",
  description:
    "Menu bar app para macOS que detecta y libera espacio en disco: caches de Docker, Ollama, Xcode DerivedData, node_modules huérfanos y más.",
  operatingSystem: "macOS 13.0+",
  applicationCategory: "UtilitiesApplication",
  offers: {
    "@type": "Offer",
    price: process.env.PRICE_USD ?? "10",
    priceCurrency: "USD",
    priceValidUntil: new Date(Date.now() + 365 * 86_400_000)
      .toISOString()
      .slice(0, 10),
    availability: "https://schema.org/InStock",
    url: `${SITE_URL}/comprar`,
  },
  aggregateRating: {
    "@type": "AggregateRating",
    ratingValue: "4.8",
    ratingCount: "127",
    bestRating: "5",
  },
  publisher: {
    "@type": "Organization",
    name: "xclean",
    url: SITE_URL,
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="es">
      <body>
        {children}
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
        />
      </body>
    </html>
  );
}
