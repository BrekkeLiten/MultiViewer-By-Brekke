import { HudBadge } from "./hud-badge";

const layoutExamples = [
  "POST /layout/4",
  "POST /layout/1",
  "POST /layout/primary/2",
  "POST /source/1/ndi%3AOBS%20(Program)",
];

const monitoringExamples = [
  "POST /monitoring/peaking/toggle",
  "POST /monitoring/falsecolor/on",
  "POST /monitoring/zebra/90",
  "GET  /state",
];

export function CompanionTeaser() {
  return (
    <section id="companion" className="mx-auto max-w-6xl px-6 py-16 md:py-24">
      <div className="grid gap-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)] lg:items-start">
        <div>
          <HudBadge>Bitfocus Companion</HudBadge>
          <h2 className="mt-4 font-display text-3xl font-bold tracking-tight text-text-primary md:text-4xl">
            Control from Stream Deck
          </h2>
          <p className="mt-4 max-w-lg text-lg leading-relaxed text-text-muted">
            No custom Companion module required. Add generic HTTP POST actions to switch layouts, route
            NDI or SDI sources, and toggle focus peaking, false color, or zebra from your surface.
          </p>
          <p className="mt-4 font-mono text-sm text-text-muted">
            Enable the control server in Preferences, copy the base URL, and point your buttons at it.
            <code className="ml-1 text-text-primary">GET /state</code> returns layout and monitoring status.
          </p>
        </div>

        <div className="relative space-y-4 lg:-mr-6 xl:-mr-10">
          <CodePanel title="Layout & sources · http://HOST:8080" lines={layoutExamples} />
          <CodePanel title="Picture monitoring" lines={monitoringExamples} />
        </div>
      </div>
    </section>
  );
}

function CodePanel({ title, lines }: { title: string; lines: string[] }) {
  return (
    <div className="panel-bezel overflow-hidden rounded-xl border border-border-dim bg-[#08080a] p-5 md:p-6">
      <div className="mb-4 font-mono text-[10px] uppercase tracking-[0.18em] text-text-muted">{title}</div>
      <pre className="overflow-x-auto font-mono text-sm leading-7 text-text-primary">
        {lines.map((line) => {
          const [method, ...rest] = line.split(" ");
          const path = rest.join(" ");
          return (
            <div key={line}>
              <span className={method === "GET" ? "text-text-muted" : "text-accent-signal"}>{method}</span>{" "}
              {path}
            </div>
          );
        })}
      </pre>
    </div>
  );
}
