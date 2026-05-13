import { redirect } from "next/navigation";
import { isAdmin } from "@/lib/auth";
import LoginForm from "./LoginForm";

export default async function Page() {
  if (await isAdmin()) redirect("/admin");

  return (
    <main className="flex min-h-screen items-center justify-center px-6">
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <div className="mx-auto mb-3 inline-block h-2 w-2 rounded-full bg-emerald-500" />
          <h1 className="text-2xl font-semibold">xclean · admin</h1>
          <p className="mt-1 text-sm text-neutral-500">Acceso restringido.</p>
        </div>
        <div className="card p-6">
          <LoginForm />
        </div>
      </div>
    </main>
  );
}
