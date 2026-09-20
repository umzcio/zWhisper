import { motion, AnimatePresence } from "framer-motion";
import { Cpu, Cloud, Download, Trash2, Check } from "lucide-react";
import { cn } from "@/lib/utils";
import type { ModelInfo } from "@/components/models/modelsData";
import { formatMB } from "@/components/models/modelsData";
import DotMeter from "@/components/models/DotMeter";
import StarButton from "@/components/models/StarButton";
import ApiKeyPopover from "@/components/models/ApiKeyPopover";

export type DownloadStatus =
  | { status: "none" }
  | { status: "queued" }
  | { status: "downloading"; progress: number; mbps: number }
  | { status: "cancelling"; progress: number; mbps: number }
  | { status: "downloaded" };

export const NONE: DownloadStatus = { status: "none" };

interface ModelRowProps {
  model: ModelInfo;
  isActive: boolean;
  download: DownloadStatus;
  starred: boolean;
  keySaved: boolean;
  onToggleStar: () => void;
  onDownload: () => void;
  onCancelDownload: () => void;
  onDeleteDownload: () => void;
  onSetActive: () => void;
  onSaveKey: () => void;
}

const rowVariants = {
  hidden: { opacity: 0, y: 12 },
  show: {
    opacity: 1,
    y: 0,
    transition: { type: "spring" as const, stiffness: 400, damping: 30 },
  },
};

function Badge({
  label,
  className,
  layoutId,
}: {
  label: string;
  className: string;
  layoutId?: string;
}) {
  return (
    <motion.span
      layoutId={layoutId}
      transition={{ type: "spring", stiffness: 400, damping: 30 }}
      className={cn(
        "inline-flex items-center rounded-full px-1.5 py-px text-[10px] font-semibold",
        className
      )}
    >
      {label}
    </motion.span>
  );
}

