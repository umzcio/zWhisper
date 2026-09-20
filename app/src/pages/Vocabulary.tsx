import { useCallback, useRef, useState } from "react";
import { motion } from "framer-motion";
import { Plus } from "lucide-react";
import TrafficLights from "@/components/TrafficLights";
import SidebarNav from "@/components/SidebarNav";
import WordChipField from "@/components/vocabulary/WordChipField";
import ReplacementsTable from "@/components/vocabulary/ReplacementsTable";
import HintsDemo from "@/components/vocabulary/HintsDemo";
import VocabToast from "@/components/vocabulary/VocabToast";
import { DEFAULT_VOCAB_WORDS, DEFAULT_REPLACEMENTS } from "@/components/vocabulary/vocabData";
import type { VocabWord, TextReplacement } from "@/components/vocabulary/vocabData";

const TOAST_MSG = "Vocabulary updated — applies to your next dictation";

const sectionVariants = {
  hidden: { opacity: 0, y: 16 },
  show: {
    opacity: 1,
    y: 0,
    transition: { type: "spring" as const, stiffness: 400, damping: 30 },
  },
};

let replacementSeq = DEFAULT_REPLACEMENTS.length;

export default function Vocabulary() {
  const [words, setWords] = useState<VocabWord[]>(DEFAULT_VOCAB_WORDS);
  const [replacements, setReplacements] = useState<TextReplacement[]>(DEFAULT_REPLACEMENTS);
  const [focusRowId, setFocusRowId] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const toastTimer = useRef<number | undefined>(undefined);

  const showToast = useCallback(() => {
    setToast(TOAST_MSG);
    window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast(null), 3000);
  }, []);

  const addWord = useCallback(
    (word: string): boolean => {
      const exists = words.some((w) => w.word.toLowerCase() === word.toLowerCase());
      if (exists) return false;
      setWords((prev) => [...prev, { word, uses: 0, lastUsed: "never" }]);
      showToast();
      return true;
    },
    [words, showToast]
  );

  const removeWord = useCallback(
    (word: string) => {
      setWords((prev) => prev.filter((w) => w.word !== word));
      showToast();
    },
    [showToast]
  );

  const addReplacement = useCallback(() => {
    replacementSeq += 1;
    const id = `r${replacementSeq}-${Date.now()}`;
    setReplacements((prev) => [...prev, { id, trigger: "", replacement: "" }]);
    setFocusRowId(id);
  }, []);

  const updateReplacement = useCallback(
    (id: string, field: "trigger" | "replacement", value: string) => {
      setReplacements((prev) =>
        prev.map((r) => (r.id === id ? { ...r, [field]: value } : r))
      );
      showToast();
    },
    [showToast]
  );

  const deleteReplacement = useCallback(
    (id: string) => {
      setReplacements((prev) => prev.filter((r) => r.id !== id));
      showToast();
    },
    [showToast]
  );

  return (
    <div className="flex h-full items-center justify-center p-4">
      <motion.div
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.25 }}
        className="vibrancy relative flex h-[640px] w-[960px] max-w-full flex-col overflow-hidden rounded-[12px] shadow-window hairline"
      >
        {/* title bar */}
        <div className="flex h-7 shrink-0 items-center border-b border-separator px-3">
          <TrafficLights />
          <span className="flex-1 text-center text-[13px] font-semibold tracking-[-0.01em] text-2">
            Vocabulary
          </span>
          <span className="w-[52px]" />
        </div>

        <div className="flex min-h-0 flex-1">
          <SidebarNav />

          <div className="relative min-w-0 flex-1 overflow-y-auto">
            <motion.div
              variants={{ hidden: {}, show: { transition: { staggerChildren: 0.08 } } }}
              initial="hidden"
              animate="show"
              className="flex flex-col gap-5 px-5 py-4"
            >
              {/* Custom Words */}
              <motion.section variants={sectionVariants}>
                <div className="mb-2.5">
                  <h1 className="text-[20px] font-bold tracking-[-0.02em] text-1">
                    Custom Words
                  </h1>
                  <p className="mt-0.5 text-[12px] text-2">
                    Names, jargon, and terms the model should always recognize.
                  </p>
                </div>
                <WordChipField words={words} onAdd={addWord} onRemove={removeWord} />
              </motion.section>

              {/* Text Replacements */}
              <motion.section variants={sectionVariants}>
                <div className="mb-2.5 flex items-start justify-between gap-2">
                  <div>
                    <h2 className="text-[20px] font-bold tracking-[-0.02em] text-1">
                      Text Replacements
                    </h2>
                    <p className="mt-0.5 text-[12px] text-2">
                      Automatically swap phrases during processing.
                    </p>
                  </div>
                  <motion.button
                    type="button"
                    onClick={addReplacement}
                    whileHover={{ scale: 1.02 }}
                    whileTap={{ scale: 0.97 }}
                    transition={{ type: "spring", stiffness: 500, damping: 35 }}
                    className="flex shrink-0 cursor-pointer items-center gap-1 rounded-[6px] hairline bg-surface-2 px-2.5 py-1.5 text-[12px] font-medium text-1 hover:bg-surface-3/70"
                  >
                    <Plus size={12} strokeWidth={2.5} />
                    Add replacement
                  </motion.button>
                </div>
                <ReplacementsTable
                  rows={replacements}
                  focusRowId={focusRowId}
                  onFocused={() => setFocusRowId(null)}
                  onUpdate={updateReplacement}
                  onDelete={deleteReplacement}
                />
              </motion.section>

              {/* Vocabulary Hints demo */}
              <motion.section variants={sectionVariants} className="pb-1">
                <HintsDemo words={words} />
              </motion.section>
            </motion.div>

            <VocabToast message={toast} />
          </div>
        </div>
      </motion.div>
    </div>
  );
}
