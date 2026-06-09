type HudBadgeProps = {
  children: React.ReactNode;
  className?: string;
};

export function HudBadge({ children, className = "" }: HudBadgeProps) {
  return (
    <span
      className={`inline-flex items-center rounded border border-border-dim bg-bg-deep/80 px-2 py-0.5 font-mono text-[10px] uppercase tracking-[0.14em] text-accent-signal ${className}`}
    >
      {children}
    </span>
  );
}
