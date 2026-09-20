import { useMemo } from "react";
import { motion } from "framer-motion";
import { Copy, Download, Mic, Pause, Play, RotateCcw, RotateCw, Trash2 } from "lucide-react";
import { cn } from "@/lib/utils";
import type { Mode } from "@/lib/modes";
import { ModeIcon, ModePill } from "@/components/ModeSwitcher";
import WaveformStrip from "@/components/history/WaveformStrip";
import TranscriptView from "@/components/history/TranscriptView";
import ReprocessBar from "@/components/history/ReprocessBar";
import type { HistoryEntry } from "@/components/history/historyData";
import { formatDuration, formatTimestamp, fullStamp, modeById, timeWords } from "@/components/history/historyData";

const SPEEDS = [1, 1.5, 2];

interface DetailPaneProps {
  entry: HistoryEntry;
  playing: boolean;
  time: number;
  speed: number;
  shimmering: boolean;
  /** increments whenever the text version changes (reprocess/undo) */
  versionKey: string;
  bannerMode: Mode | null;
  reprocessFocus: boolean;
  onTogglePlay: () => void;
  onSeek: (t: number) => void;
  onSkip: (delta: number) => void;
  onSpeed: (s: number) => void;
  onCopy: () => void;
  onExport: () => void;
  onDelete: () => void;
  onReprocess: (mode: Mode) => void;
  onUndo: () => void;
}

