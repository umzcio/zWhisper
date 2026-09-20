import { memo, useEffect, useRef } from "react";
import { motion, useSpring, useTransform } from "framer-motion";

interface WaveformStripProps {
  /** pre-computed bar heights 0..1 */
  bars: number[];
  /** 0..1 played progress */
  progress: number;
  /** seek to ratio 0..1 */
  onSeek: (ratio: number) => void;
}

/**
 * Static rendered waveform of a recording: blue→purple gradient bars,
 * played portion full opacity, unplayed at 30%. Click anywhere to seek;
 * the white playhead springs to position (stiffness 600, damping 40).
 */
const WaveformStrip = memo(function WaveformStrip({ bars, progress, onSeek }: WaveformStripProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const wrapRef = useRef<HTMLDivElement>(null);
  const playhead = useSpring(0, { stiffness: 600, damping: 40 });
  const playheadLeft = useTransform(playhead, (v) => `${Math.max(0, Math.min(1, v)) * 100}%`);

  useEffect(() => {
    playhead.set(progress);
  }, [progress, playhead]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);

    const draw = () => {
      const rect = canvas.getBoundingClientRect();
      const width = rect.width;
      const height = rect.height;
      if (width === 0 || height === 0) return;
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, width, height);

      const n = bars.length;
      const gap = 3;
      const barW = Math.max(2, (width - (n - 1) * gap) / n);
      const playX = progress * width;
      const grad = ctx.createLinearGradient(0, 0, width, 0);
      grad.addColorStop(0, "#0A84FF");
      grad.addColorStop(1, "#BF5AF2");

      for (let i = 0; i < n; i++) {
        const x = i * (barW + gap);
        const h = Math.max(2, bars[i] * (height - 6));
        const y = (height - h) / 2;
        ctx.globalAlpha = x + barW / 2 <= playX ? 1 : 0.3;
        ctx.fillStyle = grad;
        ctx.beginPath();
        ctx.roundRect(x, y, barW, h, Math.min(2, barW / 2));
        ctx.fill();
      }
      ctx.globalAlpha = 1;
    };

    draw();
    const ro = new ResizeObserver(draw);
    ro.observe(canvas);
    return () => ro.disconnect();
  }, [bars, progress]);

  const seekFromPointer = (e: React.PointerEvent) => {
    const rect = wrapRef.current?.getBoundingClientRect();
    if (!rect || rect.width === 0) return;
    const ratio = (e.clientX - rect.left) / rect.width;
    onSeek(Math.max(0, Math.min(1, ratio)));
  };

  return (
    <div
      ref={wrapRef}
      className="relative h-20 w-full cursor-pointer select-none rounded-lg bg-surface-2/40 hairline"
      onPointerDown={seekFromPointer}
      role="slider"
      aria-label="Seek"
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={Math.round(progress * 100)}
      tabIndex={0}
    >
      <canvas ref={canvasRef} style={{ width: "100%", height: "100%", display: "block" }} />
      {/* playhead: 1px white line + handle */}
      <motion.div
        className="pointer-events-none absolute top-0 bottom-0 w-px bg-white/90"
        style={{ left: playheadLeft }}
      >
        <span className="absolute -top-0.5 left-1/2 h-2 w-2 -translate-x-1/2 rounded-full bg-white shadow" />
      </motion.div>
    </div>
  );
});

export default WaveformStrip;
