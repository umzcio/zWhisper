import { useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ChevronDown, Check, Star } from "lucide-react";
import { cn } from "@/lib/utils";
import type { SortKey } from "@/components/models/modelsData";

export type TypeFilter = "all" | "local" | "cloud";

const TYPE_OPTIONS: { id: TypeFilter; label: string }[] = [
  { id: "all", label: "All" },
  { id: "local", label: "Local" },
  { id: "cloud", label: "Cloud" },
];

const SORT_OPTIONS: { id: SortKey; label: string }[] = [
  { id: "speed", label: "Speed" },
  { id: "accuracy", label: "Accuracy" },
  { id: "size", label: "Size" },
];

interface MiniSelectProps {
  value: string;
  options: string[];
  onChange: (v: string) => void;
  className?: string;
}

/** Small dropdown select with spring popover + outside-click dismiss */
function MiniSelect({ value, options, onChange, className }: MiniSelectProps) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: PointerEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    window.addEventListener("pointerdown", onDown);
    return () => window.removeEventListener("pointerdown", onDown);
  }, [open]);

  return (
    <div ref={ref} className={cn("relative", className)}>
      <motion.button
        type="button"
        onClick={() => setOpen((o) => !o)}
        whileTap={{ scale: 0.97 }}
        transition={{ type: "spring", stiffness: 500, damping: 35 }}
        className="flex cursor-pointer items-center gap-1 rounded-[6px] hairline bg-surface-2 px-2 py-1 text-[12px] font-medium text-1 hover:bg-surface-3/60"
      >
        {value}
        <ChevronDown size={12} className="text-3" />
      </motion.button>
      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, scale: 0.92, y: -4 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.95, y: -4 }}
            transition={{ type: "spring", stiffness: 400, damping: 30 }}
            className="vibrancy absolute left-0 top-7 z-30 min-w-32 rounded-[10px] p-1 shadow-popover hairline"
          >
            {options.map((opt) => (
              <button
                key={opt}
                type="button"
                onClick={() => {
                  onChange(opt);
                  setOpen(false);
                }}
                className={cn(
                  "flex w-full cursor-pointer items-center gap-2 rounded-md px-2 py-1 text-left text-[12px]",
                  opt === value ? "text-1" : "text-2 hover:bg-surface-3/60 hover:text-1"
                )}
              >
                <span className="w-3.5">
                  {opt === value && <Check size={11} className="text-accent-blue" strokeWidth={3} />}
                </span>
                {opt}
              </button>
            ))}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

interface FilterBarProps {
  type: TypeFilter;
  onTypeChange: (t: TypeFilter) => void;
  provider: string;
  onProviderChange: (p: string) => void;
  favoritesOnly: boolean;
  onToggleFavorites: () => void;
  sort: SortKey;
  onSortChange: (s: SortKey) => void;
}

export default function FilterBar({
  type,
  onTypeChange,
  provider,
  onProviderChange,
  favoritesOnly,
  onToggleFavorites,
  sort,
  onSortChange,
}: FilterBarProps) {
  return (
    <div className="flex items-center gap-2">
      {/* segmented Type control */}
      <div className="flex rounded-[8px] hairline bg-surface-2 p-0.5">
        {TYPE_OPTIONS.map((opt) => {
          const active = type === opt.id;
          return (
            <button
              key={opt.id}
              type="button"
              onClick={() => onTypeChange(opt.id)}
              className={cn(
                "relative cursor-pointer rounded-[6px] px-2.5 py-1 text-[12px] font-medium transition-colors",
                active ? "text-1" : "text-2 hover:text-1"
              )}
            >
              {active && (
                <motion.span
                  layoutId="type-segment-thumb"
                  transition={{ type: "spring", stiffness: 500, damping: 35 }}
                  className="absolute inset-0 rounded-[6px] bg-surface-3 shadow-[0_1px_2px_rgba(0,0,0,0.3)]"
                />
              )}
              <span className="relative">{opt.label}</span>
            </button>
          );
        })}
      </div>

      <MiniSelect value={provider} options={["All providers", "OpenAI", "Anthropic", "Deepgram", "Groq"]} onChange={onProviderChange} />

      {/* favorites toggle */}
      <motion.button
        type="button"
        aria-pressed={favoritesOnly}
        onClick={onToggleFavorites}
        whileTap={{ scale: 0.95 }}
        transition={{ type: "spring", stiffness: 500, damping: 35 }}
        className={cn(
          "flex cursor-pointer items-center gap-1.5 rounded-[6px] hairline px-2 py-1 text-[12px] font-medium transition-colors",
          favoritesOnly
            ? "border-[#FFD60A]/30 bg-[#FFD60A]/10 text-[#FFD60A]"
            : "bg-surface-2 text-2 hover:bg-surface-3/60 hover:text-1"
        )}
      >
        <Star size={12} className={favoritesOnly ? "fill-[#FFD60A]" : undefined} />
        Favorites only
      </motion.button>

      <div className="flex-1" />

      <span className="text-[11px] text-3">Sort</span>
      <MiniSelect
        value={SORT_OPTIONS.find((o) => o.id === sort)?.label ?? "Speed"}
        options={SORT_OPTIONS.map((o) => o.label)}
        onChange={(label) => {
          const found = SORT_OPTIONS.find((o) => o.label === label);
          if (found) onSortChange(found.id);
        }}
      />
    </div>
  );
}