/** Detail pane: player header, seekable waveform strip, transport, timed transcript, reprocess bar. */
export default function DetailPane({
  entry,
  playing,
  time,
  speed,
  shimmering,
  versionKey,
  bannerMode,
  reprocessFocus,
  onTogglePlay,
  onSeek,
  onSkip,
  onSpeed,
  onCopy,
  onExport,
  onDelete,
  onReprocess,
  onUndo,
}: DetailPaneProps) {
  const mode = modeById(entry.modeId);
  const paragraphs = useMemo(
    () => timeWords(entry.text, entry.duration, `${entry.id}:${versionKey}`),
    [entry.text, entry.duration, entry.id, versionKey]
  );

  const activeWord = useMemo(() => {
    let idx = -1;
    for (const p of paragraphs) {
      for (const w of p.words) {
        if (w.t <= time) idx = w.gi;
        else return idx;
      }
    }
    return idx;
  }, [paragraphs, time]);

  const progress = entry.duration > 0 ? Math.min(1, time / entry.duration) : 0;

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      {/* header: mode pill + timestamp + duration + actions */}
      <div className="flex shrink-0 items-center gap-2.5 border-b border-separator px-4 py-3">
        <span className="flex h-7 w-7 items-center justify-center rounded-[8px]" style={{ backgroundColor: `${mode.color}26` }}>
          <ModeIcon mode={mode} size={14} />
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <ModePill compact mode={mode} />
            <span className="truncate font-mono text-[11px] text-3 tabular-nums">
              {fullStamp(entry.createdAt)}
            </span>
          </div>
        </div>
        <span className="font-mono text-[11px] text-2 tabular-nums">{formatDuration(entry.duration)}</span>
        <span className="mx-0.5 h-4 w-px bg-separator" />
        <motion.button
          type="button"
          onClick={onCopy}
          whileTap={{ scale: 0.95 }}
          transition={{ type: "spring", stiffness: 500, damping: 35 }}
          className="flex cursor-pointer items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-2 hover:bg-surface-3 hover:text-1"
        >
          <Copy size={13} />
          Copy
        </motion.button>
        <motion.button
          type="button"
          onClick={onExport}
          whileTap={{ scale: 0.95 }}
          transition={{ type: "spring", stiffness: 500, damping: 35 }}
          className="flex cursor-pointer items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-2 hover:bg-surface-3 hover:text-1"
          title="Decorative in this prototype"
        >
          <Download size={13} />
          Export
        </motion.button>
        <motion.button
          type="button"
          onClick={onDelete}
          whileTap={{ scale: 0.95 }}
          transition={{ type: "spring", stiffness: 500, damping: 35 }}
          className="flex cursor-pointer items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-accent-red hover:bg-accent-red/10"
        >
          <Trash2 size={13} />
          Delete
        </motion.button>
      </div>

      {/* waveform strip + transport */}
      <div className="shrink-0 space-y-3 border-b border-separator px-4 py-3">
        <WaveformStrip bars={entry.bars} progress={progress} onSeek={(r) => onSeek(r * entry.duration)} />
        <div className="flex items-center gap-2">
          <motion.button
            type="button"
            aria-label="Back 5 seconds"
            onClick={() => onSkip(-5)}
            whileTap={{ scale: 0.92 }}
            transition={{ type: "spring", stiffness: 500, damping: 35 }}
            className="relative flex h-8 w-8 cursor-pointer items-center justify-center rounded-full text-2 hover:bg-surface-3 hover:text-1"
          >
            <RotateCcw size={15} />
            <span className="absolute -bottom-0.5 font-mono text-[8px] font-semibold text-3">5</span>
          </motion.button>
          <motion.button
            type="button"
            aria-label={playing ? "Pause" : "Play"}
            onClick={onTogglePlay}
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.94 }}
            transition={{ type: "spring", stiffness: 500, damping: 35 }}
            className="flex h-9 w-9 cursor-pointer items-center justify-center rounded-full bg-accent-blue text-white shadow-popover"
          >
            {playing ? <Pause size={15} fill="currentColor" /> : <Play size={15} fill="currentColor" className="ml-0.5" />}
          </motion.button>
          <motion.button
            type="button"
            aria-label="Forward 5 seconds"
            onClick={() => onSkip(5)}
            whileTap={{ scale: 0.92 }}
            transition={{ type: "spring", stiffness: 500, damping: 35 }}
            className="relative flex h-8 w-8 cursor-pointer items-center justify-center rounded-full text-2 hover:bg-surface-3 hover:text-1"
          >
            <RotateCw size={15} />
            <span className="absolute -bottom-0.5 font-mono text-[8px] font-semibold text-3">5</span>
          </motion.button>
          <span className="ml-1 font-mono text-[11px] text-2 tabular-nums">
            {formatTimestamp(time)} <span className="text-3">/ {formatDuration(entry.duration)}</span>
          </span>
          <div className="flex-1" />
          {/* playback speed segmented control */}
          <div className="flex items-center rounded-lg bg-surface-2 p-0.5 hairline">
            {SPEEDS.map((s) => (
              <motion.button
                key={s}
                type="button"
                onClick={() => onSpeed(s)}
                whileTap={{ scale: 0.95 }}
                className={cn(
                  "cursor-pointer rounded-md px-2 py-0.5 font-mono text-[11px] font-medium tabular-nums transition-colors",
                  speed === s ? "bg-surface-3 text-1 shadow-[0_1px_2px_rgba(0,0,0,0.3)]" : "text-3 hover:text-2"
                )}
              >
                {s}×
              </motion.button>
            ))}
          </div>
        </div>
      </div>

      {/* transcript */}
      <TranscriptView
        paragraphs={paragraphs}
        activeWord={activeWord}
        onWordClick={(t) => onSeek(t)}
        shimmering={shimmering}
        versionKey={versionKey}
      />

      {/* reprocess bar */}
      <ReprocessBar
        currentModeId={entry.modeId}
        onApply={onReprocess}
        bannerMode={bannerMode}
        onUndo={onUndo}
        focused={reprocessFocus}
      />
    </div>
  );
}

/** Placeholder when no recording is selected (or after delete). */
export function DetailPlaceholder() {
  return (
    <div className="flex min-h-0 flex-1 flex-col items-center justify-center gap-3">
      <span className="flex h-12 w-12 items-center justify-center rounded-2xl bg-surface-2 hairline">
        <Mic size={20} className="text-3" />
      </span>
      <p className="text-[13px] text-3">Select a recording</p>
    </div>
  );
}
