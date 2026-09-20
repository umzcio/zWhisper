import { MODES } from "@/lib/modes";
import type { Mode, ModeId } from "@/lib/modes";

export type DateFilter = "today" | "week" | "all";

export interface HistoryFilters {
  search: string;
  modes: ModeId[];
  date: DateFilter;
}

export const DEFAULT_FILTERS: HistoryFilters = { search: "", modes: [], date: "all" };

/** One stored dictation in the History list. */
export interface HistoryEntry {
  id: string;
  modeId: ModeId;
  createdAt: Date;
  /** seconds */
  duration: number;
  /** current result text (\n separated paragraphs/lines) */
  text: string;
  /** pre-computed static waveform bar heights 0..1 */
  bars: number[];
  /** shows indeterminate progress bar on first mount */
  processing: boolean;
  /** previous versions for the reversible reprocess banner */
  undoStack: { modeId: ModeId; text: string }[];
}

export interface TimedWord {
  w: string;
  /** seconds from start of recording */
  t: number;
  /** global word index across all paragraphs */
  gi: number;
}

export interface TimedParagraph {
  words: TimedWord[];
}

/* ------------------------------------------------------------------ */
/* deterministic pseudo-random                                         */
/* ------------------------------------------------------------------ */

function hashSeed(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  }
  return h >>> 0;
}

