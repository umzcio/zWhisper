import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Check } from "lucide-react";
import TrafficLights from "@/components/TrafficLights";
import SidebarNav from "@/components/SidebarNav";
import HistoryListPane from "@/components/history/HistoryListPane";
import DetailPane, { DetailPlaceholder } from "@/components/history/DetailPane";
import type { HistoryEntry, HistoryFilters } from "@/components/history/historyData";
import {
  dayLabel,
  modeById,
  reprocessText,
  seedHistory,
  DEFAULT_FILTERS,
} from "@/components/history/historyData";
import { useMockTranscriptionEngine } from "@/lib/mockEngine";
import type { Mode } from "@/lib/modes";

/** filter state persists while navigating away and back within the session */
let savedFilters: HistoryFilters | null = null;

function applyFilters(entries: HistoryEntry[], f: HistoryFilters): HistoryEntry[] {
  const q = f.search.trim().toLowerCase();
  return entries.filter((e) => {
    if (f.modes.length > 0 && !f.modes.includes(e.modeId)) return false;
    if (f.date === "today" && dayLabel(e.createdAt) !== "Today") return false;
    if (f.date === "week" && Date.now() - e.createdAt.getTime() > 7 * 86400000) return false;
    if (q && !e.text.toLowerCase().includes(q)) return false;
    return true;
  });
}

type PendingReprocess =
  | { entryId: string; kind: "reprocess"; mode: Mode }
  | { entryId: string; kind: "undo" };

