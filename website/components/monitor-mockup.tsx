import { HudBadge } from "./hud-badge";

const slots = [
  { label: "NDI · 1920×1080", tint: "from-zinc-800/80 to-zinc-950" },
  { label: "NDI · 1280×720", tint: "from-slate-800/70 to-zinc-950" },
  { label: "SDI · 1920×1080", tint: "from-neutral-800/75 to-zinc-950" },
  { label: "NDI · 1920×1080", tint: "from-stone-800/70 to-zinc-950" },
];

const monitorToggles = [
  { key: "P", label: "Peaking", active: true },
  { key: "F", label: "False color", active: false },
  { key: "Z", label: "Zebra", active: false },
];

export function MonitorMockup({ className = "" }: { className?: string }) {
  return (
    <div
      className={`panel-bezel relative overflow-hidden rounded-xl p-3 md:p-4 ${className}`}
      aria-hidden="true"
    >
      <div className="mb-3 flex items-center justify-between px-1">
        <div className="flex items-center gap-2">
          <span className="inline-block h-2 w-2 rounded-full bg-accent-tally animate-rec-pulse" />
          <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-muted">
            Multiview · 4-up
          </span>
        </div>
        <div className="flex items-center gap-1.5">
          {monitorToggles.map((toggle) => (
            <span
              key={toggle.key}
              className={`rounded border px-1.5 py-0.5 font-mono text-[9px] uppercase tracking-wider ${
                toggle.active
                  ? "border-accent-signal/50 bg-accent-signal/15 text-accent-signal"
                  : "border-border-dim text-text-muted"
              }`}
              title={toggle.label}
            >
              {toggle.key}
            </span>
          ))}
          <HudBadge>Metal</HudBadge>
        </div>
      </div>

      <div className="relative aspect-video overflow-hidden rounded-lg border border-border-dim bg-black">
        <div className="absolute inset-0 grid grid-cols-2 grid-rows-2 gap-px bg-border-dim">
          {slots.map((slot) => (
            <div
              key={slot.label}
              className={`relative overflow-hidden bg-gradient-to-br ${slot.tint}`}
            >
              <div className="absolute inset-0 opacity-20 bg-[linear-gradient(rgba(255,255,255,0.04)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.04)_1px,transparent_1px)] bg-[size:8px_8px]" />
              <div className="absolute right-2 top-2">
                <HudBadge>{slot.label}</HudBadge>
              </div>
            </div>
          ))}
        </div>
        <div className="pointer-events-none absolute inset-0 overflow-hidden opacity-[0.07]">
          <div className="h-full w-full bg-gradient-to-b from-transparent via-white to-transparent animate-scan-sweep" />
        </div>
      </div>

      <div className="mt-3 grid grid-cols-4 gap-1 rounded-lg border border-border-dim bg-bg-deep/60 p-1.5">
        <ScopeCell label="Picture" active />
        <ScopeCell label="Vectorscope" />
        <ScopeCell label="Waveform" />
        <ScopeCell label="Parade" />
      </div>
      <p className="mt-2 px-1 font-mono text-[9px] uppercase tracking-[0.14em] text-text-muted">
        1-up scope monitor · optional in Preferences
      </p>
    </div>
  );
}

function ScopeCell({ label, active = false }: { label: string; active?: boolean }) {
  return (
    <div
      className={`relative aspect-[4/3] overflow-hidden rounded border ${
        active ? "border-accent-signal/40 bg-zinc-800/80" : "border-border-dim bg-zinc-900/90"
      }`}
    >
      {label === "Vectorscope" && (
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="h-3/5 w-3/5 rounded-full border border-accent-signal/30" />
        </div>
      )}
      {label === "Waveform" && (
        <div className="absolute inset-x-1 bottom-2 top-2 flex items-end gap-px">
          {[40, 65, 30, 80, 55, 70, 45].map((h, i) => (
            <div key={i} className="flex-1 rounded-t bg-accent-signal/50" style={{ height: `${h}%` }} />
          ))}
        </div>
      )}
      {label === "Parade" && (
        <div className="absolute inset-1 grid grid-cols-3 gap-px">
          <div className="rounded-sm bg-red-500/30" />
          <div className="rounded-sm bg-green-500/30" />
          <div className="rounded-sm bg-blue-500/30" />
        </div>
      )}
      <span className="absolute bottom-0.5 left-1 font-mono text-[7px] text-text-muted">{label}</span>
    </div>
  );
}
