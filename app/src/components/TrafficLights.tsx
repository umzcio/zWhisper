import { useNavigate } from "react-router";
import { motion } from "framer-motion";
import { cn } from "@/lib/utils";

interface TrafficLightsProps {
  /** override red-button behavior; defaults to navigating back to home (dictation) */
  onClose?: () => void;
  className?: string;
}

/** macOS traffic-light window controls. Red navigates back to home by default. */
export default function TrafficLights({ onClose, className }: TrafficLightsProps) {
  const navigate = useNavigate();
  const close = onClose ?? (() => navigate("/"));
  return (
    <div className={cn("flex items-center gap-2", className)}>
      <motion.button
        type="button"
        aria-label="Close"
        onClick={close}
        whileTap={{ scale: 0.85 }}
        className="h-3 w-3 cursor-pointer rounded-full bg-[#FF5F57] ring-1 ring-black/20"
      />
      <motion.button
        type="button"
        aria-label="Minimize"
        whileTap={{ scale: 0.85 }}
        className="h-3 w-3 cursor-pointer rounded-full bg-[#FEBC2E] ring-1 ring-black/20"
      />
      <motion.button
        type="button"
        aria-label="Zoom"
        whileTap={{ scale: 0.85 }}
        className="h-3 w-3 cursor-pointer rounded-full bg-[#28C840] ring-1 ring-black/20"
      />
    </div>
  );
}