export default function ModelRow({
  model,
  isActive,
  download,
  starred,
  keySaved,
  onToggleStar,
  onDownload,
  onCancelDownload,
  onDeleteDownload,
  onSetActive,
  onSaveKey,
}: ModelRowProps) {
  const isLocal = model.type === "local";
  const inFlight =
    download.status === "downloading" || download.status === "cancelling";
  const cancelling = download.status === "cancelling";
  const progress = inFlight ? download.progress : 0;
  const mbps = inFlight ? download.mbps : 0;

  return (
    <motion.div
      layout="position"
      variants={rowVariants}
      exit={{ opacity: 0, scale: 0.95, transition: { duration: 0.15 } }}
      className="group rounded-[10px] bg-surface-2 hairline"
    >
      <div className="flex h-16 items-center gap-3 px-3">
        {/* squircle icon */}
        <div
          className={cn(
            "flex h-9 w-9 shrink-0 items-center justify-center rounded-[10px]",
            isLocal ? "bg-accent-green/15 text-accent-green" : "bg-accent-orange/15 text-accent-orange"
          )}
        >
          {isLocal ? <Cpu size={17} /> : <Cloud size={17} />}
        </div>

        {/* name + badges + description */}
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5">
            <span className="truncate text-[13px] font-semibold text-1">
              {model.name}
              <span className="font-normal text-3"> — {model.engine}</span>
            </span>
            {isLocal ? (
              <Badge label="Local" className="bg-accent-green/15 text-accent-green" />
            ) : (
              <Badge label="Cloud" className="bg-accent-orange/15 text-accent-orange" />
            )}
            {model.badges.map((b) => (
              <Badge
                key={b.label}
                label={b.label}
                className={
                  b.tone === "purple"
                    ? "bg-accent-purple/15 text-accent-purple"
                    : "bg-accent-orange/15 text-accent-orange"
                }
              />
            ))}
            {isActive && (
              <Badge
                layoutId="active-model-badge"
                label="Active"
                className="bg-accent-green/20 text-accent-green"
              />
            )}
          </div>
          <p className="truncate text-[12px] text-2">
            {model.description}
            {model.priceHint && (
              <span className="text-3"> · {model.priceHint}</span>
            )}
          </p>
        </div>

        {/* meters */}
        <div className="hidden shrink-0 items-center gap-4 sm:flex">
          <DotMeter label="Speed" value={model.speed} />
          <DotMeter label="Accuracy" value={model.accuracy} />
        </div>

        {/* star */}
        <StarButton starred={starred} onToggle={onToggleStar} />

        {/* BYOK gear */}
        {model.byok && (
          <ApiKeyPopover provider={model.provider ?? model.engine} saved={keySaved} onSave={onSaveKey} />
        )}

        {/* state control */}
        <div className="flex w-[118px] shrink-0 items-center justify-end gap-1">
          {isLocal && download.status === "none" && (
            <motion.button
              type="button"
              onClick={onDownload}
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.97 }}
              transition={{ type: "spring", stiffness: 500, damping: 35 }}
              className="flex cursor-pointer items-center gap-1.5 rounded-[6px] hairline bg-surface-3/40 px-2.5 py-1.5 text-[12px] font-medium text-1 hover:bg-surface-3"
            >
              <Download size={12} />
              Download
            </motion.button>
          )}

          {isLocal && download.status === "queued" && (
            <span className="text-[12px] font-medium text-3">Queued</span>
          )}

          {isLocal && inFlight && (
            <motion.button
              type="button"
              onClick={onCancelDownload}
              disabled={cancelling}
              whileTap={{ scale: 0.97 }}
              className="cursor-pointer rounded-[6px] px-2 py-1.5 text-[12px] font-medium text-accent-red hover:bg-accent-red/10 disabled:cursor-default disabled:opacity-50"
            >
              Cancel
            </motion.button>
          )}

          {isLocal && download.status === "downloaded" && (
            <>
              {/* resting state */}
              <motion.span
                key="downloaded"
                initial={{ scale: 0.5, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                transition={{ type: "spring", stiffness: 500, damping: 35 }}
                className={cn(
                  "flex items-center gap-1 text-[12px] font-medium text-accent-green",
                  !isActive && "group-hover:hidden"
                )}
              >
                <Check size={13} strokeWidth={3} />
                Downloaded
              </motion.span>
              {/* hover actions */}
              {!isActive && (
                <span className="hidden items-center gap-1 group-hover:flex">
                  <motion.button
                    type="button"
                    onClick={onSetActive}
                    whileHover={{ scale: 1.02 }}
                    whileTap={{ scale: 0.97 }}
                    transition={{ type: "spring", stiffness: 500, damping: 35 }}
                    className="cursor-pointer rounded-[6px] bg-accent-blue px-2 py-1.5 text-[12px] font-semibold text-white"
                  >
                    Set Active
                  </motion.button>
                  <motion.button
                    type="button"
                    aria-label={`Delete ${model.name} download`}
                    onClick={onDeleteDownload}
                    whileTap={{ scale: 0.9 }}
                    className="flex h-7 w-7 cursor-pointer items-center justify-center rounded-md text-3 hover:bg-accent-red/10 hover:text-accent-red"
                  >
                    <Trash2 size={13} />
                  </motion.button>
                </span>
              )}
            </>
          )}

          {!isLocal && !isActive && (
            <motion.button
              type="button"
              onClick={onSetActive}
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.97 }}
              transition={{ type: "spring", stiffness: 500, damping: 35 }}
              className="cursor-pointer rounded-[6px] px-2 py-1.5 text-[12px] font-medium text-3 hover:bg-surface-3 hover:text-1"
            >
              Set Active
            </motion.button>
          )}
          {!isLocal && isActive && (
            <span className="text-[12px] font-medium text-accent-green">Ready</span>
          )}
        </div>
      </div>

      {/* download progress region (row expands 8px+ taller) */}
      <AnimatePresence initial={false}>
        {inFlight && (
          <motion.div
            key="progress"
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.25, ease: [0.16, 1, 0.3, 1] }}
            className="overflow-hidden"
          >
            <div className="px-3 pb-2.5">
              <div className="h-1 overflow-hidden rounded-full bg-surface-3">
                <motion.div
                  className={cn(
                    "h-full rounded-full",
                    cancelling ? "bg-accent-red" : "bg-accent-blue"
                  )}
                  initial={false}
                  animate={{ width: `${Math.round(progress * 100)}%` }}
                  transition={{ duration: 0.15, ease: "easeOut" }}
                />
              </div>
              <div className="mt-1 flex items-center justify-between font-mono text-[11px] text-2 tabular-nums">
                <span className={cancelling ? "text-accent-red" : undefined}>
                  {cancelling
                    ? "Cancelling…"
                    : `${formatMB(progress * model.sizeMB)} / ${model.sizeLabel} — ${mbps} MB/s`}
                </span>
                <span>{Math.round(progress * 100)}%</span>
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}
