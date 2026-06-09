import Image from "next/image";
import { DownloadButton } from "./download-button";
import { HudBadge } from "./hud-badge";
import { MonitorMockup } from "./monitor-mockup";

export function Hero() {
  return (
    <section className="relative mx-auto grid max-w-6xl gap-10 px-6 pb-20 pt-16 md:grid-cols-[minmax(0,1fr)_minmax(0,1.15fr)] md:items-center md:gap-8 md:pb-28 md:pt-24 lg:gap-12">
      <div className="relative z-10">
        <div className="animate-fade-up mb-6 flex items-center gap-3" style={{ animationDelay: "80ms" }}>
          <Image
            src="/app-icon.png"
            alt="MultiViewer by Brekke app icon"
            width={56}
            height={56}
            className="rounded-xl shadow-lg shadow-black/40"
            priority
          />
          <HudBadge>macOS native</HudBadge>
        </div>

        <h1
          className="animate-fade-up font-display text-4xl font-extrabold leading-[1.05] tracking-tight text-text-primary sm:text-5xl lg:text-6xl"
          style={{ animationDelay: "80ms" }}
        >
          Four feeds.
          <br />
          <span className="text-accent-tally">One screen.</span>
          <br />
          Companion-ready.
        </h1>

        <p
          className="animate-fade-up mt-6 max-w-lg text-lg leading-relaxed text-text-muted"
          style={{ animationDelay: "160ms" }}
        >
          Metal-powered multiview for NDI and DeckLink SDI — with bundled NDI runtime, optional 1-up
          scope monitor, focus peaking, false color, zebra, and HTTP control from Bitfocus Companion.
        </p>

        <div className="animate-fade-up mt-8 flex flex-wrap items-center gap-4" style={{ animationDelay: "160ms" }}>
          <DownloadButton />
          <a
            href="#features"
            className="font-mono text-sm text-text-muted underline-offset-4 transition-colors hover:text-accent-signal hover:underline"
          >
            See features ↓
          </a>
        </div>
      </div>

      <div className="animate-scale-in relative md:-mt-6 lg:-mr-4" style={{ animationDelay: "240ms" }}>
        <MonitorMockup />
      </div>
    </section>
  );
}
