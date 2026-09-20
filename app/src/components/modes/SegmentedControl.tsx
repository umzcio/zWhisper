import { motion } from "framer-motion";
import { cn } from "@/lib/utils";

const SPRING_MICRO = { type: "spring", stiffness: 500, damping: 35 } as const;

interface SegmentedControlProps<T extends string> {
  options: readonly T[];
  value: T;
  onChange: (v: T) => void;
  /** stable layoutId so the indicator slides between segments */
  layoutId: string;
}

/** macOS segmented control with a sliding indicator */
export default function SegmentedControl<T extends string>({
  options,
  value,
  onChange,
  layoutId,
}: SegmentedControlProps<T>) {
  return (
    <div className="flex items-center rounded-[8px] bg-surface-2 p-0.5 hairline">
      {options.map((opt) => {
        const selected = opt === value;
        return (
          <button
            key={opt}
            type="button"
            onClick={() => onChange(opt)}
            className="relative cursor-pointer rounded-[6px] px-3 py-1"
          >
            {selected && (
              <motion.span
                layoutId={layoutId}
                transition={SPRING_MICRO}
                className="absolute inset-0 rounded-[6px] bg-surface-3 shadow-sm"
              />
            )}
            <span
              className={cn(
                "relative text-[12px] font-medium",
                selected ? "text-1" : "text-2 hover:text-1"
              )}
            >
              {opt}
            </span>
          </button>
        );
      })}
    </div>
  );
}
