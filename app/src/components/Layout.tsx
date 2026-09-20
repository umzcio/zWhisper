import { memo, useRef } from "react";
import { Outlet } from "react-router";
import gsap from "gsap";
import { useGSAP } from "@gsap/react";
import Navbar from "@/components/Navbar";

gsap.registerPlugin(useGSAP);

/** Wallpaper backdrop with a barely-perceptible 60s GSAP drift (scale 1→1.04, y 0→-12, sine.inOut yoyo) */
const WallpaperStage = memo(function WallpaperStage() {
  const ref = useRef<HTMLDivElement>(null);
  const reduced = useRef(
    typeof window !== "undefined" &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches
  );

  useGSAP(
    () => {
      if (reduced.current || !ref.current) return;
      gsap.to(ref.current, {
        scale: 1.04,
        y: -12,
        duration: 30,
        ease: "sine.inOut",
        yoyo: true,
        repeat: -1,
      });
    },
    { scope: ref }
  );

  return (
    <div className="pointer-events-none absolute inset-0 overflow-hidden bg-stage" aria-hidden>
      <div
        ref={ref}
        className="absolute inset-[-4%] bg-cover bg-center will-change-transform"
        style={{ backgroundImage: "url(/wallpaper-desktop.jpg)" }}
      />
    </div>
  );
});

/** AppShell: faux desktop stage + MenuBar + content slot (nested-route pattern, renders <Outlet/>) */
export default function Layout() {
  return (
    <div className="relative h-[100dvh] overflow-hidden bg-stage">
      <WallpaperStage />
      <Navbar />
      {/* content slot sits below the fixed 28px MenuBar */}
      <main className="relative z-10 h-[calc(100dvh-28px)] pt-7">
        <Outlet />
      </main>
    </div>
  );
}
