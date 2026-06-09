import { siteConfig } from "@/lib/site";

export function Footer() {
  return (
    <footer className="border-t border-border-dim bg-bg-panel/40">
      <div className="mx-auto flex max-w-6xl flex-col gap-4 px-6 py-10 md:flex-row md:items-start md:justify-between">
        <div>
          <p className="font-display text-lg font-bold text-text-primary">{siteConfig.name}</p>
          <p className="mt-1 font-mono text-xs text-text-muted">com.brekke.multiviewer</p>
        </div>
        <p className="max-w-xl text-sm leading-relaxed text-text-muted">
          NDI® is a registered trademark of Vizrt NDI AB. Release builds include the NDI runtime under
          the NDI SDK license. Learn more at{" "}
          <a
            href="https://ndi.video/"
            className="text-text-primary underline-offset-4 hover:text-accent-signal hover:underline"
            target="_blank"
            rel="noopener noreferrer"
          >
            ndi.video
          </a>
          .
        </p>
      </div>
    </footer>
  );
}
