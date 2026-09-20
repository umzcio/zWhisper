import { useEffect, useRef, useState } from "react";
import type { RefObject } from "react";
import { motion, AnimatePresence, useAnimationControls } from "framer-motion";
import {
  Mic,
  X,
  Square,
  Check,
  ChevronsUpDown,
  ChevronsDownUp,
  AudioLines,
} from "lucide-react";
import { cn } from "@/lib/utils";
import type { Mode } from "@/lib/modes";
import type { MockEngine } from "@/lib/mockEngine";
import { formatTimer } from "@/lib/mockEngine";
import Waveform from "@/components/Waveform";
import { ModePill, ModeSwitcher } from "@/components/ModeSwitcher";

export interface RecordingPopoverProps {
  open: boolean;
  engine: MockEngine;
  mode: Mode;
  onModeChange: (m: Mode) => void;
  onStart: () => void;
  onStop: () => void;
  onCancel: () => void;
  /** dismiss popover while idle */
  onDismiss: () => void;
  /** true while push-to-talk is physically held */
  holdActive?: boolean;
  /** increment to trigger the Esc-cancel shake */
  shakeSignal?: number;
  /** stage element for drag constraints */
  stageRef: RefObject<HTMLDivElement | null>;
}

const SPRING_POP = { type: "spring", stiffness: 400, damping: 28 } as const;
const SPRING_MICRO = { type: "spring", stiffness: 500, damping: 35 } as const;

