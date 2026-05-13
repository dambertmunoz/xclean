import AdminNav from "./AdminNav";
import { cookies } from "next/headers";

/// Middleware already gates everything under /admin (except /admin/login).
/// This layout just renders the nav when we have a logged-in session.
export default async function Layout({ children }: { children: React.ReactNode }) {
  const hasCookie = !!(await cookies()).get("xclean_admin")?.value;
  return (
    <>
      {hasCookie && <AdminNav />}
      <main className="container-narrow py-10">{children}</main>
    </>
  );
}
