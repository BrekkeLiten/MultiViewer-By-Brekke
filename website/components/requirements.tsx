import { HudBadge } from "./hud-badge";

const requirements = [
  {
    label: "Platform",
    value: "macOS 13 or later · Apple Silicon or Intel",
  },
  {
    label: "NDI",
    value: "NDI® runtime included in the app · tools and info at ndi.video",
    href: "https://ndi.video/",
  },
  {
    label: "SDI (optional)",
    value: "Blackmagic Desktop Video drivers for DeckLink / UltraStudio hardware",
  },
];

export function Requirements() {
  return (
    <section className="mx-auto max-w-6xl px-6 py-16 md:py-20">
      <div className="panel-bezel rounded-xl p-6 md:p-8">
        <div className="mb-6 flex items-center gap-3">
          <HudBadge>Requirements</HudBadge>
          <h2 className="font-display text-2xl font-bold text-text-primary">Before you install</h2>
        </div>
        <dl className="grid gap-4 md:grid-cols-3">
          {requirements.map((item) => (
            <div key={item.label} className="rounded-lg border border-border-dim bg-bg-deep/50 p-4">
              <dt className="font-mono text-[10px] uppercase tracking-[0.16em] text-accent-signal">
                {item.label}
              </dt>
              <dd className="mt-2 text-sm leading-relaxed text-text-muted">
                {"href" in item && item.href ? (
                  <a
                    href={item.href}
                    className="text-text-primary underline-offset-4 hover:text-accent-signal hover:underline"
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {item.value}
                  </a>
                ) : (
                  item.value
                )}
              </dd>
            </div>
          ))}
        </dl>
      </div>
    </section>
  );
}
