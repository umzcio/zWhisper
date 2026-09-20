import { motion, AnimatePresence } from "framer-motion";
import { Check } from "lucide-react";

interface PageToastProps {
  message: string | null;
}

/** Bottom-right toast, slides up, dismissed by the parent after 3s */
export default function PageToast({ message }: PageToastProps) {
  return (
    <div className="pointer-events-none absolute bottom-4 right-4 z-40">
      <AnimatePresence>
        {message && (
          <motion.div
            key={message}
            initial={{ opacity: 0, y: 16, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 8, scale: 0.97 }}
            transition={{ type: "spring", stiffness: 400, damping: 30 }}
            className="vibrancy flex items-center gap-2 rounded-[10px] px-3 py-2 shadow-popover hairline"
          >
            <span className="flex h-4 w-4 items-center justify-center rounded-full bg-accent-green/20">
              <Check size={10} strokeWidth={3} className="text-accent-green" />
            </span>
            <span className="text-[12px] font-medium text-1">{message}</span>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
