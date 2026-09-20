import { cn } from "@/lib/utils";

interface DotMeterProps {
  label: string;
  value: number; // 1–5
  className?: string;
}

/** 5-dot meter (filled = accent, empty = surface-3) with a hover tooltip */
export default function DotMeter({ label, value, className }: DotMeterProps) {
  return (
    <div className={cn("group relative flex flex-col items-start gap-1", className)}>
      <span className="text-[10px] font-medium uppercase tracking-[0.02em] text-3">
        {label}
      </span>
      <div className="flex items-center gap-1">
        {Array.from({ length: 5 }, (_, i) => (
          <span
            key={i}
            className={cn(
              "h-1.5 w-1.5 rounded-full",
              i < value ? "bg-accent-blue" : "bg-surface-3"
            )}
          />
        ))}
      </div>
      {/* tooltip */}
      <div className="pointer-events-none absolute -top-7 left-1/2 z-20 -translate-x-1/2 whitespace-nowrap rounded-md bg-surface-3 px-2 py-0.5 text-[11px] font-medium text-1 opacity-0 shadow-popover transition-opacity duration-150 group-hover:opacity-100">
        {label} {value}/5
      </div>
    </div>
  );
}
