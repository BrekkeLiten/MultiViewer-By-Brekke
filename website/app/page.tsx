import { CompanionTeaser } from "@/components/companion-teaser";
import { Features } from "@/components/features";
import { Footer } from "@/components/footer";
import { Hero } from "@/components/hero";
import { Requirements } from "@/components/requirements";
import { Shortcuts } from "@/components/shortcuts";

export default function Home() {
  return (
    <div className="page-backdrop animate-grain-fade relative min-h-screen">
      <div className="relative z-10">
        <Hero />
        <Features />
        <Shortcuts />
        <Requirements />
        <CompanionTeaser />
        <Footer />
      </div>
    </div>
  );
}
