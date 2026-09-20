import { useState } from "react";
import type { FormEvent } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { X, Plus } from "lucide-react";
import { cn } from "@/lib/utils";
import type { VocabWord } from "@/components/vocabulary/vocabData";

interface WordChipFieldProps {
  words: VocabWord[];
  /** return false when the word is a duplicate (input shakes) */
  onAdd: (word: string) => boolean;
  onRemove: (word: string) => void;
}

/** Chip field of custom words + add input. Chips pop in, scale out, reflow with layout. */
export default function WordChipField({ words, onAdd, onRemove }: WordChipFieldProps) {
  const [draft, setDraft] = useState("");
  const [shake, setShake] = useState(0);
  const [dupError, setDupError] = useState(false);

  const submit = (e: FormEvent) => {
    e.preventDefault();
    const word = draft.trim();
    if (!word) return;
    const ok = onAdd(word);
    if (ok) {
      setDraft("");
      setDupError(false);
    } else {
      setShake((n) => n + 1);
      setDupError(true);
      window.setTimeout(() => setDupError(false), 900);
    }
  };

  return (
    <div>
      {/* add input */}
      <form onSubmit={submit} className="flex items-center gap-2">
        <motion.div
          key={shake}
          animate={shake > 0 ? { x: [0, -6, 6, -6, 6, 0] } : undefined}
          transition={{ duration: 0.3 }}
          className="flex-1"
        >
          <input
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder="Add a word…"
            className={cn(
              "w-full rounded-[6px] hairline bg-surface-2 px-2.5 py-1.5 text-[13px] text-1 outline-none placeholder:text-3",
              dupError
                ? "ring-1 ring-accent-red"
                : "focus:ring-1 focus:ring-accent-blue"
            )}
          />
        </motion.div>
        <motion.button
          type="submit"
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.97 }}
          transition={{ type: "spring", stiffness: 500, damping: 35 }}
          className="flex cursor-pointer items-center gap-1 rounded-[6px] bg-accent-blue px-3 py-1.5 text-[13px] font-semibold text-white"
        >
          <Plus size={13} strokeWidth={2.5} />
          Add
        </motion.button>
      </form>

      {/* chip field */}
      <div className="mt-3 flex flex-wrap gap-1.5">
        <AnimatePresence mode="popLayout">
          {words.map((w) => (
            <motion.span
              key={w.word}
              layout
              initial={{ scale: 0.6, opacity: 0, backgroundColor: "rgba(10, 132, 255, 0.35)" }}
              animate={{ scale: 1, opacity: 1, backgroundColor: "var(--surface-2)" }}
              exit={{ scale: 0.6, opacity: 0 }}
              transition={{ type: "spring", stiffness: 500, damping: 35 }}
              className="group relative inline-flex cursor-default items-center gap-1 rounded-[6px] px-2 py-1 text-[13px] font-medium text-1 hairline"
            >
              {w.word}
              <button
                type="button"
                aria-label={`Remove ${w.word}`}
                onClick={() => onRemove(w.word)}
                className="flex h-3.5 w-3.5 cursor-pointer items-center justify-center rounded-full text-3 opacity-0 transition-opacity hover:bg-accent-red/20 hover:text-accent-red group-hover:opacity-100"
              >
                <X size={10} strokeWidth={3} />
              </button>
              {/* hover tooltip */}
              <span className="pointer-events-none absolute -top-7 left-1/2 z-20 -translate-x-1/2 whitespace-nowrap rounded-md bg-surface-3 px-2 py-0.5 text-[11px] font-medium text-1 opacity-0 shadow-popover transition-opacity duration-150 group-hover:opacity-100">
                {w.uses > 0 ? `Used ${w.uses}× · last: ${w.lastUsed}` : "Not used yet"}
              </span>
            </motion.span>
          ))}
        </AnimatePresence>
        {words.length === 0 && (
          <span className="py-1 text-[12px] text-3">No custom words yet — add one above.</span>
        )}
      </div>
    </div>
  );
}
