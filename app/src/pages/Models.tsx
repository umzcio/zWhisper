import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import Lenis from "lenis";
import TrafficLights from "@/components/TrafficLights";
import SidebarNav from "@/components/SidebarNav";
import { MODELS } from "@/components/models/modelsData";
import type { ModelInfo, SortKey } from "@/components/models/modelsData";
import ModelRow from "@/components/models/ModelRow";
import type { DownloadStatus } from "@/components/models/ModelRow";
import FilterBar from "@/components/models/FilterBar";
import type { TypeFilter } from "@/components/models/FilterBar";
import ActiveBanner from "@/components/models/ActiveBanner";
import PageToast from "@/components/models/PageToast";

const MAX_CONCURRENT = 2;
/** ~6s per download at a 150ms tick */
const TICK_MS = 150;
const TICK_STEP = TICK_MS / 6000;

export default function Models() {
  const [activeId, setActiveId] = useState("fast");
  const [downloads, setDownloads] = useState<Record<string, DownloadStatus>>({
    nano: { status: "downloaded" },
    fast: { status: "downloaded" },
  });
  const [queue, setQueue] = useState<string[]>([]);
  const [favorites, setFavorites] = useState<string[]>(["fast"]);
  const [savedKeys, setSavedKeys] = useState<string[]>([]);
  const [type, setType] = useState<TypeFilter>("all");
  const [provider, setProvider] = useState("All providers");
  const [favoritesOnly, setFavoritesOnly] = useState(false);
  const [sort, setSort] = useState<SortKey>("speed");
  const [toast, setToast] = useState<string | null>(null);

  const listRef = useRef<HTMLDivElement>(null);
  const listContentRef = useRef<HTMLDivElement>(null);
  const lenisRef = useRef<Lenis | null>(null);
  const toastTimer = useRef<number | undefined>(undefined);

  /* Lenis smooth scrolling inside the model list */
  useEffect(() => {
    const wrapper = listRef.current;
    const content = listContentRef.current;
    if (!wrapper || !content) return;
    const lenis = new Lenis({ wrapper, content, lerp: 0.12 });
    lenisRef.current = lenis;
    let raf = 0;
    const loop = (time: number) => {
      lenis.raf(time);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => {
      cancelAnimationFrame(raf);
      lenis.destroy();
      lenisRef.current = null;
    };
  }, []);

  const showToast = useCallback((msg: string) => {
    setToast(msg);
    window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast(null), 3000);
  }, []);

  /* download tick: advance all in-flight downloads with jitter */
  useEffect(() => {
    const iv = window.setInterval(() => {
      setDownloads((prev) => {
        const flying = Object.entries(prev).filter(([, s]) => s.status === "downloading");
        if (flying.length === 0) return prev;
        const next = { ...prev };
        for (const [id, s] of flying) {
          if (s.status !== "downloading") continue;
          const step = TICK_STEP * (0.5 + Math.random());
          const progress = Math.min(1, s.progress + step);
          const mbps = Math.round(90 + Math.random() * 70);
          next[id] =
            progress >= 1
              ? { status: "downloaded" }
              : { status: "downloading", progress, mbps };
        }
        return next;
      });
    }, TICK_MS);
    return () => window.clearInterval(iv);
  }, []);

  /* promote queued downloads when a slot frees up */
  useEffect(() => {
    const flying = Object.values(downloads).filter((s) => s.status === "downloading").length;
    if (flying < MAX_CONCURRENT && queue.length > 0) {
      const [next, ...rest] = queue;
      setQueue(rest);
      setDownloads((prev) => ({
        ...prev,
        [next]: { status: "downloading", progress: 0, mbps: 120 },
      }));
    }
  }, [downloads, queue]);

  const startDownload = useCallback((id: string) => {
    setDownloads((prev) => {
      const flying = Object.values(prev).filter((s) => s.status === "downloading").length;
      if (flying < MAX_CONCURRENT) {
        return { ...prev, [id]: { status: "downloading", progress: 0, mbps: 120 } };
      }
      setQueue((q) => [...q, id]);
      return { ...prev, [id]: { status: "queued" } };
    });
  }, []);

  const cancelDownload = useCallback((id: string) => {
    setDownloads((prev) => {
      const s = prev[id];
      if (!s) return prev;
      if (s.status === "queued") {
        setQueue((q) => q.filter((qid) => qid !== id));
        const next = { ...prev };
        delete next[id];
        return next;
      }
      if (s.status === "downloading") {
        return { ...prev, [id]: { status: "cancelling", progress: s.progress, mbps: s.mbps } };
      }
      return prev;
    });
    window.setTimeout(() => {
      setDownloads((prev) => {
        if (prev[id]?.status !== "cancelling") return prev;
        const next = { ...prev };
        delete next[id];
        return next;
      });
    }, 350);
  }, []);

  const deleteDownload = useCallback((id: string) => {
    setDownloads((prev) => {
      const next = { ...prev };
      delete next[id];
      return next;
    });
  }, []);

  const toggleFavorite = useCallback((id: string) => {
    setFavorites((prev) => (prev.includes(id) ? prev.filter((f) => f !== id) : [...prev, id]));
  }, []);

  const saveKey = useCallback(
    (id: string) => {
      setSavedKeys((prev) => (prev.includes(id) ? prev : [...prev, id]));
      showToast("API key saved locally");
    },
    [showToast]
  );

  const activeModel = useMemo<ModelInfo>(
    () => MODELS.find((m) => m.id === activeId) ?? MODELS[1],
    [activeId]
  );

  const visible = useMemo(() => {
    let list = MODELS.filter((m) => {
      if (type !== "all" && m.type !== type) return false;
      if (provider !== "All providers" && m.provider !== provider) return false;
      if (favoritesOnly && !favorites.includes(m.id)) return false;
      return true;
    });
    list = [...list].sort((a, b) => {
      if (sort === "size") return a.sizeMB - b.sizeMB;
      return b[sort] - a[sort];
    });
    return list;
  }, [type, provider, favoritesOnly, favorites, sort]);

  return (
    <div className="flex h-full items-center justify-center p-4">
      <motion.div
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.25 }}
        className="vibrancy relative flex h-[660px] w-[1000px] max-w-full flex-col overflow-hidden rounded-[12px] shadow-window hairline"
      >
        {/* title bar */}
        <div className="flex h-7 shrink-0 items-center border-b border-separator px-3">
          <TrafficLights />
          <span className="flex-1 text-center text-[13px] font-semibold tracking-[-0.01em] text-2">
            Models
          </span>
          <span className="w-[52px]" />
        </div>

        <div className="flex min-h-0 flex-1">
          <SidebarNav />

          <div className="relative flex min-w-0 flex-1 flex-col">
            {/* header */}
            <div className="shrink-0 px-5 pt-4">
              <h1 className="text-[20px] font-bold tracking-[-0.02em] text-1">Models</h1>
              <p className="mt-0.5 text-[12px] text-2">
                Local models run on-device and are unlimited. Cloud models use your own API keys.
              </p>

              <div className="mt-3">
                <ActiveBanner
                  model={activeModel}
                  onChange={() => lenisRef.current?.scrollTo(0, { immediate: false })}
                />
              </div>

              <div className="mt-3">
                <FilterBar
                  type={type}
                  onTypeChange={setType}
                  provider={provider}
                  onProviderChange={setProvider}
                  favoritesOnly={favoritesOnly}
                  onToggleFavorites={() => setFavoritesOnly((v) => !v)}
                  sort={sort}
                  onSortChange={setSort}
                />
              </div>
            </div>

            {/* model list (Lenis smooth scroll) */}
            <div ref={listRef} className="min-h-0 flex-1 overflow-y-auto px-5 py-3">
              <div ref={listContentRef}>
                <motion.div
                  variants={{ hidden: {}, show: { transition: { staggerChildren: 0.035 } } }}
                  initial="hidden"
                  animate="show"
                  className="flex flex-col gap-2"
                >
                  <AnimatePresence>
                    {visible.map((m) => (
                      <ModelRow
                        key={m.id}
                        model={m}
                        isActive={m.id === activeId}
                        download={downloads[m.id] ?? { status: "none" }}
                        starred={favorites.includes(m.id)}
                        keySaved={savedKeys.includes(m.id)}
                        onToggleStar={() => toggleFavorite(m.id)}
                        onDownload={() => startDownload(m.id)}
                        onCancelDownload={() => cancelDownload(m.id)}
                        onDeleteDownload={() => deleteDownload(m.id)}
                        onSetActive={() => setActiveId(m.id)}
                        onSaveKey={() => saveKey(m.id)}
                      />
                    ))}
                  </AnimatePresence>
                </motion.div>

                {visible.length === 0 && (
                  <div className="flex h-32 items-center justify-center text-[12px] text-3">
                    No models match these filters.
                  </div>
                )}
              </div>
            </div>

            {/* info footer */}
            <div className="vibrancy-menubar flex shrink-0 items-center justify-between border-t border-separator px-5 py-2.5">
              <p className="text-[11px] text-2">
                Local models never leave your Mac. zWhisper is free with unlimited local
                transcription.
              </p>
              <button
                type="button"
                className="cursor-pointer text-[11px] font-medium text-accent-blue hover:underline"
              >
                Compare models
              </button>
            </div>

            <PageToast message={toast} />
          </div>
        </div>
      </motion.div>
    </div>
  );
}
