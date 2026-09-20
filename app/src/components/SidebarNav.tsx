import { NavLink } from "react-router";
import { AudioLines, Layers, History, Cpu, BookOpenText, Settings } from "lucide-react";
import { cn } from "@/lib/utils";

const ITEMS = [
  { to: "/", label: "Dictation", icon: AudioLines, end: true },
  { to: "/modes", label: "Modes", icon: Layers },
  { to: "/history", label: "History", icon: History },
  { to: "/models", label: "Models", icon: Cpu },
  { to: "/vocabulary", label: "Vocabulary", icon: BookOpenText },
  { to: "/settings", label: "Settings", icon: Settings },
];

/** SF-Symbol-style sidebar for management windows. Active row: accent-tinted bg, accent icon. */
export default function SidebarNav() {
  return (
    <nav className="flex w-44 shrink-0 flex-col gap-0.5 border-r border-separator bg-surface-2/50 p-2">
      <div className="mb-2 flex items-center gap-2 px-2 pt-1">
        <img src="/logo.svg" alt="zWhisper" className="h-5 w-5 rounded-[5px]" />
        <span className="text-[13px] font-semibold text-1">zWhisper</span>
      </div>
      {ITEMS.map((item) => (
        <NavLink
          key={item.to}
          to={item.to}
          end={item.end}
          className={({ isActive }) =>
            cn(
              "flex items-center gap-2 rounded-md px-2 py-1.5 text-[13px] transition-colors",
              isActive
                ? "bg-[#0A84FF26] font-medium text-1"
                : "text-2 hover:bg-surface-3/60 hover:text-1"
            )
          }
        >
          {({ isActive }) => (
            <>
              <item.icon
                size={15}
                strokeWidth={2}
                className={isActive ? "text-accent-blue" : "text-3"}
              />
              {item.label}
            </>
          )}
        </NavLink>
      ))}
    </nav>
  );
}
