import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Check, Undo2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { MODES } from "@/lib/modes";
import type { Mode } from "@/lib/modes";
import { ModeIcon } from "@/components/ModeSwitcher";

interface ReprocessBarProps {
  /** mode the entry is currently rendered with (excluded from Apply) */
  currentModeId: string;
  onApply: (mode: Mode) => void;
  /** set when a reprocess just completed — shows the reversible banner */
  bannerMode: Mode | null;
  onUndo: () => void;
  /** briefly highlight the bar when the row quick-action opens it */
  focused: boolean;
}

/** Bottom frosted bar: "Reprocess with…" + mode chip row + Apply, plus Undo banner. */
export default function ReprocessBar({
  currentModeId,
  onApply,
  bannerMode,
  onUndo,
  focused,
}: ReprocessBarProps) {
  const [picked, setPicked] = useState<Mode | null>(null);
  const ref = useRef<HTMLDivElement>(null);

  // pulse-scroll into view when the list-row quick action targets this bar
  useEffect(() => {
    if (focused) ref.current?.scrollIntoView({ block: "nearest" });
  }, [focused]);

  return (
    <div className="shrink-0 border-t border-separator bg-surface-2/40 backdrop-blur-xl">
      {/* reversible banner */}
      <AnimatePresence>
        {bannerMode && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.25 }}
            className="overflow-hidden"
          >
            <div className="flex items-center gap-2 border-b border-separator bg-accent-purple/10 px-4 py-2">
              <ModeIcon mode={bannerMode} size={13} />
              <span className="flex-1 text-xs text-1">
                Reprocessed with <span className="font-semibold">{bannerMode.name}</span>
              </span>
              <motion.button
                type="button"
                onClick={onUndo}
                whileTap={{ scale: 0.97 }}
                transition={{ type: "spring", stiffness: 500, damping: 35 }}
                className="flex cursor-pointer items-center gap-1 rounded-md px-2 py-0.5 text-xs font-medium text-accent-blue hover:bg-accent-blue/10"
              >
                <Undo2 size={12} />
                Undo
              </motion.button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      <div
        ref={ref}
        className={cn(
          "flex items-center gap-2 px-4 py-2.5 transition-colors duration-300",
          focused && "bg-accent-blue/5"
        )}
      >
        <span className="shrink-0 text-xs font-medium text-2">Reprocess with…</span>
        <div className="flex min-w-0 flex-1 items-center gap-1 overflow-x-auto">
          {MODES.map((m) => {
            const isCurrent = m.id === currentModeId;
            const isPicked = picked?.id === m.id;
            return (
              <motion.button
                key={m.id}
                type="button"
                disabled={isCurrent}
                onClick={() => setPicked(isPicked ? null : m)}
                whileHover={isCurrent ? undefined : { scale: 1.02 }}
                whileTap={isCurrent ? undefined : { scale: 0.97 }}
                transition={{ type: "spring", stiffness: 500, damping: 35 }}
                className={cn(
                  "flex shrink-0 items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium hairline",
                  isCurrent
                    ? "cursor-default bg-surface-3/50 text-3"
                    : isPicked
                      ? "border-transparent bg-accent-blue/20 text-accent-blue"
                      : "cursor-pointer bg-surface-2 text-2 hover:bg-surface-3 hover:text-1"
                )}
                title={isCurrent ? "Current mode" : `Reprocess with ${m.name}`}
              >
                <ModeIcon mode={m} size={11} />
                {m.name}
                {isPicked && <Check size={10} strokeWidth={3} />}
              </motion.button>
            );
          })}
        </div>
        <motion.button
          type="button"
          disabled={!picked}
          onClick={() => {
            if (picked) onApply(picked);
            setPicked(null);
          }}
          whileHover={picked ? { scale: 1.02 } : undefined}
          whileTap={picked ? { scale: 0.97 } : undefined}
          transition={{ type: "spring", stiffness: 500, damping: 35 }}
          className={cn(
            "shrink-0 rounded-md px-3 py-1 text-xs font-semibold",
            picked
              ? "cursor-pointer bg-accent-blue text-white"
              : "cursor-default bg-surface-3/60 text-3"
          )}
        >
          Apply
        </motion.button>
      </div>
    </div>
  );
}
