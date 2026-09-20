import { useCallback, useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Mic, HelpCircle, RotateCcw, Undo2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { useApp } from "@/lib/store";
import { MODES } from "@/lib/modes";
import type { Mode } from "@/lib/modes";
import { useMockTranscriptionEngine } from "@/lib/mockEngine";
import RecordingPopover from "@/components/RecordingPopover";
import TrafficLights from "@/components/TrafficLights";
import ShortcutKey from "@/components/ShortcutKey";
import Footer from "@/components/Footer";
import { ModeIcon } from "@/components/ModeSwitcher";

const SEED_NOTES = `Project sync — Tuesday

We walked through the onboarding flow and the new dashboard empty states. Priya flagged that the migration comms need to go out before the API cutover, and Alex will confirm the timeline once the staging environment is stable.

Next review is Thursday afternoon, ahead of the stakeholder demo.`;

interface Toast {
  mode: Mode;
  words: number;
  seconds: number;
  note?: string;
}

const SPRING = { type: "spring", stiffness: 400, damping: 30 } as const;

export default function Home() {
  const { mode, setMode, popoverOpen, setPopoverOpen } = useApp();
  const [notes, setNotes] = useState(SEED_NOTES);
  const [toast, setToast] = useState<Toast | null>(null);
  const [hintDismissed, setHintDismissed] = useState(false);
  const [hintRecalled, setHintRecalled] = useState(false);
  const [holdActive, setHoldActive] = useState(false);
  const [shakeSignal, setShakeSignal] = useState(0);
  const [bounce, setBounce] = useState(0);

  const stageRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const holdRef = useRef(false);
  const typingRef = useRef<number | null>(null);
  const pasteRange = useRef<{ start: number; len: number } | null>(null);
  const preClipboard = useRef<string>("");
  const closeTimer = useRef<number | null>(null);
  const demoTimers = useRef<number[]>([]);
  const interacted = useRef(false);
  const phaseRef = useRef("idle");

  const stopTyping = () => {
    if (typingRef.current !== null) {
      window.clearInterval(typingRef.current);
      typingRef.current = null;
    }
  };

  const typeIntoNotes = useCallback((text: string, at?: number) => {
    stopTyping();
    const el = textareaRef.current;
    setNotes((current) => {
      const pos = at ?? (el ? el.selectionStart : current.length);
      pasteRange.current = { start: pos, len: 0 };
      let i = 0;
      typingRef.current = window.setInterval(() => {
        i += 1;
        setNotes((c) => {
          const p = pasteRange.current!;
          const next = c.slice(0, p.start) + text.slice(0, i) + c.slice(p.start + p.len);
          const added = text.slice(0, i).length - p.len;
          pasteRange.current = { start: p.start, len: p.len + added };
          if (i >= text.length) stopTyping();
          return next;
        });
      }, 8);
      return current;
    });
  }, []);

  const engine = useMockTranscriptionEngine({
    onPhaseChange: (p) => {
      phaseRef.current = p;
    },
    onPaste: (text) => {
      preClipboard.current = "(previous clipboard)";
      typeIntoNotes(text);
      window.setTimeout(() => {
        setPopoverOpen(false);
        setBounce((b) => b + 1);
      }, 700);
    },
    onComplete: (_text, m, stats) => {
      setHintDismissed(true);
      setToast({ mode: m, words: stats.words, seconds: stats.seconds });
      window.setTimeout(() => setToast((t) => (t ? null : t)), 6000);
    },
  });

  const startRecording = useCallback(
    (m: Mode = mode) => {
      setPopoverOpen(true);
      setToast(null);
      engine.start(m);
    },
    [engine, mode, setPopoverOpen]
  );

  const cancelAll = useCallback(() => {
    if (engine.phase === "recording" || engine.phase === "transcribing" || engine.phase === "processing") {
      engine.cancel();
    }
    setShakeSignal((s) => s + 1);
    setHoldActive(false);
    holdRef.current = false;
    if (closeTimer.current) window.clearTimeout(closeTimer.current);
    closeTimer.current = window.setTimeout(() => {
      setPopoverOpen(false);
      engine.reset();
    }, 420);
  }, [engine, setPopoverOpen]);

  // ---- keyboard: hold-to-talk Space, toggle ⌥⇧Space, Esc cancel, ⌘1–7 modes ----
  useEffect(() => {
    const isEditable = (t: EventTarget | null) =>
      t instanceof HTMLElement && (t.tagName === "TEXTAREA" || t.tagName === "INPUT");

    const onKeyDown = (e: KeyboardEvent) => {
      interacted.current = true;
      if ((e.metaKey || e.ctrlKey) && /^[1-7]$/.test(e.key)) {
        e.preventDefault();
        const m = MODES[Number(e.key) - 1];
        if (m) {
          setMode(m);
          if (phaseRef.current === "recording") engine.start(m);
        }
        return;
      }
      if (e.key === "Escape") {
        if (popoverOpen) {
          e.preventDefault();
          cancelAll();
        }
        return;
      }
      if (isEditable(e.target)) return;
      if (e.code === "Space" && e.altKey && e.shiftKey) {
        e.preventDefault();
        if (phaseRef.current === "recording") engine.stop();
        else if (phaseRef.current === "idle") startRecording();
        return;
      }
      if (e.code === "Space" && !e.altKey && !e.shiftKey && !e.metaKey && !e.ctrlKey && !e.repeat) {
        if (phaseRef.current === "idle") {
          e.preventDefault();
          holdRef.current = true;
          setHoldActive(true);
          startRecording();
        }
      }
    };
    const onKeyUp = (e: KeyboardEvent) => {
      if (e.code === "Space" && holdRef.current) {
        e.preventDefault();
        holdRef.current = false;
        setHoldActive(false);
        if (phaseRef.current === "recording") engine.stop();
      }
    };
    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("keyup", onKeyUp);
    return () => {
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("keyup", onKeyUp);
    };
  }, [popoverOpen, cancelAll, engine, setMode, startRecording]);

  // ---- scripted auto-demo: summon after 800ms idle, 6s dictation, skippable ----
  useEffect(() => {
    const d = demoTimers.current;
    d.push(window.setTimeout(() => {
      if (interacted.current) return;
      setPopoverOpen(true);
      engine.start(mode);
      d.push(window.setTimeout(() => {
        if (!interacted.current && phaseRef.current === "recording") engine.stop();
      }, 6000));
    }, 800));
    const skip = () => {
      interacted.current = true;
    };
    window.addEventListener("pointerdown", skip, { once: true });
    window.addEventListener("keydown", skip, { once: true });
    return () => {
      d.forEach((t) => window.clearTimeout(t));
      window.removeEventListener("pointerdown", skip);
      window.removeEventListener("keydown", skip);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => () => stopTyping(), []);

  const undoPaste = () => {
    stopTyping();
    const p = pasteRange.current;
    if (p) {
      setNotes((c) => c.slice(0, p.start) + c.slice(p.start + p.len));
      pasteRange.current = null;
    }
    setToast((t) => (t ? { ...t, note: "Clipboard restored" } : t));
    window.setTimeout(() => setToast(null), 1800);
  };

  const reprocess = () => {
    const p = pasteRange.current;
    const idx = MODES.findIndex((m) => m.id === mode.id);
    const next = MODES[(idx + 1) % MODES.length];
    setMode(next);
    const at = p ? p.start : undefined;
    if (p) {
      setNotes((c) => c.slice(0, p.start) + c.slice(p.start + p.len));
    }
    window.setTimeout(() => typeIntoNotes(next.processed, at), 30);
    setToast(null);
  };

  const hintVisible = !hintDismissed || hintRecalled;

  return (
    <div ref={stageRef} className="relative h-full w-full overflow-hidden">
      {/* Demo Notes window (TextEdit.app) */}
      <motion.div
        initial={{ opacity: 0, scale: 0.96 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ ...SPRING, delay: 0.25 }}
        className={cn(
          "vibrancy absolute left-[8%] top-[10%] flex h-[480px] w-[640px] flex-col",
          "overflow-hidden rounded-[12px] shadow-window hairline",
          "ring-1 ring-accent-blue/30"
        )}
      >
        <div className="flex h-7 shrink-0 items-center border-b border-separator px-3">
          <TrafficLights onClose={() => textareaRef.current?.blur()} />
          <span className="flex-1 text-center text-[13px] font-semibold tracking-[-0.01em] text-2">
            Meeting follow-up — Notes
          </span>
          <span className="w-[52px]" />
        </div>
        <textarea
          ref={textareaRef}
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          spellCheck={false}
          className={cn(
            "flex-1 resize-none bg-transparent p-4 text-[13px] leading-relaxed text-1",
            "caret-[color:var(--zw-accent)] outline-none placeholder:text-3"
          )}
          placeholder="Start typing, or dictate with zWhisper…"
        />
        <div className="flex h-6 shrink-0 items-center justify-between border-t border-separator px-3 text-[11px] text-3">
          <span>TextEdit.app — demo target</span>
          <span className="font-mono">{notes.split(/\s+/).filter(Boolean).length} words</span>
        </div>
      </motion.div>

      {/* Recording popover (hero) */}
      <RecordingPopover
        open={popoverOpen}
        engine={engine}
        mode={mode}
        onModeChange={(m) => {
          setMode(m);
          if (engine.phase === "recording") engine.start(m);
        }}
        onStart={() => startRecording()}
        onStop={() => engine.stop()}
        onCancel={cancelAll}
        onDismiss={() => setPopoverOpen(false)}
        holdActive={holdActive}
        shakeSignal={shakeSignal}
        stageRef={stageRef}
      />

      {/* Hint bar */}
      <AnimatePresence>
        {hintVisible && (
          <motion.div
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 8 }}
            transition={{ ...SPRING, delay: hintRecalled ? 0 : 0.5 }}
            className="vibrancy-menubar absolute bottom-20 left-1/2 z-20 flex -translate-x-1/2 items-center gap-3 rounded-full px-4 py-2 hairline"
          >
            <button
              type="button"
              onPointerDown={() => {
                if (phaseRef.current !== "idle") return;
                holdRef.current = true;
                setHoldActive(true);
                startRecording();
              }}
              onPointerUp={() => {
                if (holdRef.current) {
                  holdRef.current = false;
                  setHoldActive(false);
                  engine.stop();
                }
              }}
              className="flex cursor-pointer items-center gap-1.5 text-[12px] text-2 hover:text-1"
            >
              <span className="flex h-5 w-5 items-center justify-center rounded-full bg-accent-red text-white">
                <Mic size={11} />
              </span>
              <ShortcutKey keys="Hold Space" /> Push to talk
            </button>
            <span className="h-3 w-px bg-separator" />
            <span className="flex items-center gap-1.5 text-[12px] text-2">
              <ShortcutKey keys="⌥⇧ Space" /> Toggle recording
            </span>
            <span className="h-3 w-px bg-separator" />
            <span className="flex items-center gap-1.5 text-[12px] text-2">
              <ShortcutKey keys="Esc" /> Cancel
            </span>
          </motion.div>
        )}
      </AnimatePresence>

      {/* recall-hints button */}
      {hintDismissed && !hintRecalled && (
        <motion.button
          type="button"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          onClick={() => setHintRecalled(true)}
          className="vibrancy-menubar absolute bottom-20 right-6 z-20 flex h-8 w-8 cursor-pointer items-center justify-center rounded-full text-2 hairline hover:text-1"
          aria-label="Show shortcuts"
        >
          <HelpCircle size={15} />
        </motion.button>
      )}

      {/* Result toast */}
      <AnimatePresence>
        {toast && (
          <motion.div
            initial={{ opacity: 0, y: 12, scale: 0.96 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 8, scale: 0.96 }}
            transition={SPRING}
            className="vibrancy absolute bottom-20 right-6 z-30 w-72 rounded-[14px] p-3 shadow-popover hairline"
          >
            <div className="flex items-center gap-2">
              <ModeIcon mode={toast.mode} size={15} />
              <div className="flex-1">
                <p className="text-[12px] font-semibold text-1">
                  {toast.note ?? "Saved to History"}
                </p>
                {!toast.note && (
                  <p className="font-mono text-[11px] text-3">
                    {toast.words} words · {Math.floor(toast.seconds / 60)}:
                    {String(Math.round(toast.seconds % 60)).padStart(2, "0")}
                  </p>
                )}
              </div>
            </div>
            {!toast.note && (
              <div className="mt-2 flex gap-1.5">
                <button
                  type="button"
                  onClick={reprocess}
                  className="flex flex-1 cursor-pointer items-center justify-center gap-1 rounded-[6px] bg-surface-2 px-2 py-1 text-[11px] font-medium text-1 hover:bg-surface-3"
                >
                  <RotateCcw size={11} /> Reprocess
                </button>
                <button
                  type="button"
                  onClick={undoPaste}
                  className="flex flex-1 cursor-pointer items-center justify-center gap-1 rounded-[6px] bg-surface-2 px-2 py-1 text-[11px] font-medium text-1 hover:bg-surface-3"
                >
                  <Undo2 size={11} /> Undo paste
                </button>
              </div>
            )}
          </motion.div>
        )}
      </AnimatePresence>

      {/* Dock */}
      <div className="absolute inset-x-0 bottom-0 z-20">
        <Footer bounceSignal={bounce} />
      </div>
    </div>
  );
}
