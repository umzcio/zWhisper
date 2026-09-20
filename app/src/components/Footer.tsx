import { motion } from "framer-motion";
import { cn } from "@/lib/utils";

interface FooterProps {
  /** increment to trigger the zWhisper dock-icon bounce */
  bounceSignal?: number;
  className?: string;
}

const APP_DOTS = ["#FF9F0A", "#64D2FF", "#30D158", "#FF453A", "#BF5AF2", "#98989D"];

/** Decorative macOS Dock — frosted 56px bar, generic app dots + zWhisper icon */
export default function Footer({ bounceSignal = 0, className }: FooterProps) {
  return (
    <div className={cn("pointer-events-none flex justify-center pb-2", className)}>
      <div className="vibrancy-menubar pointer-events-auto flex h-14 items-center gap-2.5 rounded-2xl px-3 hairline">
        {APP_DOTS.map((c, i) => (
          <div
            key={i}
            className="h-9 w-9 rounded-[10px] hairline"
            style={{ background: `linear-gradient(160deg, ${c}55, ${c}22)` }}
          />
        ))}
        <div className="mx-1 h-8 w-px bg-separator" />
        <motion.img
          key={bounceSignal}
          src="/logo.svg"
          alt="zWhisper"
          initial={false}
          animate={bounceSignal > 0 ? { y: [0, -18, 0] } : undefined}
          transition={{ duration: 0.5, ease: "easeOut" }}
          className="h-9 w-9 rounded-[10px] hairline"
        />
      </div>
    </div>
  );
}