export default function RecordingPopover({
  open,
  engine,
  mode,
  onModeChange,
  onStart,
  onStop,
  onCancel,
  onDismiss,
  holdActive = false,
  shakeSignal = 0,
  stageRef,
}: RecordingPopoverProps) {
  const { phase, spokenWords, activeWord, elapsed, contextCaptured } = engine;
  const [mini, setMini] = useState(false);
  const [switcherOpen, setSwitcherOpen] = useState(false);
  const [hovering, setHovering] = useState(false);
  const shake = useAnimationControls();
  const teleRef = useRef<HTMLDivElement>(null);

  const recording = phase === "recording";
  const busy = phase === "transcribing" || phase === "processing";
  const settling = busy || phase === "pasted";

  useEffect(() => {
    if (shakeSignal > 0) {
      shake.start({ x: [0, -8, 8, -4, 0], transition: { duration: 0.4 } });
    }
  }, [shakeSignal, shake]);

  // teleprompter auto-scroll
  useEffect(() => {
    const el = teleRef.current;
    if (el) el.scrollLeft = el.scrollWidth;
  }, [spokenWords, activeWord]);

  const teleprompterText = spokenWords.join(" ");

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          drag
          dragConstraints={stageRef}
          dragMomentum={false}
          whileDrag={{ scale: 1.01 }}
          initial={false}
          className={cn(
            "absolute top-10 z-30",
            "cursor-grab active:cursor-grabbing"
          )}
          style={{
            left: `calc(50% - ${mini ? 110 : 210}px)`,
            filter: "drop-shadow(0 24px 64px rgba(0,0,0,0.5))",
          }}
        >
          <motion.div
            initial={{ opacity: 0, scale: 0.85, y: -8 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.9, y: -4 }}
            transition={SPRING_POP}
          >
          <motion.div
            animate={shake}
            onMouseEnter={() => setHovering(true)}
            onMouseLeave={() => setHovering(false)}
            onDoubleClick={() => setMini((m) => !m)}
            className={cn(
              "vibrancy relative overflow-hidden rounded-[14px] hairline shadow-popover"
            )}
            style={{ width: mini ? 220 : 420, height: mini ? 64 : 240 }}
          >
            {/* watermark logo */}
            <img
              src="/logo.svg"
              alt=""
              aria-hidden
              className="pointer-events-none absolute left-1/2 top-2 h-16 w-16 -translate-x-1/2 opacity-[0.03]"
            />

            <motion.div layout="position" className="flex h-full flex-col p-3">
              {/* top row */}
              <div className="flex items-center gap-2">
                {/* context-awareness dot */}
                <span className="relative flex h-3 w-3 items-center justify-center" title="Context captured: Notes selection + clipboard">
                  {contextCaptured && (
                    <>
                      <img
                        src="/super-mode-glow.png"
                        alt=""
                        aria-hidden
                        className="absolute h-6 w-6 animate-[zw-pulse-dot_2s_ease-in-out_infinite]"
                      />
                      <span className="relative h-2 w-2 rounded-full bg-accent-purple" />
                    </>
                  )}
                  {!contextCaptured && <span className="h-2 w-2 rounded-full bg-surface-3" />}
                </span>

                <div className="relative">
                  <motion.span
                    key={mode.id + String(open)}
                    initial={{ scale: 1.15 }}
                    animate={{ scale: 1 }}
                    transition={SPRING_MICRO}
                    className="block"
                  >
                    <ModePill compact mode={mode} onClick={() => setSwitcherOpen((o) => !o)} />
                  </motion.span>
                  <ModeSwitcher
                    open={switcherOpen}
                    activeMode={mode}
                    onSelect={onModeChange}
                    onClose={() => setSwitcherOpen(false)}
                    className="absolute left-0 top-7 z-50"
                  />
                </div>

                <div className="flex-1" />

                {!mini && recording && (
                  <span className="flex items-center gap-1.5">
                    <span className="h-2 w-2 rounded-full bg-accent-red animate-[zw-pulse-dot_1s_ease-in-out_infinite]" />
                    <span className="font-mono text-[11px] text-2 tabular-nums">
                      {formatTimer(elapsed)}
                    </span>
                  </span>
                )}

                <motion.button
                  type="button"
                  aria-label={mini ? "Expand" : "Collapse"}
                  onClick={() => setMini((m) => !m)}
                  whileTap={{ scale: 0.97 }}
                  transition={SPRING_MICRO}
                  className="cursor-pointer rounded p-1 text-3 hover:bg-surface-3/60 hover:text-2"
                >
                  {mini ? <ChevronsDownUp size={13} /> : <ChevronsUpDown size={13} />}
                </motion.button>
              </div>

              {/* waveform */}
              <motion.div layout="position" className="relative flex-1 py-2">
                {recording && (
                  <div
                    className="recording-glow pointer-events-none absolute inset-0 animate-[zw-breathe_2s_ease-in-out_infinite]"
                    aria-hidden
                  />
                )}
                <Waveform bars={mini ? 28 : 48} active={recording} settling={settling} />
              </motion.div>

              {/* teleprompter (Main only) */}
              {!mini && (
                <motion.div layout="position" className="min-h-[26px]">
                  {phase === "idle" && (
                    <p className="text-[13px] text-3">
                      {mode.id === "write-for-me"
                        ? "Pick a topic, then speak the details."
                        : "Tap the mic or hold Space to dictate."}
                    </p>
                  )}
                  {phase === "idle" && mode.id === "write-for-me" && mode.topicChips && (
                    <div className="mt-1.5 flex gap-1.5">
                      {mode.topicChips.map((chip) => (
                        <button
                          key={chip}
                          type="button"
                          onClick={onStart}
                          className="cursor-pointer rounded-full hairline bg-surface-2 px-2 py-0.5 text-[11px] font-medium text-2 hover:bg-surface-3 hover:text-1"
                        >
                          {chip}
                        </button>
                      ))}
                    </div>
                  )}
                  {(recording || busy || phase === "pasted") && (
                    <div
                      ref={teleRef}
                      className="cursor-text overflow-x-auto whitespace-nowrap text-[17px] font-medium leading-snug [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
                    >
                      <span
                        className={cn(
                          "text-1",
                          phase === "transcribing" && "shimmer-text-transcribe",
                          phase === "processing" && "shimmer-text"
                        )}
                      >
                        {teleprompterText.split(" ").map((w, i) => (
                          <span
                            key={i}
                            className={cn(i === activeWord && recording && "text-accent-blue")}
                          >
                            {w}{" "}
                          </span>
                        ))}
                      </span>
                    </div>
                  )}
                  {recording && holdActive && (
                    <p className="mt-1 text-[11px] text-2">Push to talk — release to paste</p>
                  )}
                  {phase === "processing" && (
                    <p className="mt-1 text-[11px] font-medium text-accent-purple">
                      Processing with {mode.name} mode
                    </p>
                  )}
                  {phase === "transcribing" && (
                    <p className="mt-1 text-[11px] text-2">Transcribing…</p>
                  )}
                  {phase === "pasted" && (
                    <p className="mt-1 flex items-center gap-1 text-[11px] font-medium text-accent-green">
                      <Check size={12} strokeWidth={3} /> Pasted to Notes
                    </p>
                  )}
                </motion.div>
              )}

              {/* bottom controls */}
              <motion.div layout="position" className="flex items-center justify-between pt-1">
                {phase === "idle" ? (
                  <>
                    <button
                      type="button"
                      onClick={onDismiss}
                      className="cursor-pointer rounded-md px-2 py-1 text-[12px] text-3 hover:bg-surface-3/60 hover:text-2"
                    >
                      Dismiss
                    </button>
                    <motion.button
                      type="button"
                      aria-label="Start dictation"
                      onClick={onStart}
                      whileHover={{ scale: 1.02 }}
                      whileTap={{ scale: 0.97 }}
                      transition={SPRING_MICRO}
                      className={cn(
                        "flex cursor-pointer items-center gap-1.5 rounded-full bg-accent-red px-3 py-1.5 text-[12px] font-semibold text-white",
                        holdActive && "ring-2 ring-accent-blue scale-[1.15]"
                      )}
                    >
                      <Mic size={13} /> Start dictation
                    </motion.button>
                  </>
                ) : (
                  <>
                    <motion.button
                      type="button"
                      aria-label="Cancel"
                      onClick={onCancel}
                      disabled={busy}
                      whileHover={{ scale: 1.08 }}
                      whileTap={{ scale: 0.97 }}
                      transition={SPRING_MICRO}
                      className="flex h-7 w-7 cursor-pointer items-center justify-center rounded-[6px] text-2 hover:bg-surface-3 disabled:opacity-40"
                    >
                      <X size={15} />
                    </motion.button>
                    <span className="flex items-center gap-1 text-[11px] text-3">
                      <AudioLines size={12} /> {mode.name}
                    </span>
                    <motion.button
                      type="button"
                      aria-label="Stop"
                      onClick={onStop}
                      disabled={busy}
                      initial={mini ? { x: 24, opacity: 0 } : false}
                      animate={mini ? { x: hovering ? 0 : 24, opacity: hovering ? 1 : 0 } : { x: 0, opacity: 1 }}
                      whileHover={{ scale: 1.08 }}
                      whileTap={{ scale: 0.97 }}
                      transition={SPRING_MICRO}
                      className="flex h-7 w-7 cursor-pointer items-center justify-center rounded-[6px] bg-accent-red text-white disabled:opacity-40"
                    >
                      <Square size={12} fill="currentColor" />
                    </motion.button>
                  </>
                )}
              </motion.div>
            </motion.div>
          </motion.div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
