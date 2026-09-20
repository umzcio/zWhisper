import { useEffect, useRef, useState } from "react";
import type { ReactNode } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Check, ChevronDown, Info } from "lucide-react";
import { cn } from "@/lib/utils";
import { playClick } from "@/components/settings/settingsState";

const MICRO = { type: "spring", stiffness: 500, damping: 35 } as const;

/* ---------------------------------- Group --------------------------------- */

/** Inset grouped-list card: --surface-2, 10px radius, hairline separators between rows. */
export function Group({ title, children }: { title?: string; children: ReactNode }) {
  return (
    <section>
      {title && (
        <h3 className="mb-1.5 px-1 text-[11px] font-semibold uppercase tracking-[0.06em] text-3">
          {title}
        </h3>
      )}
      <div className="hairline divide-y divide-separator overflow-hidden rounded-[10px] bg-surface-2">
        {children}
      </div>
    </section>
  );
}

/* ----------------------------------- Row ----------------------------------- */

export function Row({
  label,
  caption,
  control,
}: {
  label: ReactNode;
  caption?: ReactNode;
  control?: ReactNode;
}) {
  return (
    <div className="flex min-h-12 items-center justify-between gap-4 px-3.5 py-2">
      <div className="min-w-0">
        <div className="flex items-center gap-1.5 text-[13px] text-1">{label}</div>
        {caption && <p className="mt-0.5 text-[11px] leading-snug text-3">{caption}</p>}
      </div>
      {control && <div className="flex shrink-0 items-center">{control}</div>}
    </div>
  );
}

/* ---------------------------------- Switch --------------------------------- */

/** macOS-style switch: thumb spring 500/35, track color fades 150ms, 0.96 press scale. */
export function Switch({
  checked,
  onChange,
  ariaLabel,
}: {
  checked: boolean;
  onChange: (v: boolean) => void;
  ariaLabel?: string;
}) {
  return (
    <motion.button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={ariaLabel}
      onClick={() => {
        playClick();
        onChange(!checked);
      }}
      whileTap={{ scale: 0.96 }}
      transition={MICRO}
      className={cn(
        "relative h-[22px] w-[38px] shrink-0 cursor-pointer rounded-full transition-colors duration-150",
        checked ? "bg-accent-green" : "bg-surface-3"
      )}
    >
      <motion.span
        initial={false}
        animate={{ x: checked ? 18 : 2 }}
        transition={MICRO}
        className="absolute top-[2px] block h-[18px] w-[18px] rounded-full bg-white shadow-[0_1px_3px_rgba(0,0,0,0.4)]"
      />
    </motion.button>
  );
}

/* ----------------------------- Segmented control ---------------------------- */

export interface SegmentOption<T extends string> {
  value: T;
  label: ReactNode;
}

export function SegmentedControl<T extends string>({
  id,
  options,
  value,
  onChange,
  ariaLabel,
}: {
  /** unique namespace for the sliding indicator layoutId */
  id: string;
  options: SegmentOption<T>[];
  value: T;
  onChange: (v: T) => void;
  ariaLabel?: string;
}) {
  return (
    <div
      role="radiogroup"
      aria-label={ariaLabel}
      className="flex items-center rounded-[7px] bg-black/25 p-[2px]"
    >
      {options.map((opt) => {
        const active = opt.value === value;
        return (
          <motion.button
            key={opt.value}
            type="button"
            role="radio"
            aria-checked={active}
            onClick={() => {
              if (!active) {
                playClick();
                onChange(opt.value);
              }
            }}
            whileTap={{ scale: 0.96 }}
            transition={MICRO}
            className={cn(
              "relative cursor-pointer rounded-[5px] px-3 py-[3px] text-[12px] font-medium transition-colors duration-150",
              active ? "text-1" : "text-2 hover:text-1"
            )}
          >
            {active && (
              <motion.span
                layoutId={`zw-seg-${id}`}
                transition={MICRO}
                className="hairline absolute inset-0 rounded-[5px] bg-surface-3 shadow-[0_1px_3px_rgba(0,0,0,0.35)]"
              />
            )}
            <span className="relative z-10 flex items-center gap-1">{opt.label}</span>
          </motion.button>
        );
      })}
    </div>
  );
}

/* --------------------------------- Dropdown --------------------------------- */

