import { useEffect, useState } from "react";

const PREFIX = "zw-settings:";

/** Session-persistent settings state (localStorage-backed), local to the Settings page. */
export function usePersistentState<T>(
  key: string,
  initial: T
): [T, (v: T | ((prev: T) => T)) => void] {
  const [value, setValue] = useState<T>(() => {
    try {
      const raw = window.localStorage.getItem(PREFIX + key);
      if (raw != null) return JSON.parse(raw) as T;
    } catch {
      /* ignore corrupt values */
    }
    return initial;
  });

  useEffect(() => {
    try {
      window.localStorage.setItem(PREFIX + key, JSON.stringify(value));
    } catch {
      /* storage unavailable */
    }
  }, [key, value]);

  return [value, setValue];
}

export function readPersistent<T>(key: string, fallback: T): T {
  try {
    const raw = window.localStorage.getItem(PREFIX + key);
    if (raw != null) return JSON.parse(raw) as T;
  } catch {
    /* ignore */
  }
  return fallback;
}

export type SoundStyle = "subtle" | "classic" | "none";

let audioCtx: AudioContext | null = null;

/** Tiny synthesized UI click so the "Sound effects style" setting audibly affects the app. */
export function playClick(style?: SoundStyle) {
  const s = style ?? readPersistent<SoundStyle>("sound-style", "subtle");
  if (s === "none") return;
  try {
    audioCtx ??= new (window.AudioContext ??
      (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext)();
    if (audioCtx.state === "suspended") void audioCtx.resume();
    const osc = audioCtx.createOscillator();
    const gain = audioCtx.createGain();
    osc.type = "sine";
    osc.frequency.value = s === "classic" ? 760 : 1240;
    const peak = s === "classic" ? 0.09 : 0.035;
    const t = audioCtx.currentTime;
    gain.gain.setValueAtTime(peak, t);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.09);
    osc.connect(gain);
    gain.connect(audioCtx.destination);
    osc.start(t);
    osc.stop(t + 0.1);
  } catch {
    /* audio unavailable */
  }
}
