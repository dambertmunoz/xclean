type Props = {
  size?: number;
  withText?: boolean;
  className?: string;
};

export default function Logo({ size = 28, withText = true, className }: Props) {
  return (
    <span className={`inline-flex items-center gap-2 ${className ?? ""}`}>
      <svg
        width={size}
        height={size}
        viewBox="0 0 64 64"
        fill="none"
        aria-hidden="true"
      >
        <defs>
          <linearGradient id="x-grad" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="#34d399" />
            <stop offset="100%" stopColor="#059669" />
          </linearGradient>
        </defs>
        <rect width="64" height="64" rx="14" fill="#0a0a0a" />
        <g stroke="url(#x-grad)" strokeWidth="7" strokeLinecap="round">
          <path d="M19 19 L41 41" />
          <path d="M41 19 L19 41" />
        </g>
        <g fill="#34d399">
          <circle cx="49" cy="14" r="2.6" />
          <circle cx="55.5" cy="20" r="1.5" />
          <circle cx="56" cy="11" r="1.1" />
        </g>
      </svg>
      {withText && (
        <span className="font-semibold tracking-tight">xclean</span>
      )}
    </span>
  );
}
