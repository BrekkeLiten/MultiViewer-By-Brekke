import { HudBadge } from "./hud-badge";

const features: { title: string; body: string; badge: string; span?: string }[] = [
  {
    title: "1-up & 4-up layouts",
    body: "Full-screen slot 1 or four quadrants — switch instantly from the app, View menu, or over HTTP.",
    badge: "Layout",
  },
  {
    title: "NDI® built in",
    body: "Release builds ship the NDI runtime inside the app. Discover sources, connect by IP, or assign by name.",
    badge: "NDI",
  },
  {
    title: "DeckLink SDI",
    body: "Capture from Blackmagic hardware when Desktop Video drivers are installed.",
    badge: "SDI",
  },
  {
    title: "1-up scope monitor",
    body: "LiveScopes-style 2×2 grid in 1-up: picture, vectorscope, RGB waveform, and RGB parade. Drag dividers to resize.",
    badge: "Scopes",
    span: "md:col-span-2",
  },
  {
    title: "Picture monitoring",
    body: "GPU focus peaking, false color, and zebra on every visible feed. Title-bar P / F / Z toggles and ⌘⇧ shortcuts.",
    badge: "Monitor",
  },
  {
    title: "Correct aspect ratio",
    body: "Incoming frames are letterboxed or pillarboxed to match broadcast display aspect.",
    badge: "Display",
  },
  {
    title: "HTTP control API",
    body: "POST layout, source, and picture-monitoring changes from Companion, curl, or any automation that speaks HTTP.",
    badge: "API",
    span: "md:col-span-2",
  },
  {
    title: "Flexible control server",
    body: "Bind to localhost, your LAN IP, or all interfaces — copy the URL from Preferences.",
    badge: "Control",
  },
];

export function Features() {
  return (
    <section id="features" className="mx-auto max-w-6xl px-6 py-20 md:py-28">
      <div className="mb-12 max-w-2xl">
        <HudBadge>Features</HudBadge>
        <h2 className="mt-4 font-display text-3xl font-bold tracking-tight text-text-primary md:text-4xl">
          Built for live production
        </h2>
        <p className="mt-4 text-lg text-text-muted">
          A focused multiview monitor with scopes and picture tools — not a switcher, not a recorder.
          Reliable feeds on screen, with the control hooks your show already uses.
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        {features.map((feature) => (
          <article
            key={feature.title}
            className={`panel-bezel group rounded-xl p-6 transition-colors hover:border-accent-signal/30 ${feature.span ?? ""}`}
          >
            <HudBadge className="mb-4">{feature.badge}</HudBadge>
            <h3 className="font-display text-xl font-bold text-text-primary">{feature.title}</h3>
            <p className="mt-3 leading-relaxed text-text-muted">{feature.body}</p>
          </article>
        ))}
      </div>
    </section>
  );
}
