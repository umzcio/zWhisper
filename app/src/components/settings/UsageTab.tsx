import { useEffect, useMemo, useRef, useState } from "react";
import { motion } from "framer-motion";
import type { Variants } from "framer-motion";
import { Copy, Download, RotateCcw } from "lucide-react";
import { useToast } from "@/components/settings/toast";
import { playClick } from "@/components/settings/settingsState";
import { cn } from "@/lib/utils";

const WORDS = 12483;
const DICTATION_WPM = 148;
const TYPING_BASELINE = 41;
const HOURS_SAVED = 9.2;
const TEST_SENTENCE = "The quick brown fox jumps over the lazy dog.";
const SPARK = [18, 26, 22, 34, 30, 44, 52]; // 7-day words trend

const list: Variants = {
  hidden: {},
  show: { transition: { staggerChildren: 0.07 } },
};
const item: Variants = {
  hidden: { opacity: 0, y: 16 },
  show: { opacity: 1, y: 0, transition: { type: "spring", stiffness: 400, damping: 30 } },
};

/* --------------------------------- CountUp --------------------------------- */

/** Counts from 0 to `value` on mount — 1.2s ease-out cubic, tabular output. */
function CountUp({
  value,
  decimals = 0,
  duration = 1.2,
}: {
  value: number;
  decimals?: number;
  duration?: number;
}) {
  const [display, setDisplay] = useState(0);

  useEffect(() => {
    let raf = 0;
    const start = performance.now();
    const tick = (now: number) => {
      const p = Math.min(1, (now - start) / (duration * 1000));
      const eased = 1 - Math.pow(1 - p, 3);
      setDisplay(value * eased);
      if (p < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [value, duration]);

  const text =
    decimals > 0
      ? display.toFixed(decimals)
      : Math.round(display).toLocaleString("en-US");
  return <>{text}</>;
}

/* --------------------------------- Sparkline -------------------------------- */

/** 7-day sparkline, accent stroke 1.5px, draws itself via stroke-dashoffset over 1s. */
function Sparkline({ data }: { data: number[] }) {
  const W = 120;
  const H = 32;
  const PAD = 2;
  const d = useMemo(() => {
    const mn = Math.min(...data);
    const mx = Math.max(...data);
    const span = mx - mn || 1;
    const step = (W - PAD * 2) / (data.length - 1);
    return data
      .map(
        (v, i) =>
          `${i === 0 ? "M" : "L"}${(PAD + i * step).toFixed(1)},${(
            H - PAD - ((v - mn) / span) * (H - PAD * 2)
          ).toFixed(1)}`
      )
      .join(" ");
  }, [data]);

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="mt-2 h-8 w-full" aria-hidden>
      <motion.path
        d={d}
        fill="none"
        stroke="var(--zw-accent)"
        strokeWidth={1.5}
        strokeLinecap="round"
        strokeLinejoin="round"
        initial={{ pathLength: 0 }}
        animate={{ pathLength: 1 }}
        transition={{ duration: 1, ease: "easeOut" }}
      />
    </svg>
  );
}

/* --------------------------------- StatCard --------------------------------- */

function StatCard({
  label,
  children,
  caption,
  extra,
}: {
  label: string;
  children: React.ReactNode;
  caption?: string;
  extra?: React.ReactNode;
}) {
  return (
    <motion.div variants={item} className="hairline flex-1 rounded-2xl bg-surface-2 p-4">
      <p className="text-[11px] font-medium uppercase tracking-[0.05em] text-3">{label}</p>
      <p className="mt-1 text-[32px] font-bold leading-none tracking-[-0.03em] tabular-nums text-1">
        {children}
      </p>
      {caption && <p className="mt-1.5 text-[11px] text-2">{caption}</p>}
      {extra}
    </motion.div>
  );
}

/* -------------------------------- Typing test ------------------------------- */

function TypingTest() {
  const [typed, setTyped] = useState("");
  const [startTime, setStartTime] = useState<number | null>(null);
  const [endTime, setEndTime] = useState<number | null>(null);
  const [wpm, setWpm] = useState(0);
  const [elapsedSec, setElapsedSec] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  const finished = endTime !== null;

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    let v = e.target.value;
    if (v.length > TEST_SENTENCE.length) v = v.slice(0, TEST_SENTENCE.length);
    const now = performance.now();
    const started = startTime ?? (v.length > 0 ? now : null);
    if (!startTime && v.length > 0) setStartTime(now);
    setTyped(v);
    if (started) {
      const secs = (now - started) / 1000;
      setElapsedSec(secs);
      setWpm(secs > 0.5 ? Math.round(v.length / 5 / (secs / 60)) : 0);
    }
    if (v.length === TEST_SENTENCE.length && started) {
      setEndTime(now);
    }
  };

  const reset = () => {
    playClick();
    setTyped("");
    setStartTime(null);
    setEndTime(null);
    setWpm(0);
    setElapsedSec(0);
    inputRef.current?.focus();
  };

  const ratio = finished && wpm > 0 ? (DICTATION_WPM / wpm).toFixed(1) : null;
  const barMax = Math.max(DICTATION_WPM, wpm, 1);

  return (
    <motion.div variants={item} className="hairline rounded-2xl bg-surface-2 p-4">
      <div className="flex items-center justify-between">
        <h4 className="text-[13px] font-semibold text-1">How fast do you type?</h4>
        {(typed.length > 0 || finished) && (
          <motion.button
            type="button"
            onClick={reset}
            whileTap={{ scale: 0.95 }}
            className="flex cursor-pointer items-center gap-1 rounded-[5px] px-1.5 py-0.5 text-[11px] font-medium text-2 hover:bg-surface-3 hover:text-1"
          >
            <RotateCcw size={11} /> Restart
          </motion.button>
        )}
      </div>

      {/* target sentence with per-character feedback */}
      <p className="mt-2 select-none font-mono text-[12px] leading-relaxed tracking-[0.01em]">
        {TEST_SENTENCE.split("").map((ch, i) => (
          <span
            key={i}
            className={cn(
              i < typed.length
                ? typed[i] === ch
                  ? "text-accent-green"
                  : "rounded-[2px] bg-accent-red/25 text-accent-red"
                : "text-3"
            )}
          >
            {ch}
          </span>
        ))}
      </p>

      <input
        ref={inputRef}
        type="text"
        value={typed}
        onChange={handleChange}
        disabled={finished}
        placeholder="Start typing the sentence…"
        aria-label="Typing speed test"
        className="hairline mt-2.5 w-full rounded-[8px] bg-surface-1 px-3 py-2 font-mono text-[12px] text-1 outline-none placeholder:text-3 focus:ring-2 focus:ring-accent-blue/60 disabled:opacity-60"
      />

      <div className="mt-2.5 flex items-center justify-between text-[11px] text-2">
        <span>
          Live speed:{" "}
          <span className="font-mono font-semibold tabular-nums text-1">
            {finished ? wpm : startTime ? wpm : 0}
          </span>{" "}
          wpm
        </span>
        {finished && <span className="font-mono tabular-nums">{elapsedSec.toFixed(1)}s</span>}
      </div>

      {/* compare bars */}
      {finished && (
        <motion.div
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ type: "spring", stiffness: 400, damping: 30 }}
          className="mt-3 flex flex-col gap-2 border-t border-separator pt-3"
        >
          {[
            { label: "You", value: wpm, color: "var(--accent-teal)" },
            { label: "Dictation", value: DICTATION_WPM, color: "var(--zw-accent)" },
          ].map((bar) => (
            <div key={bar.label} className="flex items-center gap-2">
              <span className="w-16 shrink-0 text-[11px] text-2">{bar.label}</span>
              <div className="h-3 flex-1 overflow-hidden rounded-full bg-surface-3/60">
                <motion.div
                  initial={{ width: 0 }}
                  animate={{ width: `${Math.max(4, (bar.value / barMax) * 100)}%` }}
                  transition={{ duration: 0.8, ease: [0.16, 1, 0.3, 1] }}
                  className="h-full rounded-full"
                  style={{ backgroundColor: bar.color }}
                />
              </div>
              <span className="w-12 shrink-0 text-right font-mono text-[11px] tabular-nums text-1">
                {bar.value} wpm
              </span>
            </div>
          ))}
          {ratio && (
            <p className="mt-1 text-[12px] font-medium text-1">
              Dictation is <span className="text-accent-green">{ratio}× faster</span> than your typing.
            </p>
          )}
        </motion.div>
      )}
    </motion.div>
  );
}