function mulberry32(seed: number): () => number {
  let a = seed | 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/* ------------------------------------------------------------------ */
/* word timing + waveform bars                                         */
/* ------------------------------------------------------------------ */

/** Spread words across the recording duration with deterministic jitter. */
export function timeWords(text: string, duration: number, seedKey: string): TimedParagraph[] {
  const rand = mulberry32(hashSeed(seedKey + text.length));
  const paragraphs = text.split("\n");
  const totalWords = text.split(/\s+/).filter(Boolean).length;
  // leave ~8% tail of silence at the end
  const span = Math.max(1, duration * 0.92);
  let gi = 0;
  return paragraphs.map((p) => {
    const words = p.split(/\s+/).filter(Boolean).map((w) => {
      const base = (gi / Math.max(1, totalWords - 1)) * span;
      const jitter = (rand() - 0.5) * Math.min(0.35, span / Math.max(1, totalWords));
      const tw: TimedWord = { w, t: Math.max(0, base + jitter), gi };
      gi++;
      return tw;
    });
    return { words };
  });
}

function makeBars(seedKey: string, count = 80): number[] {
  const rand = mulberry32(hashSeed(seedKey));
  const bars: number[] = [];
  let level = 0.45;
  for (let i = 0; i < count; i++) {
    // random-walk with mean reversion + slow envelope so it looks like speech
    level += (rand() - 0.5) * 0.3;
    level += (0.45 - level) * 0.12;
    const envelope = 0.55 + 0.45 * Math.sin((i / count) * Math.PI);
    const v = Math.max(0.08, Math.min(1, level * envelope + (rand() - 0.5) * 0.12));
    bars.push(v);
  }
  return bars;
}

/* ------------------------------------------------------------------ */
/* seed data — 12 rows across 3 days, all modes mixed                  */
/* ------------------------------------------------------------------ */

function at(daysAgo: number, h: number, m: number): Date {
  const d = new Date();
  d.setDate(d.getDate() - daysAgo);
  d.setHours(h, m, 0, 0);
  return d;
}

function entry(
  id: string,
  modeId: ModeId,
  createdAt: Date,
  duration: number,
  text: string,
  processing = false
): HistoryEntry {
  return { id, modeId, createdAt, duration, text, bars: makeBars(id), processing, undoStack: [] };
}

export function seedHistory(): HistoryEntry[] {
  return [
    entry(
      "h01",
      "email",
      at(0, 9, 41),
      38,
      "Hi Sarah,\n\nThanks for sending over the revised mockups. I've reviewed the onboarding flow and left a few comments on frames twelve through fifteen.\n\nCould we sync Thursday afternoon to finalize everything before the stakeholder review?\n\nBest,\nAlex"
    ),
    entry(
      "h02",
      "meeting",
      at(0, 9, 12),
      64,
      "Action Items — Sync\n\n• Alex — owns the API migration timeline\n• Priya — drafts the migration comms (due Wednesday)\n• Team — retro moved to accommodate the design review\n• Sam — circulates the updated rollout checklist by Friday"
    ),
    entry(
      "h03",
      "message",
      at(0, 8, 57),
      12,
      "hey! running ~10 min late, grabbing coffee on the way — order me the usual if you get there first"
    ),
    entry(
      "h04",
      "note",
      at(0, 7, 30),
      46,
      "Pricing page — before Friday's launch:\n\n• Update pricing page copy\n• Get legal sign-off on annual plan discount messaging\n• Fix comparison table — still shows old tier names"
    ),
    entry(
      "h05",
      "super",
      at(0, 7, 5),
      52,
      "Summary: Project sync covered onboarding flow feedback and launch readiness.\n\nNext steps:\n• Review frames 12–15 comments\n• Confirm Thursday sync with Sarah\n• Circulate stakeholder-review agenda",
      true
    ),
    entry(
      "h06",
      "voice-note",
      at(1, 18, 18),
      29,
      "um so i was thinking about the launch and like we should probably get the blog post drafted before thursday and, yeah, also remind design about the hero image"
    ),
    entry(
      "h07",
      "email",
      at(1, 15, 44),
      57,
      "Hi Priya,\n\nThe migration comms draft looks great — two small notes on the rollout timeline section. Let's land the final version before Wednesday's standup so support has time to review.\n\nThanks,\nAlex"
    ),
    entry(
      "h08",
      "write-for-me",
      at(1, 13, 20),
      33,
      "Just following up on our stakeholder review — I'd love to hear any final thoughts before we lock the scope. Happy to hop on a quick call if that's easier. Thanks!",
      true
    ),
    entry(
      "h09",
      "meeting",
      at(1, 10, 2),
      81,
      "Action Items — Design Review\n\n• Mia — revises the empty-state illustrations by Thursday\n• Alex — files the follow-up tickets for the onboarding audit\n• Team — next review moved to Monday 10 AM"
    ),
    entry(
      "h10",
      "note",
      at(2, 16, 12),
      41,
      "Weekend plan:\n\n• Draft the launch retrospective outline\n• Book the team dinner for Friday\n• Renew the design-tool seats before they lapse"
    ),
    entry("h11", "message", at(2, 11, 26), 9, "omw — five minutes out, save me a seat near the window"),
    entry(
      "h12",
      "voice-note",
      at(2, 8, 3),
      70,
      "okay so quick brain dump before I forget — the new landing page needs a clearer headline, the footer links are stale, and we should ask legal about the partner logos before friday, also remind me to ping sam about the changelog"
    ),
  ];
}

/* ------------------------------------------------------------------ */
/* reprocess: transform a transcript into a different mode's voice     */
/* ------------------------------------------------------------------ */

function sentencesOf(text: string): string[] {
  const flat = text
    .split("\n")
    .map((l) => l.replace(/^•\s*/, "").trim())
    .filter(Boolean)
    .join(" ")
    .replace(/\s+/g, " ");
  const parts = flat.split(/(?<=[.!?])\s+/).filter(Boolean);
  return parts.length ? parts : [flat];
}

function sentenceCase(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

/** Mock "process with {mode}" transformation of an existing transcript. */
export function reprocessText(text: string, mode: Mode): string {
  const sents = sentencesOf(text).map((s) => s.trim());
  const clean = sents.map((s) => s.replace(/^um\s+|^so\s+|^okay so\s+/i, "").trim()).filter(Boolean);
  const pick = clean.length ? clean : sents;

  switch (mode.id) {
    case "email": {
      const body = pick.slice(0, 3).map(sentenceCase).join(" ");
      const ask = pick.length > 3 ? `\n\n${pick.slice(3).map(sentenceCase).join(" ")}` : "";
      return `Hi there,\n\n${body}${ask}\n\nBest,\nAlex`;
    }
    case "message": {
      const joined = pick.join(" ").replace(/\.\s+/g, ", ").replace(/,$/, "");
      return joined.toLowerCase().replace(/\.$/, "");
    }
    case "note": {
      const title = pick[0] ? sentenceCase(pick[0]).replace(/\.$/, "") : "Note";
      const bullets = pick.slice(1, 5).map((s) => `• ${sentenceCase(s).replace(/\.$/, "")}`);
      return bullets.length ? `${title}\n\n${bullets.join("\n")}` : title;
    }
    case "meeting": {
      const items = pick.slice(0, 5).map((s) => `• ${sentenceCase(s).replace(/\.$/, "")}`);
      return `Action Items\n\n${items.join("\n")}`;
    }
    case "voice-note":
      return pick.join(" ").toLowerCase().replace(/\s+/g, " ").trim();
    case "write-for-me": {
      const core = pick.slice(0, 2).map(sentenceCase).join(" ");
      return `${core} Happy to hop on a quick call if that's easier. Thanks!`;
    }
    case "super": {
      const summary = pick.slice(0, 2).map(sentenceCase).join(" ");
      const steps = pick
        .slice(2, 5)
        .map((s) => `• ${sentenceCase(s).replace(/\.$/, "")}`)
        .join("\n");
      return `Summary: ${summary}${steps ? `\n\nNext steps:\n${steps}` : ""}`;
    }
    default:
      return text;
  }
}

/* ------------------------------------------------------------------ */
/* formatting helpers                                                  */
/* ------------------------------------------------------------------ */

export function modeById(id: ModeId): Mode {
  return MODES.find((m) => m.id === id) ?? MODES[0];
}

/** 9:41 AM */
export function formatClockTime(d: Date): string {
  let h = d.getHours();
  const ampm = h >= 12 ? "PM" : "AM";
  h = h % 12 || 12;
  return `${h}:${String(d.getMinutes()).padStart(2, "0")} ${ampm}`;
}

/** 0:38 */
export function formatDuration(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

/** 0:12.4 */
export function formatTimestamp(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = sec - m * 60;
  return `${m}:${s < 10 ? "0" : ""}${s.toFixed(1)}`;
}

const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function sameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

/** Today / Yesterday / Mon Jan 13 */
export function dayLabel(d: Date, now = new Date()): string {
  if (sameDay(d, now)) return "Today";
  const y = new Date(now);
  y.setDate(y.getDate() - 1);
  if (sameDay(d, y)) return "Yesterday";
  return `${DAYS[d.getDay()]} ${MONTHS[d.getMonth()]} ${d.getDate()}`;
}

/** Today at 9:41 AM / Mon Jan 13 at 9:41 AM */
export function fullStamp(d: Date): string {
  return `${dayLabel(d)} at ${formatClockTime(d)}`;
}

export function wordCount(text: string): number {
  return text.split(/\s+/).filter(Boolean).length;
}

/** First ~40 chars of result text, single line. */
export function previewOf(text: string): string {
  const flat = text.replace(/\s+/g, " ").trim();
  return flat.length > 44 ? `${flat.slice(0, 44).trimEnd()}…` : flat;
}
