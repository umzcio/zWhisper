import { motion, AnimatePresence } from "framer-motion";
import { Cpu, Cloud, ArrowRight } from "lucide-react";
import type { ModelInfo } from "@/components/models/modelsData";
import DotMeter from "@/components/models/DotMeter";

interface ActiveBannerProps {
  model: ModelInfo;
  onChange: () => void;
}

/** Frosted banner showing the currently active model; crossfades when selection changes */
export default function ActiveBanner({ model, onChange }: ActiveBannerProps) {
  const isLocal = model.type === "local";
  return (
    <motion.div
      initial={{ y: -12, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={{ type: "spring", stiffness: 400, damping: 30 }}
      className="vibrancy relative overflow-hidden rounded-[10px] hairline"
    >
      <AnimatePresence mode="wait" initial={false}>
        <motion.div
          key={model.id}
          initial={{ opacity: 0, y: -6 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: 6 }}
          transition={{ duration: 0.18 }}
          className="flex items-center gap-3 px-3.5 py-3"
        >
          <div
            className={
              isLocal
                ? "flex h-9 w-9 items-center justify-center rounded-[10px] bg-accent-green/15 text-accent-green"
                : "flex h-9 w-9 items-center justify-center rounded-[10px] bg-accent-orange/15 text-accent-orange"
            }
          >
            {isLocal ? <Cpu size={17} /> : <Cloud size={17} />}
          </div>
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2">
              <span className="rounded-full bg-surface-2 px-2 py-0.5 text-[12px] font-semibold text-1 hairline">
                {model.name} — {model.engine}
              </span>
              <span className="inline-flex items-center gap-1 rounded-full bg-accent-green/20 px-1.5 py-px text-[10px] font-semibold text-accent-green">
                <span className="h-1.5 w-1.5 rounded-full bg-accent-green" />
                Active
              </span>
            </div>
            <p className="mt-0.5 text-[11px] text-3">
              {isLocal ? "On-device · unlimited" : `${model.provider} cloud · ${model.priceHint ?? "BYOK"}`}
            </p>
          </div>
          <div className="flex items-center gap-4">
            <DotMeter label="Speed" value={model.speed} />
            <DotMeter label="Accuracy" value={model.accuracy} />
          </div>
          <motion.button
            type="button"
            onClick={onChange}
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.97 }}
            transition={{ type: "spring", stiffness: 500, damping: 35 }}
            className="flex cursor-pointer items-center gap-1 rounded-[6px] hairline bg-surface-2 px-2.5 py-1.5 text-[12px] font-medium text-1 hover:bg-surface-3/70"
          >
            Change
            <ArrowRight size={12} className="text-3" />
          </motion.button>
        </motion.div>
      </AnimatePresence>
    </motion.div>
  );
}