/* --------------------------------- Share card -------------------------------- */

function ShareCard() {
  const toast = useToast();

  const copyText = async () => {
    playClick();
    const text = `I've saved ${HOURS_SAVED} hours with zWhisper this month — ${WORDS.toLocaleString("en-US")} words dictated at ${DICTATION_WPM} wpm.`;
    try {
      await navigator.clipboard.writeText(text);
      toast("Copied to clipboard");
    } catch {
      toast("Clipboard unavailable in this browser");
    }
  };

  return (
    <motion.div variants={item} className="hairline rounded-2xl bg-surface-2 p-4">
      <h4 className="text-[13px] font-semibold text-1">Share your stats</h4>

      {/* 320×180 share card preview */}
      <div
        className="hairline relative mx-auto mt-3 h-[180px] w-[320px] overflow-hidden rounded-[14px]"
        style={{
          background:
            "linear-gradient(135deg, #1B1B26 0%, #0B0B0F 55%, #141024 100%)",
        }}
      >
        <div
          className="pointer-events-none absolute -right-8 -top-10 h-32 w-32 rounded-full opacity-40 blur-2xl"
          style={{ background: "radial-gradient(closest-side, #BF5AF2, transparent)" }}
        />
        <div
          className="pointer-events-none absolute -bottom-10 -left-8 h-32 w-32 rounded-full opacity-30 blur-2xl"
          style={{ background: "radial-gradient(closest-side, #64D2FF, transparent)" }}
        />
        <div className="relative flex h-full flex-col p-4">
          <div className="flex items-center gap-1.5">
            <img src="/logo.svg" alt="zWhisper" className="h-4 w-4 rounded-[4px]" />
            <span className="text-[11px] font-semibold text-[#F5F5F7]">zWhisper</span>
          </div>
          <div className="flex flex-1 items-center gap-3">
            <img
              src="/avatar-user.jpg"
              alt="User avatar"
              className="h-11 w-11 rounded-full ring-2 ring-white/15"
            />
            <div>
              <p className="text-[22px] font-bold leading-tight tracking-[-0.02em] text-white">
                {HOURS_SAVED} hours saved
              </p>
              <p className="text-[11px] text-[#98989D]">with zWhisper this month</p>
            </div>
          </div>
          <p className="font-mono text-[10px] text-[#636366]">
            {WORDS.toLocaleString("en-US")} words · {DICTATION_WPM} wpm
          </p>
        </div>
      </div>

      <div className="mt-3 flex justify-center gap-2">
        <motion.button
          type="button"
          onClick={() => {
            playClick();
            toast("PNG export is decorative in this prototype");
          }}
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.97 }}
          transition={{ type: "spring", stiffness: 500, damping: 35 }}
          className="hairline flex cursor-pointer items-center gap-1.5 rounded-[6px] bg-surface-3 px-3 py-1.5 text-[12px] font-medium text-1 hover:bg-surface-3/70"
        >
          <Download size={12} /> Download PNG
        </motion.button>
        <motion.button
          type="button"
          onClick={copyText}
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.97 }}
          transition={{ type: "spring", stiffness: 500, damping: 35 }}
          className="flex cursor-pointer items-center gap-1.5 rounded-[6px] bg-accent-blue px-3 py-1.5 text-[12px] font-medium text-white hover:opacity-90"
        >
          <Copy size={12} /> Copy text
        </motion.button>
      </div>
    </motion.div>
  );
}

/* ---------------------------------- Usage tab -------------------------------- */

export default function UsageTab() {
  return (
    <motion.div
      variants={list}
      initial="hidden"
      animate="show"
      className="mx-auto flex w-full max-w-[560px] flex-col gap-4 pb-2"
    >
      <div className="flex gap-3">
        <StatCard label="Words dictated" extra={<Sparkline data={SPARK} />}>
          <CountUp value={WORDS} />
        </StatCard>
        <StatCard label="Dictation speed" caption={`vs ${TYPING_BASELINE} wpm typing`}>
          <CountUp value={DICTATION_WPM} />
          <span className="ml-1 text-[13px] font-medium tracking-normal text-2">wpm</span>
        </StatCard>
        <StatCard label="Time saved" caption="this month">
          <CountUp value={HOURS_SAVED} decimals={1} />
          <span className="ml-1 text-[13px] font-medium tracking-normal text-2">hrs</span>
        </StatCard>
      </div>
      <TypingTest />
      <ShareCard />
    </motion.div>
  );
}
