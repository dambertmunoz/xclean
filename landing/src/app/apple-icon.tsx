import { ImageResponse } from "next/og";

export const size = { width: 180, height: 180 };
export const contentType = "image/png";

export default function AppleIcon() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "#0a0a0a",
        }}
      >
        <svg width="140" height="140" viewBox="0 0 64 64" fill="none">
          <defs>
            <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stopColor="#34d399" />
              <stop offset="100%" stopColor="#059669" />
            </linearGradient>
          </defs>
          <g stroke="url(#g)" strokeWidth="7" strokeLinecap="round">
            <path d="M19 19 L41 41" />
            <path d="M41 19 L19 41" />
          </g>
          <g fill="#34d399">
            <circle cx="49" cy="14" r="2.6" />
            <circle cx="55.5" cy="20" r="1.5" />
            <circle cx="56" cy="11" r="1.1" />
          </g>
        </svg>
      </div>
    ),
    size,
  );
}
