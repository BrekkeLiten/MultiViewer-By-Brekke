import { siteConfig } from "@/lib/site";

export function DownloadButton({ className = "" }: { className?: string }) {
  const url = siteConfig.downloadUrl.trim();
  const version = siteConfig.version;

  if (url) {
    return (
      <a
        href={url}
        className={`tally-button inline-flex items-center justify-center rounded-md px-6 py-3 font-display text-sm font-bold uppercase tracking-[0.08em] ${className}`}
      >
        Download for macOS · v{version}
      </a>
    );
  }

  return (
    <div className={`flex flex-col items-start gap-2 ${className}`}>
      <span
        className="inline-flex cursor-not-allowed items-center justify-center rounded-md border border-border-dim bg-bg-panel px-6 py-3 font-display text-sm font-bold uppercase tracking-[0.08em] text-text-muted"
        aria-disabled="true"
      >
        Download coming soon
      </span>
      <span className="font-mono text-xs text-text-muted">
        v{version} · macOS 13+ · Apple Silicon & Intel
      </span>
    </div>
  );
}
