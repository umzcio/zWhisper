import { useCallback, useEffect, useRef, useState } from "react";
import type { Mode } from "@/lib/modes";

export type EnginePhase =
  | "idle"
  | "recording"
  | "transcribing"
  | "processing"
  | "pasted"
  | "cancelled";

export interface EngineCallbacks {
  /** Called with the processed result when auto-paste should happen */
  onPaste?: (text: string, mode: Mode) => void;
  /** Called after the full sequence (incl. type-out) completes */
  onComplete?: (text: string, mode: Mode, stats: { words: number; seconds: number }) => void;
  /** Called when the user cancels (Esc / Cancel button) */
  onCancel?: () => void;
  /** Called whenever the phase changes */
  onPhaseChange?: (phase: EnginePhase) => void;
}

export interface MockEngine {
  phase: EnginePhase;
  /** words of the script that have been "spoken" so far */
  spokenWords: string[];
  /** index of the word currently being spoken (-1 when not recording) */
  activeWord: number;
  /** seconds elapsed in the current recording */
  elapsed: number;
  /** true once the purple context dot has lit up */
  contextCaptured: boolean;
  /** 0..1 amplitude drive for waveform/glow (rises while speaking) */
  energy: number;
  start: (mode: Mode) => void;
  stop: () => void;
  cancel: () => void;
  reset: () => void;
}

const WORD_MIN_MS = 120;
const WORD_MAX_MS = 180;
const TRANSCRIBE_MS = 900;
const PROCESS_MS = 700;
const CONTEXT_MS = 600;

/** Simulated amplitude: layered sines + noise. t in seconds, speaking boosts level. */
export function sampleAmplitude(t: number, speaking: boolean): number {
  const base =
    0.5 +
    0.28 * Math.sin(t * 5.3) * Math.sin(t * 1.7) +
    0.16 * Math.sin(t * 11.1 + 1.3) +
    0.1 * Math.sin(t * 23.7 + 0.7) +
    (Math.random() - 0.5) * 0.22;
  const level = Math.abs(base);
  return speaking ? Math.min(1, 0.25 + level * 0.9) : Math.min(1, level * 0.12);
}

export function useMockTranscriptionEngine(cb: EngineCallbacks = {}): MockEngine {
  const [phase, setPhase] = useState<EnginePhase>("idle");
  const [spokenWords, setSpokenWords] = useState<string[]>([]);
  const [activeWord, setActiveWord] = useState(-1);
  const [elapsed, setElapsed] = useState(0);
  const [contextCaptured, setContextCaptured] = useState(false);
  const [energy, setEnergy] = useState(0);

  const timers = useRef<number[]>([]);
  const phaseRef2 = useRef<EnginePhase>("idle");
  const modeRef = useRef<Mode | null>(null);
  const startedAt = useRef(0);
  const cbRef = useRef(cb);
  useEffect(() => {
    cbRef.current = cb;
  }, [cb]);

  const clearTimers = useCallback(() => {
    timers.current.forEach((t) => window.clearTimeout(t));
    timers.current = [];
  }, []);

  const later = useCallback((fn: () => void, ms: number) => {
    timers.current.push(window.setTimeout(fn, ms));
  }, []);

  const setPhaseTracked = useCallback(
    (p: EnginePhase) => {
      phaseRef2.current = p;
      setPhase(p);
      cbRef.current.onPhaseChange?.(p);
    },
    []
  );

  const reset = useCallback(() => {
    clearTimers();
    setPhaseTracked("idle");
    setSpokenWords([]);
    setActiveWord(-1);
    setElapsed(0);
    setContextCaptured(false);
    setEnergy(0);
  }, [clearTimers, setPhaseTracked]);

  const start = useCallback(
    (mode: Mode) => {
      clearTimers();
      modeRef.current = mode;
      startedAt.current = Date.now();
      setSpokenWords([]);
      setActiveWord(-1);
      setElapsed(0);
      setContextCaptured(false);
      setPhaseTracked("recording");

      const words = mode.script.split(/\s+/);
      let acc = 0;
      words.forEach((word, i) => {
        acc += WORD_MIN_MS + Math.random() * (WORD_MAX_MS - WORD_MIN_MS);
        later(() => {
          setSpokenWords((prev) => [...prev, word]);
          setActiveWord(i);
        }, acc);
      });
      later(() => setContextCaptured(true), CONTEXT_MS);
    },
    [clearTimers, later, setPhaseTracked]
  );

  const stop = useCallback(() => {
    if (!modeRef.current || phaseRef2.current !== "recording") return;
    const mode = modeRef.current;
    const seconds = (Date.now() - startedAt.current) / 1000;
    clearTimers();
    setActiveWord(-1);
    setEnergy(0);
    setContextCaptured(true);
    // full script is considered spoken once stopped
    setSpokenWords(mode.script.split(/\s+/));
    setPhaseTracked("transcribing");

    later(() => setPhaseTracked("processing"), TRANSCRIBE_MS);
    later(() => {
      setPhaseTracked("pasted");
      cbRef.current.onPaste?.(mode.processed, mode);
      const words = mode.processed.split(/\s+/).length;
      cbRef.current.onComplete?.(mode.processed, mode, { words, seconds });
    }, TRANSCRIBE_MS + PROCESS_MS);
  }, [clearTimers, later, setPhaseTracked]);

  const cancel = useCallback(() => {
    clearTimers();
    setEnergy(0);
    setPhaseTracked("cancelled");
    cbRef.current.onCancel?.();
  }, [clearTimers, setPhaseTracked]);

  // elapsed ticker + energy drive while recording
  useEffect(() => {
    if (phase !== "recording") return;
    const t0 = Date.now();
    const iv = window.setInterval(() => {
      const t = (Date.now() - t0) / 1000;
      setElapsed(t);
      setEnergy(sampleAmplitude(t, true));
    }, 50);
    return () => window.clearInterval(iv);
  }, [phase]);

  useEffect(() => clearTimers, [clearTimers]);

  return {
    phase,
    spokenWords,
    activeWord,
    elapsed,
    contextCaptured,
    energy,
    start,
    stop,
    cancel,
    reset,
  };
}

/** Format seconds as m:ss.d teleprompter timer */
export function formatTimer(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds - m * 60;
  return `${m}:${s < 10 ? "0" : ""}${s.toFixed(1)}`;
}
