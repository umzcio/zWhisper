import { useCallback, useEffect, useRef, useState } from "react";
import { motion } from "framer-motion";
import { cn } from "@/lib/utils";
import ShortcutKey from "@/components/ShortcutKey";
import { useApp } from "@/lib/store";
import type { LibraryMode } from "@/components/modes/data";
import { MODE_ICON_MAP } from "@/components/modes/data";

const SPRING_MICRO = { type: "spring", stiffness: 500, damping: 35 } as const;

interface ModeCycleStripProps {
  modes: LibraryMode[];
}

/**
 * Demo strip: "hold ⌥⇧ and tap K to cycle modes" — hold the demo button, tap K
 * (button or key) to slide the highlight across the mode pill carousel.
 */
export default function ModeCycleStrip({ modes }: ModeCycleStripProps) {
  const { setModeById } = useApp();
  const [holding, setHolding] = useState(false);
  const [index, setIndex] = useState(0);
  const holdingRef = useRef(false);

  const cycle = useCallback(() => {
    setIndex((i) => {
      const next = (i + 1) % modes.length;
      const m = modes[next];
      if (m?.storeId) setModeById(m.storeId);
      return next;
    });
  }, [modes, setModeById]);

  // real keyboard: while the demo "⌥⇧" is held, tapping K cycles
  useEffect(() => {
    holdingRef.current = holding;
  }, [holding]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (holdingRef.current && (e.key === "k" || e.key === "K")) {
        e.preventDefault();
        cycle();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [cycle]);

  const startHold = () => setHolding(true);
  const endHold = () => setHolding(false);

  return (
    <div className="vibrancy-menubar flex shrink-0 items-center gap-3 border-t border-separator px-6 py-2.5">
      <div className="flex shrink-0 items-center gap-1.5 text-[12px] text-2">
        <span>Try it: hold</span>
        <ShortcutKey keys="⌥⇧" />
        <span>and tap</span>
        <ShortcutKey keys="K" />
        <span>to cycle modes</span>
      </div>

      {/* simulated hold button */}
      <motion.button
        type="button"
        onPointerDown={startHold}
        onPointerUp={endHold}
        onPointerLeave={endHold}
        whileTap={{ scale: 0.97 }}
        transition={SPRING_MICRO}
        className={cn(
          "shrink-0 cursor-pointer select-none rounded-md px-2 py-1 font-mono text-[11px] font-medium hairline",
          holding ? "bg-accent-blue/25 text-accent-blue" : "bg-surface-2 text-2 hover:text-1"
        )}
      >
        Hold ⌥⇧
      </motion.button>
      <motion.button
        type="button"
        disabled={!holding}
        onClick={cycle}
        whileTap={holding ? { scale: 0.97 } : undefined}
        transition={SPRING_MICRO}
        className={cn(
          "shrink-0 rounded-md px-2 py-1 font-mono text-[11px] font-medium hairline",
          holding
            ? "cursor-pointer bg-accent-blue/25 text-accent-blue"
            : "cursor-default bg-surface-2 text-3 opacity-50"
        )}
      >
        K
      </motion.button>

      {/* pill carousel with sliding highlight */}
      <div className="flex min-w-0 flex-1 items-center gap-1 overflow-x-auto">
        {modes.map((m, i) => {
          const Icon = MODE_ICON_MAP[m.icon] ?? MODE_ICON_MAP.Sparkles;
          const highlighted = holding && i === index;
          return (
            <button
              key={m.id}
              type="button"
              onClick={() => {
                setIndex(i);
                if (m.storeId) setModeById(m.storeId);
              }}
              className="relative flex shrink-0 cursor-pointer items-center gap-1.5 rounded-full px-2.5 py-1"
            >
              {highlighted && (
                <motion.span
                  layoutId="mode-cycle-highlight"
                  transition={SPRING_MICRO}
                  className="absolute inset-0 rounded-full bg-accent-blue/25 ring-1 ring-accent-blue"
                />
              )}
              <Icon size={12} strokeWidth={2.2} style={{ color: m.color }} className="relative" />
              <span
                className={cn(
                  "relative text-[11px] font-semibold uppercase tracking-[0.02em]",
                  highlighted ? "text-1" : "text-2"
                )}
              >
                {m.name}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
