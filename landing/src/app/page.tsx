import Navbar from "@/components/Navbar";
import Hero from "@/components/Hero";
import SocialProof from "@/components/SocialProof";
import PainPoints from "@/components/PainPoints";
import Features from "@/components/Features";
import Pricing from "@/components/Pricing";
import FAQ from "@/components/FAQ";
import Footer from "@/components/Footer";

export const revalidate = 1800;

export default function Page() {
  return (
    <>
      <Navbar />
      <main>
        <Hero />
        <SocialProof />
        <PainPoints />
        <Features />
        <Pricing />
        <FAQ />
      </main>
      <Footer />
    </>
  );
}
