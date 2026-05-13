export default function Footer() {
  return (
    <footer className="border-t border-neutral-900 py-10">
      <div className="container-narrow flex flex-col items-center gap-3 text-xs text-neutral-500 sm:flex-row sm:justify-between">
        <div className="flex items-center gap-2">
          <span className="inline-block h-1.5 w-1.5 rounded-full bg-emerald-500" />
          <span>xclean · made on a Mac that was running out of space</span>
        </div>
        <div className="flex items-center gap-4">
          <span>© {new Date().getFullYear()}</span>
          <a className="hover:text-neutral-300" href="mailto:dev@wasyra.com">dev@wasyra.com</a>
        </div>
      </div>
    </footer>
  );
}
