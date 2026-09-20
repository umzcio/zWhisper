import { memo, useEffect, useRef } from "react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import Lenis from "lenis";
import { cn } from "@/lib/utils";
import type { TimedParagraph } from "@/components/history/historyData";
import { formatTimestamp } from "@/components/history/historyData";

interface TranscriptViewProps {
  paragraphs: TimedParagraph[];
  /** global index of the word currently being played (-1 = none) */
  activeWord: number;
  /** seek when a word is clicked */
  onWordClick: (t: number) => void;
  /** purple shimmer sweep while reprocessing */
  shimmering: boolean;
  /** change to trigger the reprocess morph (out: fade/slide, in: stagger) */
  versionKey: string;
}

/**
 * Flowing-paragraph transcript with word-level timestamps.
 * Every word is a hoverable/clickable token; clicking seeks playback.
 * During playback the current word highlights in accent and auto-scrolls
 * to stay centered (Lenis-smoothed scrollTo).
 */
const TranscriptView = memo(function TranscriptView({
  paragraphs,
  activeWord,
  onWordClick,
  shimmering,
  versionKey,
}: TranscriptViewProps) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const lenisRef = useRef<Lenis | null>(null);
  const reduced = useReducedMotion();

  // Lenis-smoothed scrolling inside the transcript pane
  useEffect(() => {
    const wrapper = scrollRef.current;
    const content = wrapper?.firstElementChild as HTMLElement | null;
    if (!wrapper || !content) return;
    const lenis = new Lenis({ wrapper, content, duration: 0.8, smoothWheel: true });
    lenisRef.current = lenis;
    let raf = 0;
    const loop = (time: number) => {
      lenis.raf(time);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => {
      cancelAnimationFrame(raf);
      lenis.destroy();
      lenisRef.current = null;
    };
  }, []);

  // keep the current word centered during playback
  useEffect(() => {
    if (activeWord < 0) return;
    const wrapper = scrollRef.current;
    const el = wrapper?.querySelector(`[data-w="${activeWord}"]`);
    if (!wrapper || !el) return;
    lenisRef.current?.scrollTo(el as HTMLElement, {
      offset: -(wrapper.clientHeight / 2 - 24),
      duration: 0.5,
    });
  }, [activeWord]);

  return (
    <div ref={scrollRef} className="relative min-h-0 flex-1 overflow-y-auto px-5 py-4">
      <div>
        <AnimatePresence mode="wait" initial={false}>
          <motion.div
            key={versionKey}
            initial="hidden"
            animate="show"
            exit={reduced ? { opacity: 0 } : { opacity: 0, y: -8, transition: { duration: 0.25 } }}
            variants={{
              hidden: {},
              show: { transition: { staggerChildren: 0.03 } },
            }}
            className={cn("space-y-3", shimmering && "shimmer-text")}
          >
            {paragraphs.map((p, pi) => (
              <motion.p
                key={pi}
                variants={{
                  hidden: reduced ? { opacity: 0 } : { opacity: 0, y: 8 },
                  show: { opacity: 1, y: 0, transition: { duration: 0.3, ease: "easeOut" } },
                }}
                className="text-[15px] font-medium leading-relaxed tracking-[-0.01em] text-1"
              >
                {p.words.map((word) => {
                  const isActive = word.gi === activeWord;
                  return (
                    <span key={word.gi} className="group relative inline-block">
                      {/* timestamps rail on hover */}
                      <span
                        className={cn(
                          "pointer-events-none absolute -top-6 left-1/2 z-10 -translate-x-1/2",
                          "rounded-md hairline bg-surface-2 px-1.5 py-0.5 shadow-popover",
                          "font-mono text-[11px] text-2 tabular-nums whitespace-nowrap",
                          "opacity-0 transition-opacity duration-100 group-hover:opacity-100"
                        )}
                      >
                        {formatTimestamp(word.t)}
                      </span>
                      <button
                        type="button"
                        data-w={word.gi}
                        onClick={() => onWordClick(word.t)}
                        className={cn(
                          "cursor-pointer rounded px-0.5 -mx-0.5 transition-colors [transition-duration:120ms]",
                          "hover:bg-surface-3",
                          isActive && "bg-accent-blue/20 text-accent-blue"
                        )}
                      >
                        {word.w}
                      </button>{" "}
                    </span>
                  );
                })}
              </motion.p>
            ))}
          </motion.div>
        </AnimatePresence>
      </div>
    </div>
  );
});

export default TranscriptView;
