import Link from "next/link";
import Logo from "./Logo";

export default function Navbar() {
  return (
    <header className="sticky top-0 z-30 border-b border-neutral-900/70 bg-neutral-950/70 backdrop-blur">
      <div className="container-narrow flex h-14 items-center justify-between">
        <Link href="/" className="text-sm" aria-label="xclean — recuperá tu Mac">
          <Logo size={24} />
        </Link>
        <nav className="flex items-center gap-2 text-sm">
          <Link href="#features" className="hidden text-neutral-400 hover:text-neutral-100 sm:inline px-3 py-1.5">
            Features
          </Link>
          <Link href="#pricing" className="hidden text-neutral-400 hover:text-neutral-100 sm:inline px-3 py-1.5">
            Precio
          </Link>
          <Link href="#faq" className="hidden text-neutral-400 hover:text-neutral-100 sm:inline px-3 py-1.5">
            FAQ
          </Link>
          <Link href="/comprar" className="btn-primary !py-2 !text-xs">
            Comprar
          </Link>
        </nav>
      </div>
    </header>
  );
}
