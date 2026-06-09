import { HudBadge } from "./hud-badge";

const shortcuts = [
  { keys: "⌘ 1 / ⌘ 4", action: "1-up / 4-up layout" },
  { keys: "⇧ ⌘ I", action: "Configure inputs" },
  { keys: "⇧ ⌘ P", action: "Toggle focus peaking" },
  { keys: "⇧ ⌘ F", action: "Toggle false color" },
  { keys: "⇧ ⌘ Z", action: "Toggle zebra" },
  { keys: "⌘ ,", action: "Preferences" },
];

export function Shortcuts() {
  return (
    <section className="mx-auto max-w-6xl px-6 pb-4">
      <div className="panel-bezel rounded-xl px-5 py-4 md:px-6">
        <div className="mb-4 flex items-center gap-3">
          <HudBadge>Shortcuts</HudBadge>
          <span className="font-mono text-xs text-text-muted">Title bar · P / F / Z for picture tools</span>
        </div>
        <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {shortcuts.map((item) => (
            <li key={item.keys} className="flex items-baseline gap-3">
              <span className="shrink-0 rounded border border-border-dim bg-bg-deep px-2 py-0.5 font-mono text-xs text-accent-signal">
                {item.keys}
              </span>
              <span className="text-sm text-text-muted">{item.action}</span>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
