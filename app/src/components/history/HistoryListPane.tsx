import { Fragment, useEffect, useMemo, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import Lenis from "lenis";
import { Copy, ListFilter, Play, RefreshCw, Search, X } from "lucide-react";
import { cn } from "@/lib/utils";
import { MODES } from "@/lib/modes";
import type { ModeId } from "@/lib/modes";
import { ModeIcon } from "@/components/ModeSwitcher";
import type { HistoryEntry, HistoryFilters, DateFilter } from "@/components/history/historyData";
import {
  dayLabel,
  formatClockTime,
  formatDuration,
  modeById,
  previewOf,
  wordCount,
  DEFAULT_FILTERS,
} from "@/components/history/historyData";

interface HistoryListPaneProps {
  entries: HistoryEntry[];
  totalCount: number;
  selectedId: string | null;
  playingId: string | null;
  /** 0..1 playback progress for the playing row underline */
  playProgress: number;
  filters: HistoryFilters;
  onFiltersChange: (f: HistoryFilters) => void;
  onSelect: (id: string) => void;
  onQuickPlay: (id: string) => void;
  onQuickReprocess: (id: string) => void;
  onQuickCopy: (entry: HistoryEntry) => void;
}

const DATE_OPTIONS: { id: DateFilter; label: string }[] = [
  { id: "today", label: "Today" },
  { id: "week", label: "This week" },
  { id: "all", label: "All" },
];

/** 340px list pane: search + filter popover + date-grouped rows (Lenis-smoothed). */
export default function HistoryListPane({
  entries,
  totalCount,
  selectedId,
  playingId,
  playProgress,
  filters,
  onFiltersChange,
  onSelect,
  onQuickPlay,
  onQuickReprocess,
  onQuickCopy,
}: HistoryListPaneProps) {
  const [filterOpen, setFilterOpen] = useState(false);
  const filterRef = useRef<HTMLDivElement>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  // Lenis smooth scrolling for the long list
  useEffect(() => {
    const wrapper = scrollRef.current;
    const content = wrapper?.firstElementChild as HTMLElement | null;
    if (!wrapper || !content) return;
    const lenis = new Lenis({ wrapper, content, duration: 0.9, smoothWheel: true });
    let raf = 0;
    const loop = (time: number) => {
      lenis.raf(time);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => {
      cancelAnimationFrame(raf);
      lenis.destroy();
    };
  }, []);

  // close filter popover on outside pointer down
  useEffect(() => {
    if (!filterOpen) return;
    const onDown = (e: PointerEvent) => {
      if (filterRef.current && !filterRef.current.contains(e.target as Node)) setFilterOpen(false);
    };
    window.addEventListener("pointerdown", onDown);
    return () => window.removeEventListener("pointerdown", onDown);
  }, [filterOpen]);

  const groups = useMemo(() => {
    const out: { label: string; items: HistoryEntry[] }[] = [];
    for (const e of entries) {
      const label = dayLabel(e.createdAt);
      const last = out[out.length - 1];
      if (last && last.label === label) last.items.push(e);
      else out.push({ label, items: [e] });
    }
    return out;
  }, [entries]);

  const activeFilterCount = filters.modes.length + (filters.date !== "all" ? 1 : 0);
  const filtersActive = activeFilterCount > 0 || filters.search.trim().length > 0;

  const toggleMode = (id: ModeId) => {
    const modes = filters.modes.includes(id)
      ? filters.modes.filter((m) => m !== id)
      : [...filters.modes, id];
    onFiltersChange({ ...filters, modes });
  };

  return (
    <div className="flex w-[340px] shrink-0 flex-col border-r border-separator">
      {/* header: search + filter */}
      <div className="flex shrink-0 items-center gap-2 border-b border-separator p-3">
        <div className="flex h-7 min-w-0 flex-1 items-center gap-1.5 rounded-md bg-surface-2 px-2 hairline focus-within:ring-1 focus-within:ring-accent-blue/50">
          <Search size={13} className="shrink-0 text-3" />
          <input
            value={filters.search}
            onChange={(e) => onFiltersChange({ ...filters, search: e.target.value })}
            placeholder="Search transcripts"
            className="min-w-0 flex-1 bg-transparent text-[13px] text-1 outline-none placeholder:text-3"
          />
          {filters.search && (
            <button
              type="button"
              aria-label="Clear search"
              onClick={() => onFiltersChange({ ...filters, search: "" })}
              className="cursor-pointer text-3 hover:text-1"
            >
              <X size={12} />
            </button>
          )}
        </div>
        <div ref={filterRef} className="relative shrink-0">
          <motion.button
            type="button"
            aria-label="Filters"
            onClick={() => setFilterOpen((o) => !o)}
            whileTap={{ scale: 0.95 }}
            transition={{ type: "spring", stiffness: 500, damping: 35 }}
            className={cn(
              "relative flex h-7 w-7 cursor-pointer items-center justify-center rounded-md hairline",
              filterOpen || activeFilterCount > 0
                ? "bg-accent-blue/20 text-accent-blue"
                : "bg-surface-2 text-2 hover:bg-surface-3 hover:text-1"
            )}
          >
            <ListFilter size={13} />
            {activeFilterCount > 0 && (
              <span className="absolute -right-1 -top-1 flex h-3.5 w-3.5 items-center justify-center rounded-full bg-accent-blue font-mono text-[9px] font-semibold text-white">
                {activeFilterCount}
              </span>
            )}
          </motion.button>

          {/* filter popover */}
          <AnimatePresence>
            {filterOpen && (
              <motion.div
                initial={{ opacity: 0, scale: 0.92, y: -6 }}
                animate={{ opacity: 1, scale: 1, y: 0 }}
                exit={{ opacity: 0, scale: 0.95, y: -4 }}
                transition={{ type: "spring", stiffness: 400, damping: 30 }}
                className="vibrancy absolute right-0 top-9 z-40 w-60 rounded-[14px] p-3 shadow-popover hairline"
              >
                <p className="mb-1.5 text-[11px] font-semibold uppercase tracking-wide text-3">Modes</p>
                <div className="mb-3 flex flex-wrap gap-1">
                  {MODES.map((m) => {
                    const on = filters.modes.includes(m.id);
                    return (
                      <motion.button
                        key={m.id}
                        type="button"
                        onClick={() => toggleMode(m.id)}
                        whileTap={{ scale: 0.95 }}
                        transition={{ type: "spring", stiffness: 500, damping: 35 }}
                        className={cn(
                          "flex cursor-pointer items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium hairline",
                          on
                            ? "border-transparent bg-accent-blue/20 text-accent-blue"
                            : "bg-surface-2 text-2 hover:bg-surface-3 hover:text-1"
                        )}
                      >
                        <ModeIcon mode={m} size={11} />
                        {m.name}
                      </motion.button>
                    );
                  })}
                </div>
                <p className="mb-1.5 text-[11px] font-semibold uppercase tracking-wide text-3">Date</p>
                <div className="flex gap-1">
                  {DATE_OPTIONS.map((d) => {
                    const on = filters.date === d.id;
                    return (
                      <motion.button
                        key={d.id}
                        type="button"
                        onClick={() => onFiltersChange({ ...filters, date: d.id })}
                        whileTap={{ scale: 0.95 }}
                        transition={{ type: "spring", stiffness: 500, damping: 35 }}
                        className={cn(
                          "flex-1 cursor-pointer rounded-md px-2 py-1 text-[11px] font-medium hairline",
                          on
                            ? "border-transparent bg-accent-blue/20 text-accent-blue"
                            : "bg-surface-2 text-2 hover:bg-surface-3 hover:text-1"
                        )}
                      >
                        {d.label}
                      </motion.button>
                    );
                  })}
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>

      {/* rows */}
      <div ref={scrollRef} className="min-h-0 flex-1 overflow-y-auto">
        <motion.div
          initial="hidden"
          animate="show"
          variants={{ hidden: {}, show: { transition: { staggerChildren: 0.04 } } }}
          className="py-1"
        >
          <AnimatePresence initial={false} mode="popLayout">
            {groups.map((g) => (
              <Fragment key={g.label}>
                <motion.div
                  key={`h-${g.label}`}
                  layout="position"
                  exit={{ opacity: 0 }}
                  className="vibrancy-menubar sticky top-0 z-10 px-3 pb-1 pt-2.5 text-[11px] font-semibold uppercase tracking-wide text-3"
                >
                  {g.label}
                </motion.div>
                {g.items.map((e) => {
                  const mode = modeById(e.modeId);
                  const selected = e.id === selectedId;
                  const isPlaying = e.id === playingId;
                  return (
                    <motion.div
                      key={e.id}
                      layout="position"
                      variants={{
                        hidden: { opacity: 0, y: 12 },
                        show: {
                          opacity: 1,
                          y: 0,
                          transition: { type: "spring", stiffness: 400, damping: 30 },
                        },
                      }}
                      exit={{ opacity: 0, height: 0, transition: { duration: 0.25 } }}
                      className="overflow-hidden"
                    >
                      <div
                        role="button"
                        tabIndex={0}
                        onClick={() => onSelect(e.id)}
                        onKeyDown={(ev) => {
                          if (ev.key === "Enter") onSelect(e.id);
                        }}
                        className={cn(
                          "group relative flex h-[72px] cursor-pointer items-center gap-2.5 px-3 transition-colors",
                          selected ? "bg-[#0A84FF26]" : "hover:bg-surface-3/70"
                        )}
                      >
                        {/* mode icon squircle */}
                        <span
                          className="flex h-7 w-7 shrink-0 items-center justify-center rounded-[8px]"
                          style={{ backgroundColor: `${mode.color}26` }}
                        >
                          <ModeIcon mode={mode} size={14} />
                        </span>
                        <span className="min-w-0 flex-1">
                          <span className="block truncate text-[13px] font-medium text-1">
                            {previewOf(e.text)}
                          </span>
                          <span className="mt-0.5 block truncate text-[11px] text-2">
                            {e.processing ? (
                              <span className="text-accent-blue">Processing…</span>
                            ) : (
                              <>
                                {formatClockTime(e.createdAt)} · {formatDuration(e.duration)} ·{" "}
                                {wordCount(e.text)} words
                              </>
                            )}
                          </span>
                          {/* indeterminate progress while processing */}
                          {e.processing && (
                            <span className="mt-1 block h-0.5 w-full overflow-hidden rounded-full bg-surface-3">
                              <motion.span
                                className="block h-full w-1/3 rounded-full bg-accent-blue"
                                animate={{ x: ["-100%", "300%"] }}
                                transition={{ duration: 1.1, repeat: Infinity, ease: "easeInOut" }}
                              />
                            </span>
                          )}
                        </span>
                        {/* mode chip (hidden on hover) / quick actions */}
                        <span
                          className={cn(
                            "shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.02em] hairline bg-surface-2 text-2",
                            "group-hover:opacity-0"
                          )}
                        >
                          {mode.name}
                        </span>
                        <span className="pointer-events-none absolute right-3 flex items-center gap-0.5 opacity-0 transition-opacity duration-100 group-hover:pointer-events-auto group-hover:opacity-100">
                          {[
                            { icon: Play, label: "Play", fn: () => onQuickPlay(e.id) },
                            { icon: RefreshCw, label: "Reprocess", fn: () => onQuickReprocess(e.id) },
                            { icon: Copy, label: "Copy", fn: () => onQuickCopy(e) },
                          ].map((a) => (
                            <motion.button
                              key={a.label}
                              type="button"
                              aria-label={a.label}
                              title={a.label}
                              onClick={(ev) => {
                                ev.stopPropagation();
                                a.fn();
                              }}
                              whileTap={{ scale: 0.9 }}
                              transition={{ type: "spring", stiffness: 500, damping: 35 }}
                              className="flex h-6 w-6 cursor-pointer items-center justify-center rounded-md bg-surface-2 text-2 hairline hover:bg-surface-3 hover:text-1"
                            >
                              <a.icon size={12} />
                            </motion.button>
                          ))}
                        </span>
                        {/* playback progress underline */}
                        {isPlaying && (
                          <span className="absolute inset-x-3 bottom-0 h-0.5 rounded-full bg-surface-3/60">
                            <span
                              className="block h-full rounded-full bg-accent-blue"
                              style={{ width: `${playProgress * 100}%` }}
                            />
                          </span>
                        )}
                      </div>
                    </motion.div>
                  );
                })}
              </Fragment>
            ))}
          </AnimatePresence>

          {/* empty state */}
          {entries.length === 0 && (
            <motion.div
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.25 }}
              className="flex flex-col items-center gap-3 px-6 py-12 text-center"
            >
              <img src="/empty-history.svg" alt="" className="h-28 w-36 opacity-80" />
              <p className="text-[13px] text-2">
                {totalCount === 0 ? "No dictations yet" : "No dictations match these filters"}
              </p>
              {filtersActive && (
                <motion.button
                  type="button"
                  onClick={() => onFiltersChange(DEFAULT_FILTERS)}
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.97 }}
                  transition={{ type: "spring", stiffness: 500, damping: 35 }}
                  className="cursor-pointer rounded-md bg-surface-2 px-3 py-1.5 text-xs font-medium text-1 hairline hover:bg-surface-3"
                >
                  Clear Filters
                </motion.button>
              )}
            </motion.div>
          )}
        </motion.div>
      </div>
    </div>
  );
}
