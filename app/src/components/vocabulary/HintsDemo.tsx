import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { BookOpenText, RotateCcw, X } from "lucide-react";
import { cn } from "@/lib/utils";
import type { VocabWord } from "@/components/vocabulary/vocabData";
import { HINTS_DEMO_SENTENCE } from "@/components/vocabulary/vocabData";

const WORD_MS = 140;

interface HintsDemoProps {
  words: VocabWord[];
}

/** Interactive vocabulary-hints demo: mini teleprompter streams a scripted sentence;
    vocab words land as underlined accent chips that pop an info card when clicked. */
export default function HintsDemo({ words }: HintsDemoProps) {
  const tokens = useMemo(() => HINTS_DEMO_SENTENCE.split(" "), []);
  const vocabLookup = useMemo(() => {
    const map = new Map<string, VocabWord>();
    for (const w of words) map.set(w.word.toLowerCase(), w);
    return map;
  }, [words]);

  const [count, setCount] = useState(0);
  const [runId, setRunId] = useState(0);
  const [popped, setPopped] = useState<VocabWord | null>(null);
  const cardRef = useRef<HTMLDivElement>(null);

  /* stream words at 140ms */
  useEffect(() => {
    setCount(0);
    setPopped(null);
    const iv = window.setInterval(() => {
      setCount((c) => {
        if (c >= tokens.length) {
          window.clearInterval(iv);
          return c;
        }
        return c + 1;
      });
    }, WORD_MS);
    return () => window.clearInterval(iv);
  }, [runId, tokens.length]);

  /* dismiss popped card on outside click */
  useEffect(() => {
    if (!popped) return;
    const onDown = (e: PointerEvent) => {
      if (cardRef.current && !cardRef.current.contains(e.target as Node)) setPopped(null);
    };
    window.addEventListener("pointerdown", onDown);
    return () => window.removeEventListener("pointerdown", onDown);
  }, [popped]);

  const replay = useCallback(() => setRunId((n) => n + 1), []);

  const matchFor = (token: string): VocabWord | undefined => {
    const clean = token.replace(/[^\p{L}\p{N}'-]/gu, "").toLowerCase();
    return clean ? vocabLookup.get(clean) : undefined;
  };

  const done = count >= tokens.length;

  return (
    <div className="vibrancy rounded-[10px] p-3.5 hairline">
      <div className="flex items-start gap-3">
        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-[8px] bg-accent-purple/15 text-accent-purple">
          <BookOpenText size={15} />
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-[13px] font-semibold text-1">Vocabulary hints</p>
          <p className="mt-0.5 text-[12px] leading-snug text-2">
            While dictating, zWhisper shows clickable hints when it detects a custom word.
          </p>

          {/* mini teleprompter */}
          <div className="mt-2.5 flex min-h-9 flex-wrap items-center gap-x-1 gap-y-1 rounded-[8px] bg-stage/60 px-2.5 py-2 hairline">
            {tokens.slice(0, count).map((token, i) => {
              const match = matchFor(token);
              if (!match) {
                return (
                  <span key={`${runId}-${i}`} className="text-[13px] font-medium text-1">
                    {token}
                  </span>
                );
              }
              const punct = token.slice(match.word.length);
              return (
                <motion.button
                  key={`${runId}-${i}`}
                  type="button"
                  initial={{ y: 6, opacity: 0 }}
                  animate={{ y: 0, opacity: 1 }}
                  transition={{ type: "spring", stiffness: 500, damping: 35 }}
                  onClick={(e) => {
                    e.stopPropagation();
                    setPopped((p) => (p?.word === match.word ? null : match));
                  }}
                  className={cn(
                    "cursor-pointer rounded-[4px] px-1 text-[13px] font-medium underline decoration-accent-blue decoration-2 underline-offset-2",
                    popped?.word === match.word
                      ? "bg-accent-blue/20 text-accent-blue"
                      : "text-accent-blue hover:bg-accent-blue/10"
                  )}
                >
                  {match.word}
                  {punct}
                </motion.button>
              );
            })}
            {!done && (
              <span className="inline-block h-3.5 w-px animate-[zw-caret_1s_step-end_infinite] bg-accent-blue" />
            )}
          </div>

          {/* popped hint card + replay */}
          <div className="mt-2 flex items-center justify-between gap-2">
            <div className="min-h-7 flex-1">
              <AnimatePresence>
                {popped && (
                  <motion.div
                    ref={cardRef}
                    key={popped.word}
                    initial={{ scale: 0.9, opacity: 0, y: 4 }}
                    animate={{ scale: 1, opacity: 1, y: 0 }}
                    exit={{ scale: 0.95, opacity: 0 }}
                    transition={{ type: "spring", stiffness: 500, damping: 35 }}
                    className="inline-flex items-center gap-2 rounded-[8px] bg-surface-2 px-2.5 py-1.5 text-[12px] hairline"
                  >
                    <span className="font-semibold text-1">{popped.word}</span>
                    <span className="text-2">
                      — from your vocabulary · Used {popped.uses}×
                    </span>
                    <button
                      type="button"
                      aria-label="Dismiss hint"
                      onClick={() => setPopped(null)}
                      className="cursor-pointer text-3 hover:text-1"
                    >
                      <X size={11} />
                    </button>
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
            <motion.button
              type="button"
              onClick={replay}
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.97 }}
              transition={{ type: "spring", stiffness: 500, damping: 35 }}
              className="flex cursor-pointer items-center gap-1 rounded-[6px] hairline bg-surface-2 px-2 py-1 text-[11px] font-medium text-2 hover:bg-surface-3/60 hover:text-1"
            >
              <RotateCcw size={11} />
              Replay
            </motion.button>
          </div>
        </div>
      </div>
    </div>
  );
}