export function Dropdown({
  options,
  value,
  onChange,
  ariaLabel,
  width = 200,
}: {
  options: SegmentOption<string>[];
  value: string;
  onChange: (v: string) => void;
  ariaLabel?: string;
  width?: number;
}) {
  const [open, setOpen] = useState(false);
  const active = options.find((o) => o.value === value);

  return (
    <div className="relative">
      <motion.button
        type="button"
        aria-label={ariaLabel}
        aria-expanded={open}
        onClick={() => {
          playClick();
          setOpen((o) => !o);
        }}
        whileTap={{ scale: 0.97 }}
        transition={MICRO}
        className="hairline flex cursor-pointer items-center justify-between gap-2 rounded-[6px] bg-surface-3/70 py-1 pl-2.5 pr-2 text-[12px] font-medium text-1 shadow-[0_1px_0_rgba(255,255,255,0.04)] hover:bg-surface-3"
        style={{ width }}
      >
        <span className="flex min-w-0 items-center gap-1.5 truncate">
          {active?.label ?? value}
        </span>
        <ChevronDown
          size={13}
          className={cn("shrink-0 text-3 transition-transform duration-150", open && "rotate-180")}
        />
      </motion.button>
      <AnimatePresence>
        {open && (
          <>
            <div
              className="fixed inset-0 z-40 cursor-default"
              onClick={() => setOpen(false)}
              aria-hidden
            />
            <motion.ul
              initial={{ opacity: 0, y: -4, scale: 0.98 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: -4, scale: 0.98 }}
              transition={{ duration: 0.15 }}
              className="hairline absolute right-0 z-50 mt-1 max-h-56 overflow-auto rounded-[8px] bg-surface-3 p-1 shadow-popover"
              style={{ width }}
              role="listbox"
            >
              {options.map((opt) => {
                const selected = opt.value === value;
                return (
                  <li key={opt.value}>
                    <button
                      type="button"
                      role="option"
                      aria-selected={selected}
                      onClick={() => {
                        playClick();
                        onChange(opt.value);
                        setOpen(false);
                      }}
                      className={cn(
                        "flex w-full cursor-pointer items-center gap-1.5 rounded-[5px] px-2 py-1 text-left text-[12px]",
                        selected ? "text-1" : "text-2 hover:bg-surface-2 hover:text-1"
                      )}
                    >
                      <Check
                        size={12}
                        strokeWidth={3}
                        className={cn("shrink-0 text-accent-blue", selected ? "opacity-100" : "opacity-0")}
                      />
                      <span className="flex min-w-0 items-center gap-1.5 truncate">{opt.label}</span>
                    </button>
                  </li>
                );
              })}
            </motion.ul>
          </>
        )}
      </AnimatePresence>
    </div>
  );
}

/* ---------------------------------- Slider --------------------------------- */

/** Slider with spring-feel thumb (scales 1.15 while dragging) and a value bubble that follows the thumb. */
export function Slider({
  value,
  onChange,
  min = 0,
  max = 100,
  disabled = false,
  ariaLabel,
}: {
  value: number;
  onChange: (v: number) => void;
  min?: number;
  max?: number;
  disabled?: boolean;
  ariaLabel?: string;
}) {
  const trackRef = useRef<HTMLDivElement>(null);
  const [dragging, setDragging] = useState(false);
  const pct = ((value - min) / (max - min)) * 100;

  const setFromClientX = (clientX: number) => {
    const track = trackRef.current;
    if (!track) return;
    const rect = track.getBoundingClientRect();
    const p = Math.min(1, Math.max(0, (clientX - rect.left) / rect.width));
    onChange(Math.round(min + p * (max - min)));
  };

  useEffect(() => {
    if (!dragging) return;
    const move = (e: PointerEvent) => setFromClientX(e.clientX);
    const up = () => setDragging(false);
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
    return () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dragging, min, max]);

  return (
    <div
      ref={trackRef}
      role="slider"
      aria-label={ariaLabel}
      aria-valuemin={min}
      aria-valuemax={max}
      aria-valuenow={value}
      onPointerDown={(e) => {
        if (disabled) return;
        playClick();
        setDragging(true);
        setFromClientX(e.clientX);
      }}
      className={cn(
        "relative flex h-5 w-44 touch-none items-center",
        disabled ? "cursor-default opacity-40" : "cursor-pointer"
      )}
    >
      <div className="h-[4px] w-full rounded-full bg-surface-3" />
      <div
        className="absolute left-0 h-[4px] rounded-full bg-accent-blue"
        style={{ width: `${pct}%` }}
      />
      {/* value bubble follows the thumb */}
      <AnimatePresence>
        {dragging && (
          <motion.div
            initial={{ opacity: 0, y: 3, scale: 0.85 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 3, scale: 0.85 }}
            transition={{ duration: 0.12 }}
            className="pointer-events-none absolute -top-6 z-10 -translate-x-1/2 rounded-[5px] bg-surface-3 px-1.5 py-0.5 font-mono text-[10px] font-medium text-1 shadow-popover hairline"
            style={{ left: `${pct}%` }}
          >
            {value}
          </motion.div>
        )}
      </AnimatePresence>
      <motion.div
        animate={{ scale: dragging ? 1.15 : 1 }}
        transition={MICRO}
        className="absolute h-4 w-4 -translate-x-1/2 rounded-full bg-white shadow-[0_1px_4px_rgba(0,0,0,0.45)]"
        style={{ left: `${pct}%` }}
      />
    </div>
  );
}

/* ---------------------------------- InfoTip --------------------------------- */

/** Info dot with a hover tooltip bubble. */
export function InfoTip({ text }: { text: string }) {
  return (
    <span className="group relative inline-flex cursor-default items-center">
      <Info size={13} className="text-3 transition-colors group-hover:text-2" />
      <span className="hairline pointer-events-none absolute bottom-full left-1/2 z-40 mb-1.5 w-48 -translate-x-1/2 rounded-[6px] bg-surface-3 px-2 py-1.5 text-[11px] leading-snug text-2 opacity-0 shadow-popover transition-opacity duration-150 group-hover:opacity-100">
        {text}
      </span>
    </span>
  );
}
