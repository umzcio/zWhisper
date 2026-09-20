import { useEffect, useRef } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { ChevronDown, Check } from "lucide-react";
import { cn } from "@/lib/utils";
import { MODES } from "@/lib/modes";
import type { Mode } from "@/lib/modes";
import { MODE_ICONS } from "@/components/modeIcons";

export function ModeIcon({ mode, size = 13 }: { mode: Mode; size?: number }) {
  const Icon = MODE_ICONS[mode.icon];
  return <Icon size={size} style={{ color: mode.color }} strokeWidth={2.2} />;
}

interface ModePillProps {
  mode: Mode;
  onClick?: () => void;
  className?: string;
  compact?: boolean;
}

/** Pill: mode icon + name + chevron */
export function ModePill({ mode, onClick, className, compact }: ModePillProps) {
  return (
    <motion.button
      type="button"
      onClick={onClick}
      whileHover={{ scale: 1.02 }}
      whileTap={{ scale: 0.97 }}
      transition={{ type: "spring", stiffness: 500, damping: 35 }}
      className={cn(
        "flex cursor-pointer items-center gap-1.5 rounded-full hairline",
        "bg-surface-2/80 hover:bg-surface-3/80",
        compact ? "px-2 py-0.5" : "px-2.5 py-1",
        className
      )}
    >
      <ModeIcon mode={mode} size={compact ? 11 : 13} />
      <span
        className={cn(
          "font-semibold uppercase text-1",
          compact ? "text-[10px]" : "text-xs tracking-[0.02em]"
        )}
      >
        {mode.name}
      </span>
      <ChevronDown size={compact ? 10 : 12} className="text-3" />
    </motion.button>
  );
}

interface ModeSwitcherProps {
  open: boolean;
  activeMode: Mode;
  onSelect: (mode: Mode) => void;
  onClose: () => void;
  className?: string;
}

/** Popover list of modes with ⌘1–⌘7 hints and spring check on active */
export function ModeSwitcher({ open, activeMode, onSelect, onClose, className }: ModeSwitcherProps) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: PointerEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) onClose();
    };
    window.addEventListener("pointerdown", onDown);
    return () => window.removeEventListener("pointerdown", onDown);
  }, [open, onClose]);

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          ref={ref}
          initial={{ opacity: 0, scale: 0.92, y: -6 }}
          animate={{ opacity: 1, scale: 1, y: 0 }}
          exit={{ opacity: 0, scale: 0.95, y: -4 }}
          transition={{ type: "spring", stiffness: 400, damping: 30 }}
          className={cn(
            "vibrancy w-56 rounded-[14px] p-1.5 shadow-popover hairline",
            className
          )}
        >
          {MODES.map((m) => {
            const active = m.id === activeMode.id;
            return (
              <motion.button
                key={m.id}
                type="button"
                whileTap={{ scale: 0.97 }}
                onClick={() => {
                  onSelect(m);
                  onClose();
                }}
                className={cn(
                  "flex w-full cursor-pointer items-center gap-2.5 rounded-md px-2 py-1.5 text-left",
                  active ? "bg-accent-blue/15" : "hover:bg-surface-3/60"
                )}
              >
                <span className="w-4">
                  {active && (
                    <motion.span
                      key={`${m.id}-${String(open)}`}
                      initial={{ scale: 0.5, opacity: 0 }}
                      animate={{ scale: 1, opacity: 1 }}
                      transition={{ type: "spring", stiffness: 500, damping: 35 }}
                      className="block"
                    >
                      <Check size={13} className="text-accent-blue" strokeWidth={3} />
                    </motion.span>
                  )}
                </span>
                <ModeIcon mode={m} size={14} />
                <span className="flex-1 text-[13px] font-medium text-1">{m.name}</span>
                <kbd className="font-mono text-[11px] font-medium text-3">{m.shortcut}</kbd>
              </motion.button>
            );
          })}
        </motion.div>
      )}
    </AnimatePresence>
  );
}