export default function History() {
  const [entries, setEntries] = useState<HistoryEntry[]>(seedHistory);
  const [selectedId, setSelectedId] = useState<string | null>(() => seedHistory()[0].id);
  const [filters, setFiltersState] = useState<HistoryFilters>(() => savedFilters ?? DEFAULT_FILTERS);
  const [playing, setPlaying] = useState(false);
  const [time, setTime] = useState(0);
  const [speed, setSpeed] = useState(1);
  const [shimmering, setShimmering] = useState(false);
  const [banner, setBanner] = useState<{ entryId: string; mode: Mode } | null>(null);
  const [reprocessFocus, setReprocessFocus] = useState(false);
  const [toast, setToast] = useState<string | null>(null);
  /** monotonic version counter per entry — drives the transcript morph animation */
  const [versions, setVersions] = useState<Record<string, number>>({});

  const pendingRef = useRef<PendingReprocess | null>(null);
  const toastTimer = useRef<number>(0);

  const setFilters = useCallback((f: HistoryFilters) => {
    savedFilters = f;
    setFiltersState(f);
  }, []);

  const filtered = useMemo(() => applyFilters(entries, filters), [entries, filters]);
  const selected = useMemo(
    () => entries.find((e) => e.id === selectedId) ?? null,
    [entries, selectedId]
  );
  const selectedRef = useRef(selected);
  useEffect(() => {
    selectedRef.current = selected;
  }, [selected]);

  /* ---- demo: the two "Processing…" rows resolve shortly after mount ---- */
  useEffect(() => {
    const t1 = window.setTimeout(() => {
      setEntries((prev) => prev.map((e) => (e.id === "h05" ? { ...e, processing: false } : e)));
    }, 3200);
    const t2 = window.setTimeout(() => {
      setEntries((prev) => prev.map((e) => (e.id === "h08" ? { ...e, processing: false } : e)));
    }, 4400);
    return () => {
      window.clearTimeout(t1);
      window.clearTimeout(t2);
    };
  }, []);

  /* ---- toast ---- */
  const showToast = useCallback((msg: string) => {
    setToast(msg);
    window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast(null), 2200);
  }, []);

  /* ---- reprocess pipeline (reuses the shared mock engine timing) ---- */
  const engine = useMockTranscriptionEngine({
    onPhaseChange: (phase) => {
      if (phase === "transcribing" || phase === "processing") setShimmering(true);
    },
    onPaste: () => {
      const pending = pendingRef.current;
      pendingRef.current = null;
      setShimmering(false);
      if (!pending) return;
      if (pending.kind === "reprocess") {
        setEntries((prev) =>
          prev.map((e) =>
            e.id === pending.entryId
              ? {
                  ...e,
                  undoStack: [...e.undoStack, { modeId: e.modeId, text: e.text }],
                  modeId: pending.mode.id,
                  text: reprocessText(e.text, pending.mode),
                }
              : e
          )
        );
        setBanner({ entryId: pending.entryId, mode: pending.mode });
      } else {
        let restoredMode: Mode | null = null;
        setEntries((prev) =>
          prev.map((e) => {
            if (e.id !== pending.entryId || e.undoStack.length === 0) return e;
            const last = e.undoStack[e.undoStack.length - 1];
            restoredMode = modeById(last.modeId);
            return {
              ...e,
              undoStack: e.undoStack.slice(0, -1),
              modeId: last.modeId,
              text: last.text,
            };
          })
        );
        setBanner(null);
        void restoredMode;
      }
      setVersions((v) => ({ ...v, [pending.entryId]: (v[pending.entryId] ?? 0) + 1 }));
      setPlaying(false);
      setTime(0);
      engineRef.current?.reset();
    },
  });
  const engineRef = useRef(engine);
  useEffect(() => {
    engineRef.current = engine;
  }, [engine]);

  const runPipeline = useCallback(
    (pending: PendingReprocess, mode: Mode) => {
      pendingRef.current = pending;
      engine.start(mode);
      engine.stop();
    },
    [engine]
  );

  const handleReprocess = useCallback(
    (mode: Mode) => {
      const cur = selectedRef.current;
      if (!cur || shimmering) return;
      runPipeline({ entryId: cur.id, kind: "reprocess", mode }, mode);
    },
    [runPipeline, shimmering]
  );

  const handleUndo = useCallback(() => {
    const cur = selectedRef.current;
    if (!cur || shimmering || cur.undoStack.length === 0) return;
    const prev = cur.undoStack[cur.undoStack.length - 1];
    runPipeline({ entryId: cur.id, kind: "undo" }, modeById(prev.modeId));
  }, [runPipeline, shimmering]);

  /* ---- selection ---- */
  const select = useCallback((id: string) => {
    setSelectedId((prev) => {
      if (prev !== id) {
        setPlaying(false);
        setTime(0);
      }
      return id;
    });
  }, []);

  /* ---- playback ---- */
  const durationRef = useRef(0);
  const speedRef = useRef(speed);
  const timeRef = useRef(time);
  useEffect(() => {
    durationRef.current = selected?.duration ?? 0;
    speedRef.current = speed;
    timeRef.current = time;
  }, [selected, speed, time]);

  useEffect(() => {
    if (!playing) return;
    let raf = 0;
    let last = performance.now();
    const tick = (now: number) => {
      const dt = ((now - last) / 1000) * speedRef.current;
      last = now;
      setTime((t) => {
        const nt = t + dt;
        if (nt >= durationRef.current) {
          setPlaying(false);
          return durationRef.current;
        }
        return nt;
      });
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [playing]);

  const togglePlay = useCallback(() => {
    if (!selectedRef.current) return;
    setPlaying((p) => {
      if (!p && timeRef.current >= durationRef.current) setTime(0);
      return !p;
    });
  }, []);

  const seekTo = useCallback((t: number) => {
    setTime(Math.max(0, Math.min(durationRef.current, t)));
  }, []);

  const skip = useCallback((delta: number) => {
    setTime((t) => Math.max(0, Math.min(durationRef.current, t + delta)));
  }, []);

  const quickPlay = useCallback(
    (id: string) => {
      select(id);
      setTime(0);
      setPlaying(true);
    },
    [select]
  );

  const quickReprocess = useCallback(
    (id: string) => {
      select(id);
      setReprocessFocus(true);
      window.setTimeout(() => setReprocessFocus(false), 1600);
    },
    [select]
  );

  /* ---- copy / export / delete ---- */
  const copyText = useCallback(
    (text: string) => {
      void navigator.clipboard?.writeText(text).catch(() => undefined);
      showToast("Transcript copied");
    },
    [showToast]
  );

  const handleDelete = useCallback(() => {
    const cur = selectedRef.current;
    if (!cur) return;
    setEntries((prev) => prev.filter((e) => e.id !== cur.id));
    setSelectedId(null);
    setPlaying(false);
    setBanner(null);
    showToast("Recording deleted");
  }, [showToast]);

  /* ---- keyboard: Space play/pause, ←/→ seek 5s (unless typing in search) ---- */
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const el = document.activeElement as HTMLElement | null;
      if (el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.isContentEditable)) return;
      if (e.key === " ") {
        e.preventDefault();
        togglePlay();
      } else if (e.key === "ArrowLeft") {
        e.preventDefault();
        skip(-5);
      } else if (e.key === "ArrowRight") {
        e.preventDefault();
        skip(5);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [togglePlay, skip]);

  const progress = selected && selected.duration > 0 ? time / selected.duration : 0;

  return (
    <div className="flex h-full items-center justify-center p-6">
      <motion.div
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: 8 }}
        transition={{ duration: 0.25 }}
        className="vibrancy relative flex h-[660px] max-h-full w-[1000px] max-w-full flex-col overflow-hidden rounded-[12px] shadow-window hairline"
      >
        {/* window chrome */}
        <div className="flex h-7 shrink-0 items-center border-b border-separator px-3">
          <TrafficLights />
          <span className="flex-1 text-center text-[13px] font-semibold tracking-[-0.01em] text-2">
            History
          </span>
          <span className="w-[52px]" />
        </div>

        <div className="flex min-h-0 flex-1">
          <SidebarNav />

          <HistoryListPane
            entries={filtered}
            totalCount={entries.length}
            selectedId={selectedId}
            playingId={playing ? selectedId : null}
            playProgress={progress}
            filters={filters}
            onFiltersChange={setFilters}
            onSelect={select}
            onQuickPlay={quickPlay}
            onQuickReprocess={quickReprocess}
            onQuickCopy={(e) => copyText(e.text)}
          />

          {/* detail pane: fades in 100ms after the list, crossfades on selection */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 0.2, delay: 0.1 }}
            className="flex min-w-0 flex-1 flex-col"
          >
            <AnimatePresence mode="wait" initial={false}>
              {selected ? (
                <motion.div
                  key={selected.id}
                  initial={{ opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -8 }}
                  transition={{ duration: 0.2 }}
                  className="flex min-h-0 flex-1 flex-col"
                >
                  <DetailPane
                    entry={selected}
                    playing={playing}
                    time={time}
                    speed={speed}
                    shimmering={shimmering}
                    versionKey={`${versions[selected.id] ?? 0}`}
                    bannerMode={banner && banner.entryId === selected.id ? banner.mode : null}
                    reprocessFocus={reprocessFocus}
                    onTogglePlay={togglePlay}
                    onSeek={seekTo}
                    onSkip={skip}
                    onSpeed={setSpeed}
                    onCopy={() => copyText(selected.text)}
                    onExport={() => showToast("Export is decorative in this prototype")}
                    onDelete={handleDelete}
                    onReprocess={handleReprocess}
                    onUndo={handleUndo}
                  />
                </motion.div>
              ) : (
                <motion.div
                  key="placeholder"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  transition={{ duration: 0.2 }}
                  className="flex min-h-0 flex-1 flex-col"
                >
                  <DetailPlaceholder />
                </motion.div>
              )}
            </AnimatePresence>
          </motion.div>
        </div>

        {/* toast */}
        <AnimatePresence>
          {toast && (
            <motion.div
              initial={{ opacity: 0, y: 12, scale: 0.96 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 8, scale: 0.98 }}
              transition={{ type: "spring", stiffness: 400, damping: 30 }}
              className="vibrancy absolute bottom-5 left-1/2 z-50 flex -translate-x-1/2 items-center gap-1.5 rounded-full px-3 py-1.5 shadow-popover hairline"
            >
              <Check size={12} className="text-accent-green" strokeWidth={3} />
              <span className="text-xs font-medium text-1">{toast}</span>
            </motion.div>
          )}
        </AnimatePresence>
      </motion.div>
    </div>
  );
}
