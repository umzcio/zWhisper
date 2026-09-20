import { useCallback, useEffect, useRef, useState } from "react";
import { motion } from "framer-motion";
import { Play, Square, AudioLines } from "lucide-react";
import { cn } from "@/lib/utils";
import { useMockTranscriptionEngine, formatTimer } from "@/lib/mockEngine";
import Waveform from "@/components/Waveform";
import type { LibraryMode } from "@/components/modes/data";
import { toEngineMode } from "@/components/modes/data";

const SPRING_MICRO = { type: "spring", stiffness: 500, damping: 35 } as const;
const TYPE_MS = 8;

interface LivePreviewProps {
  /** the mode currently being edited (script/processed drive the sample) */
  mode: LibraryMode;
}

/** 220px live preview pane: Sample button runs the mock engine, raw vs processed with shimmer */
export default function LivePreview({ mode }: LivePreviewProps) {
  const [typed, setTyped] = useState("");
  const typeTimer = useRef<number | null>(null);
  const autoStop = useRef<number | null>(null);

  const clearTypeTimer = useCallback(() => {
    if (typeTimer.current !== null) {
      window.clearInterval(typeTimer.current);
      typeTimer.current = null;
    }
  }, []);

  const engine = useMockTranscriptionEngine({
    onPaste: (text) => {
      // type out the processed result character by character (8ms/char)
      clearTypeTimer();
      setTyped("");
      let i = 0;
      typeTimer.current = window.setInterval(() => {
        i += 1;
        setTyped(text.slice(0, i));
        if (i >= text.length) clearTypeTimer();
      }, TYPE_MS);
    },
  });

  const { phase, spokenWords, elapsed } = engine;
  const recording = phase === "recording";
  const transcribing = phase === "transcribing";
  const processing = phase === "processing";
  const pasted = phase === "pasted";
  const busy = recording || transcribing || processing;

  const runSample = useCallback(() => {
    if (busy) {
      if (recording) {
        if (autoStop.current !== null) window.clearTimeout(autoStop.current);
        engine.stop();
      }
      return;
    }
    setTyped("");
    const engineMode = toEngineMode(mode);
    engine.start(engineMode);
    // auto-stop once the scripted sample has been fully "spoken"
    const words = engineMode.script.split(/\s+/).length;
    autoStop.current = window.setTimeout(() => engine.stop(), words * 165 + 500);
  }, [busy, recording, engine, mode]);

  // re-arm cleanly when switching modes mid-edit
  useEffect(() => {
    return () => {
      if (autoStop.current !== null) window.clearTimeout(autoStop.current);
      clearTypeTimer();
      engine.cancel();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mode.id]);

  useEffect(() => {
    return () => {
      if (autoStop.current !== null) window.clearTimeout(autoStop.current);
      clearTypeTimer();
    };
  }, [clearTypeTimer]);

  const rawText = spokenWords.join(" ");
  const showAfter = processing || pasted;

  return (
    <div className="flex w-[220px] shrink-0 flex-col border-l border-separator bg-surface-2/40">
      <div className="flex items-center gap-2 border-b border-separator px-3 py-2.5">
        <AudioLines size={13} className="text-accent-purple" />
        <span className="text-[11px] font-semibold uppercase tracking-[0.02em] text-2">
          Live preview
        </span>
        {recording && (
          <span className="ml-auto font-mono text-[11px] text-accent-green tabular-nums">
            {formatTimer(elapsed)}
          </span>
        )}
      </div>

      <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto p-3">
        <div className="h-9 shrink-0">
          <Waveform bars={28} active={recording} settling={busy && !recording} />
        </div>

        {/* before */}
        <div>
          <span className="text-[10px] font-semibold uppercase tracking-[0.02em] text-3">
            Before
          </span>
          <div className="mt-1 min-h-[64px] rounded-md bg-surface-1/70 p-2 text-[12px] leading-relaxed text-2 hairline">
            {transcribing ? (
              <span className="shimmer-text-transcribe">Transcribing…</span>
            ) : rawText ? (
              rawText
            ) : (
              <span className="text-3">Your raw transcription appears here.</span>
            )}
          </div>
        </div>

        {/* after */}
        <div>
          <span className="text-[10px] font-semibold uppercase tracking-[0.02em] text-3">
            After · {mode.name || "Untitled Mode"}
          </span>
          <div className="mt-1 min-h-[64px] rounded-md bg-surface-1/70 p-2 text-[12px] leading-relaxed text-1 hairline">
            {processing ? (
              <span className="shimmer-text">Processing with {mode.name || "mode"}…</span>
            ) : showAfter ? (
              <>
                <span className="whitespace-pre-wrap">{typed}</span>
                {typed.length < mode.processed.length && (
                  <span className="ml-px inline-block h-3 w-[1.5px] animate-[zw-caret_1s_infinite] bg-accent-purple align-middle" />
                )}
              </>
            ) : (
              <span className="text-3">The processed result appears here.</span>
            )}
          </div>
        </div>
      </div>

      <div className="border-t border-separator p-3">
        <motion.button
          type="button"
          onClick={runSample}
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.97 }}
          transition={SPRING_MICRO}
          className={cn(
            "flex w-full cursor-pointer items-center justify-center gap-1.5 rounded-md py-1.5 text-[12px] font-medium",
            recording
              ? "bg-accent-red/15 text-accent-red hover:bg-accent-red/25"
              : "bg-accent-purple/15 text-accent-purple hover:bg-accent-purple/25"
          )}
        >
          {recording ? <Square size={11} /> : <Play size={11} />}
          {recording ? "Stop" : busy ? "Working…" : "Sample"}
        </motion.button>
      </div>
    </div>
  );
}
