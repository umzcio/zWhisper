import { useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Settings2, Check } from "lucide-react";
import { cn } from "@/lib/utils";

interface ApiKeyPopoverProps {
  provider: string;
  saved: boolean;
  onSave: () => void;
}

/** Gear button → small popover with a masked API-key input (BYOK simulation) */
export default function ApiKeyPopover({ provider, saved, onSave }: ApiKeyPopoverProps) {
  const [open, setOpen] = useState(false);
  const [value, setValue] = useState("");
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
    <div ref={ref} className="relative">
      <motion.button
        type="button"
        aria-label={`${provider} API key settings`}
        onClick={(e) => {
          e.stopPropagation();
          setOpen((o) => !o);
        }}
        whileTap={{ scale: 0.9 }}
        transition={{ type: "spring", stiffness: 500, damping: 35 }}
        className={cn(
          "flex h-7 w-7 cursor-pointer items-center justify-center rounded-md hover:bg-surface-3/70",
          saved ? "text-accent-green" : "text-3 hover:text-2"
        )}
      >
        {saved ? <Check size={14} /> : <Settings2 size={14} />}
      </motion.button>
      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, scale: 0.92, y: -4 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.95, y: -4 }}
            transition={{ type: "spring", stiffness: 400, damping: 30 }}
            className="vibrancy absolute right-0 top-8 z-30 w-60 rounded-[10px] p-3 shadow-popover hairline"
            onClick={(e) => e.stopPropagation()}
          >
            <p className="mb-1.5 text-[11px] font-semibold uppercase tracking-[0.02em] text-3">
              {provider} API Key
            </p>
            <input
              type="password"
              value={value}
              onChange={(e) => setValue(e.target.value)}
              placeholder="sk-…••••"
              autoFocus
              onKeyDown={(e) => {
                if (e.key === "Enter" && value.trim()) {
                  onSave();
                  setValue("");
                  setOpen(false);
                }
              }}
              className="mb-2 w-full rounded-[6px] hairline bg-surface-2 px-2 py-1.5 font-mono text-[12px] text-1 outline-none placeholder:text-3 focus:ring-1 focus:ring-accent-blue"
            />
            <motion.button
              type="button"
              disabled={!value.trim()}
              onClick={() => {
                onSave();
                setValue("");
                setOpen(false);
              }}
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.97 }}
              transition={{ type: "spring", stiffness: 500, damping: 35 }}
              className="w-full cursor-pointer rounded-[6px] bg-accent-blue py-1.5 text-[12px] font-semibold text-white disabled:cursor-default disabled:opacity-40"
            >
              Save
            </motion.button>
            <p className="mt-1.5 text-[10px] text-3">Stored locally, never uploaded.</p>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
