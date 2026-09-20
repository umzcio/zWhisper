import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Plus, Search, CheckCircle2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { useApp } from "@/lib/store";
import TrafficLights from "@/components/TrafficLights";
import SidebarNav from "@/components/SidebarNav";
import ModeCard from "@/components/modes/ModeCard";
import ModeEditorSheet from "@/components/modes/ModeEditorSheet";
import type { ModeDraft } from "@/components/modes/ModeEditorSheet";
import ModeCycleStrip from "@/components/modes/ModeCycleStrip";
import SegmentedControl from "@/components/modes/SegmentedControl";
import type { ActivationRule, LibraryMode } from "@/components/modes/data";
import { NEW_MODE_SAMPLE, nextShortcut, seedLibrary } from "@/components/modes/data";

const SPRING_MICRO = { type: "spring", stiffness: 500, damping: 35 } as const;
const SEGMENTS = ["All", "Built-in", "Custom"] as const;
type Segment = (typeof SEGMENTS)[number];

function describeNew(instructions: string): string {
  const first = instructions.trim().split(/[.\n]/)[0]?.trim();
  if (!first) return "Custom mode";
  return first.length > 64 ? `${first.slice(0, 61)}…` : first;
}

export default function Modes() {
  const { mode: activeStoreMode } = useApp();
  const [library, setLibrary] = useState<LibraryMode[]>(seedLibrary);
  const [rulesByMode, setRulesByMode] = useState<Record<string, ActivationRule[]>>(() => ({
    email: [{ id: "r-email-1", app: "Mail", domain: "" }],
    "slack-update": [{ id: "r-slack-1", app: "Slack", domain: "" }],
    "support-reply": [{ id: "r-support-1", app: "Safari", domain: "help.zwhisper.app" }],
  }));
  const [segment, setSegment] = useState<Segment>("All");
  const [query, setQuery] = useState("");
  const [sheetOpen, setSheetOpen] = useState(false);
  const [draft, setDraft] = useState<ModeDraft | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<LibraryMode | null>(null);
  const [collapsingId, setCollapsingId] = useState<string | null>(null);
  const [lastAddedId, setLastAddedId] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const toastTimer = useRef<number | null>(null);

  const showToast = useCallback((msg: string) => {
    if (toastTimer.current !== null) window.clearTimeout(toastTimer.current);
    setToast(msg);
    toastTimer.current = window.setTimeout(() => setToast(null), 3000);
  }, []);

  useEffect(() => {
    return () => {
      if (toastTimer.current !== null) window.clearTimeout(toastTimer.current);
    };
  }, []);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return library.filter((m) => {
      if (segment === "Built-in" && !m.builtIn) return false;
      if (segment === "Custom" && m.builtIn) return false;
      if (q && !`${m.name} ${m.description}`.toLowerCase().includes(q)) return false;
      return true;
    });
  }, [library, segment, query]);

  const openEditor = useCallback(
    (m: LibraryMode) => {
      setDraft({
        mode: { ...m },
        rules: (rulesByMode[m.id] ?? []).map((r) => ({ ...r })),
        isNew: false,
      });
      setSheetOpen(true);
    },
    [rulesByMode]
  );

  const openNewMode = useCallback(() => {
    setDraft({
      mode: {
        id: `custom-${Date.now()}`,
        name: "",
        icon: "Sparkles",
        color: "#BF5AF2",
        shortcut: nextShortcut(library),
        description: "Custom mode",
        builtIn: false,
        readSelected: false,
        readClipboard: false,
        instructions: "",
        script: NEW_MODE_SAMPLE.script,
        processed: NEW_MODE_SAMPLE.processed,
      },
      rules: [],
      isNew: true,
    });
    setSheetOpen(true);
  }, [library]);

  const handleSave = useCallback(
    (d: ModeDraft) => {
      const saved: LibraryMode = {
        ...d.mode,
        name: d.mode.name.trim(),
        description: d.isNew ? describeNew(d.mode.instructions) : d.mode.description,
      };
      setLibrary((lib) => {
        const exists = lib.some((m) => m.id === saved.id);
        return exists ? lib.map((m) => (m.id === saved.id ? saved : m)) : [...lib, saved];
      });
      setRulesByMode((r) => ({ ...r, [saved.id]: d.rules }));
      setLastAddedId(saved.id);
      setSheetOpen(false);
      setDraft(null);
      showToast(`${saved.name} saved · ${saved.shortcut} assigned`);
    },
    [showToast]
  );

  const handleDuplicate = useCallback(
    (m: LibraryMode) => {
      const clone: LibraryMode = {
        ...m,
        id: `custom-${Date.now()}`,
        name: `${m.name} copy`,
        shortcut: nextShortcut(library),
        builtIn: false,
      };
      setLibrary((lib) => {
        const idx = lib.findIndex((x) => x.id === m.id);
        const next = [...lib];
        next.splice(idx + 1, 0, clone);
        return next;
      });
      setRulesByMode((r) => ({
        ...r,
        [clone.id]: (r[m.id] ?? []).map((rule) => ({ ...rule, id: `${rule.id}-c${Date.now()}` })),
      }));
      setLastAddedId(clone.id);
    },
    [library]
  );

  const confirmDelete = useCallback(() => {
    if (!deleteTarget) return;
    setCollapsingId(deleteTarget.id);
    setLibrary((lib) => lib.filter((m) => m.id !== deleteTarget.id));
    setRulesByMode((r) => {
      const next = { ...r };
      delete next[deleteTarget.id];
      return next;
    });
    setDeleteTarget(null);
    window.setTimeout(() => setCollapsingId(null), 300);
  }, [deleteTarget]);

  return (
    <div className="flex h-full items-center justify-center p-6">
      <motion.div
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: 8 }}
        transition={{ duration: 0.25 }}
        className="vibrancy relative flex h-[640px] max-h-full w-[960px] max-w-full flex-col overflow-hidden rounded-[12px] shadow-window hairline"
      >
        {/* window chrome */}
        <div className="flex h-7 shrink-0 items-center border-b border-separator px-3">
          <TrafficLights />
          <span className="flex-1 text-center text-[13px] font-semibold tracking-[-0.01em] text-2">
            Modes
          </span>
          <span className="w-[52px]" />
        </div>

        <div className="flex min-h-0 flex-1">
          <SidebarNav />

          {/* content */}
          <div className="flex min-w-0 flex-1 flex-col">
            {/* header */}
            <div className="flex items-start justify-between gap-4 px-6 pt-5">
              <div>
                <h1 className="text-[20px] font-bold tracking-[-0.02em] text-1">Modes</h1>
                <p className="mt-0.5 text-[13px] text-2">
                  Choose how zWhisper rewrites your voice. Modes persist across sessions.
                </p>
              </div>
              <motion.button
                type="button"
                onClick={openNewMode}
                whileHover={{ scale: 1.02 }}
                whileTap={{ scale: 0.97 }}
                transition={SPRING_MICRO}
                className="flex shrink-0 cursor-pointer items-center gap-1.5 rounded-md bg-accent-blue px-3 py-1.5 text-[13px] font-medium text-white"
              >
                <Plus size={14} strokeWidth={2.5} />
                New Mode
              </motion.button>
            </div>

            {/* toolbar */}
            <div className="flex items-center justify-between gap-3 px-6 pt-4">
              <SegmentedControl
                options={SEGMENTS}
                value={segment}
                onChange={setSegment}
                layoutId="modes-segment"
              />
              <div className="relative">
                <Search
                  size={13}
                  className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-3"
                />
                <input
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder="Search"
                  className="h-7 w-48 rounded-md bg-surface-2 pl-8 pr-2.5 text-[12px] text-1 hairline placeholder:text-3 focus:outline-none focus:ring-2 focus:ring-accent-blue/60"
                />
              </div>
            </div>

            {/* mode grid */}
            <div className="min-h-0 flex-1 overflow-y-auto px-6 pb-4 pt-4">
              {filtered.length === 0 ? (
                <div className="flex h-full items-center justify-center text-[13px] text-3">
                  No modes match “{query}”.
                </div>
              ) : (
                <motion.div layout className="grid grid-cols-2 gap-4">
                  <AnimatePresence mode="popLayout">
                    {filtered.map((m, i) => {
                      const collapsing = m.id === collapsingId;
                      const isNew = m.id === lastAddedId;
                      return (
                        <motion.div
                          key={m.id}
                          layout
                          initial={isNew ? { opacity: 0, scale: 0.8 } : { opacity: 0, y: 16 }}
                          animate={{
                            opacity: 1,
                            scale: 1,
                            y: 0,
                            transition: {
                              type: "spring",
                              stiffness: 400,
                              damping: 30,
                              delay: isNew ? 0 : i * 0.05,
                            },
                          }}
                          exit={
                            collapsing
                              ? { height: 0, opacity: 0, transition: { duration: 0.25 } }
                              : { scale: 0.9, opacity: 0, transition: { duration: 0.15 } }
                          }
                          transition={{ type: "spring", stiffness: 400, damping: 30 }}
                          className={cn(collapsing && "overflow-hidden")}
                        >
                          <ModeCard
                            mode={m}
                            active={m.storeId !== undefined && m.storeId === activeStoreMode.id}
                            onOpen={openEditor}
                            onDuplicate={handleDuplicate}
                            onDelete={setDeleteTarget}
                          />
                        </motion.div>
                      );
                    })}
                  </AnimatePresence>
                </motion.div>
              )}
            </div>

            {/* mode switching demo strip */}
            <ModeCycleStrip modes={library} />
          </div>
        </div>

        {/* editor sheet */}
        <ModeEditorSheet
          open={sheetOpen}
          draft={draft}
          onCancel={() => {
            setSheetOpen(false);
            setDraft(null);
          }}
          onSave={handleSave}
        />

        {/* delete confirmation */}
        <AnimatePresence>
          {deleteTarget && (
            <div className="absolute inset-0 z-50 flex items-center justify-center">
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.2 }}
                className="absolute inset-0 bg-black/30"
                onClick={() => setDeleteTarget(null)}
              />
              <motion.div
                initial={{ opacity: 0, scale: 0.95 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.95 }}
                transition={{ type: "spring", stiffness: 400, damping: 30 }}
                className="vibrancy relative w-[280px] rounded-[12px] p-4 text-center shadow-window hairline"
              >
                <p className="text-[13px] font-semibold text-1">
                  Delete “{deleteTarget.name}”?
                </p>
                <p className="mt-1 text-[12px] text-2">This can’t be undone.</p>
                <div className="mt-3 flex gap-2">
                  <motion.button
                    type="button"
                    onClick={() => setDeleteTarget(null)}
                    whileTap={{ scale: 0.97 }}
                    transition={SPRING_MICRO}
                    className="flex-1 cursor-pointer rounded-md bg-surface-3 px-3 py-1.5 text-[13px] text-1 hover:bg-surface-3/70"
                  >
                    Cancel
                  </motion.button>
                  <motion.button
                    type="button"
                    onClick={confirmDelete}
                    whileTap={{ scale: 0.97 }}
                    transition={SPRING_MICRO}
                    className="flex-1 cursor-pointer rounded-md bg-accent-red px-3 py-1.5 text-[13px] font-medium text-white"
                  >
                    Delete
                  </motion.button>
                </div>
              </motion.div>
            </div>
          )}
        </AnimatePresence>

        {/* save toast */}
        <AnimatePresence>
          {toast && (
            <motion.div
              initial={{ opacity: 0, x: 24 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: 24 }}
              transition={{ type: "spring", stiffness: 400, damping: 30 }}
              className="vibrancy absolute right-4 top-10 z-50 flex items-center gap-2 rounded-[10px] px-3 py-2 shadow-popover hairline"
            >
              <CheckCircle2 size={14} className="text-accent-green" />
              <span className="text-[12px] font-medium text-1">{toast}</span>
            </motion.div>
          )}
        </AnimatePresence>
      </motion.div>
    </div>
  );
}
