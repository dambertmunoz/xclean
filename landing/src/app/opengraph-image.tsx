import { ImageResponse } from "next/og";

export const alt = "xclean — recuperá tu Mac · $10 al año";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OG() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: "80px",
          background:
            "radial-gradient(circle at 80% 0%, #064e3b 0%, #0a0a0a 55%)",
          color: "#fafafa",
          fontFamily: "system-ui, -apple-system, sans-serif",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 20 }}>
          <svg width="80" height="80" viewBox="0 0 64 64" fill="none">
            <defs>
              <linearGradient id="og-g" x1="0" y1="0" x2="1" y2="1">
                <stop offset="0%" stopColor="#34d399" />
                <stop offset="100%" stopColor="#059669" />
              </linearGradient>
            </defs>
            <rect width="64" height="64" rx="14" fill="#0a0a0a" />
            <g stroke="url(#og-g)" strokeWidth="7" strokeLinecap="round">
              <path d="M19 19 L41 41" />
              <path d="M41 19 L19 41" />
            </g>
            <g fill="#34d399">
              <circle cx="49" cy="14" r="2.6" />
              <circle cx="55.5" cy="20" r="1.5" />
              <circle cx="56" cy="11" r="1.1" />
            </g>
          </svg>
          <span style={{ fontSize: 44, fontWeight: 700, letterSpacing: -1 }}>
            xclean
          </span>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
          <div
            style={{
              fontSize: 88,
              fontWeight: 700,
              letterSpacing: -3,
              lineHeight: 1,
              display: "flex",
              flexDirection: "column",
            }}
          >
            <span>Recuperá tu Mac.</span>
            <span style={{ color: "#34d399" }}>Sin suscripciones.</span>
          </div>
          <div style={{ fontSize: 30, color: "#a3a3a3", maxWidth: 900 }}>
            Liberá decenas de GB de caches de Docker, Ollama, node_modules
            viejos. Un click. Pagás $10 una vez al año.
          </div>
        </div>

        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            color: "#6b6b6b",
            fontSize: 22,
          }}
        >
          <span>macOS 13.0+ · Apple Silicon + Intel</span>
          <span
            style={{
              background: "#10b981",
              color: "#0a0a0a",
              padding: "10px 22px",
              borderRadius: 999,
              fontWeight: 700,
              fontSize: 26,
            }}
          >
            $10 / año
          </span>
        </div>
      </div>
    ),
    size,
  );
}
