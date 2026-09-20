import {
  Mail,
  MessageCircle,
  Hash,
  StickyNote,
  Users,
  Mic,
  PenLine,
  Sparkles,
  LifeBuoy,
  Zap,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import type { Mode } from "@/lib/modes";

/** Page-local mode library entry (built-ins seeded from src/lib/modes + custom modes) */
export interface LibraryMode {
  id: string;
  name: string;
  /** key into MODE_ICON_MAP */
  icon: string;
  color: string;
  shortcut: string; // ⌘1…⌘9
  description: string;
  builtIn: boolean;
  /** context-aware ("Super") — reads selected text / clipboard */
  readSelected: boolean;
  readClipboard: boolean;
  instructions: string;
  /** mock engine script + processed result for the live preview */
  script: string;
  processed: string;
  /** maps to a store Mode id when built-in (for active-mode highlight) */
  storeId?: Mode["id"];
}

export interface ActivationRule {
  id: string;
  app: string; // Mail | Slack | Notes | Safari
  /** only for Safari */
  domain: string;
}

export const RULE_APPS = ["Mail", "Slack", "Notes", "Safari"] as const;

export const MODE_ICON_MAP: Record<string, LucideIcon> = {
  Mail,
  MessageCircle,
  Hash,
  StickyNote,
  Users,
  Mic,
  PenLine,
  Sparkles,
  LifeBuoy,
  Zap,
};

/** The 8 glyphs offered in the editor's icon picker */
export const ICON_PICKER_OPTIONS = [
  "Mail",
  "MessageCircle",
  "Hash",
  "StickyNote",
  "Users",
  "Mic",
  "PenLine",
  "Sparkles",
] as const;

export const COLOR_SWATCHES = [
  "#0A84FF",
  "#30D158",
  "#FF9F0A",
  "#BF5AF2",
  "#64D2FF",
  "#FF453A",
] as const;

export const INSTRUCTIONS_PLACEHOLDER =
  "Rewrite the transcription as a professional email. Keep it under 120 words. Sign off with my name.";

/** Built-in cards (6) per modes.md, seeded from src/lib/modes.ts */
export const BUILT_IN_MODES: LibraryMode[] = [
  {
    id: "voice-transcription",
    storeId: "voice-note",
    name: "Voice Transcription",
    icon: "Mic",
    color: "#64D2FF",
    shortcut: "⌘5",
    description: "Pure transcript, no AI processing",
    builtIn: true,
    readSelected: false,
    readClipboard: false,
    instructions: "",
    script:
      "um so i was thinking about the launch and like we should probably get the blog post drafted before thursday and, yeah, also remind design about the hero image",
    processed:
      "um so i was thinking about the launch and like we should probably get the blog post drafted before thursday and, yeah, also remind design about the hero image",
  },
  {
    id: "email",
    storeId: "email",
    name: "Email",
    icon: "Mail",
    color: "#0A84FF",
    shortcut: "⌘1",
    description: "Professional emails with greeting and sign-off",
    builtIn: true,
    readSelected: false,
    readClipboard: false,
    instructions:
      "Rewrite the transcription as a professional email. Keep it under 120 words. Sign off with my name.",
    script:
      "Hi Sarah, thanks for sending over the revised mockups. I've reviewed the onboarding flow and left a few comments on frames twelve through fifteen. Could we sync Thursday afternoon to finalize before the stakeholder review?",
    processed:
      "Hi Sarah,\n\nThanks for sending over the revised mockups. I've reviewed the onboarding flow and left a few comments on frames twelve through fifteen.\n\nCould we sync Thursday afternoon to finalize everything before the stakeholder review?\n\nBest,\nAlex",
  },
  {
    id: "message",
    storeId: "message",
    name: "Message",
    icon: "MessageCircle",
    color: "#30D158",
    shortcut: "⌘2",
    description: "Casual chat tone, contractions kept",
    builtIn: true,
    readSelected: false,
    readClipboard: false,
    instructions:
      "Keep it casual and short. Fix grammar lightly but preserve tone. Emoji allowed.",
    script:
      "hey! running about ten minutes late, grabbing coffee on the way — order me the usual if you get there first",
    processed:
      "hey! running ~10 min late, grabbing coffee on the way ☕ order me the usual if you get there first",
  },
  {
    id: "note",
    storeId: "note",
    name: "Note",
    icon: "StickyNote",
    color: "#FF9F0A",
    shortcut: "⌘3",
    description: "Structured notes with bullets",
    builtIn: true,
    readSelected: false,
    readClipboard: false,
    instructions:
      "Turn the transcription into a structured note. Use a short title and bullet points.",
    script:
      "Remember to update the pricing page copy before Friday's launch. The annual plan discount messaging needs legal sign-off, and the comparison table still shows the old tier names.",
    processed:
      "Pricing page — before Friday's launch:\n• Update pricing page copy\n• Get legal sign-off on annual plan discount messaging\n• Fix comparison table — still shows old tier names",
  },
  {
    id: "meeting",
    storeId: "meeting",
    name: "Meeting",
    icon: "Users",
    color: "#BF5AF2",
    shortcut: "⌘4",
    description: "Action items with owners and due dates",
    builtIn: true,
    readSelected: true,
    readClipboard: false,
    instructions:
      "Extract action items. Assign owners and due dates where mentioned. Format as a list.",
    script:
      "Action items from today's sync: Alex owns the API migration timeline, Priya drafts the migration comms by Wednesday, and we're moving the retro to accommodate the design review.",
    processed:
      "Action Items — Sync\n\n• Alex — owns the API migration timeline\n• Priya — drafts the migration comms (due Wednesday)\n• Team — retro moved to accommodate the design review",
  },
  {
    id: "write-for-me",
    storeId: "write-for-me",
    name: "Write for me",
    icon: "PenLine",
    color: "#FF453A",
    shortcut: "⌘6",
    description: "Drafts text from a short prompt",
    builtIn: true,
    readSelected: false,
    readClipboard: false,
    instructions:
      "Write the text for me based on my prompt. Match the requested tone and length.",
    script: "Follow-up about the stakeholder review — short and friendly.",
    processed:
      "Just following up on our stakeholder review — I'd love to hear any final thoughts before we lock the scope. Happy to hop on a quick call if that's easier. Thanks!",
  },
];

/** Pre-seeded custom modes */
export const CUSTOM_MODES: LibraryMode[] = [
  {
    id: "slack-update",
    name: "Slack Update",
    icon: "Hash",
    color: "#30D158",
    shortcut: "⌘7",
    description: "Casual standup format for team channels",
    builtIn: false,
    readSelected: false,
    readClipboard: false,
    instructions:
      "Format as a casual standup update: Yesterday / Today / Blockers. Keep it breezy, use channel-friendly shorthand.",
    script:
      "so yesterday I wrapped the onboarding audit and today I'm pairing with Priya on the migration plan, no blockers really except waiting on legal for the pricing copy",
    processed:
      ":sunrise: Yesterday — wrapped the onboarding audit\n:dart: Today — pairing w/ Priya on the migration plan\n:no_entry: Blockers — pricing copy still w/ legal",
  },
  {
    id: "support-reply",
    name: "Support Reply",
    icon: "LifeBuoy",
    color: "#BF5AF2",
    shortcut: "⌘8",
    description: "Empathetic tone, includes ticket macro",
    builtIn: false,
    readSelected: true,
    readClipboard: true,
    instructions:
      "Rewrite as an empathetic support reply. Acknowledge the issue, give the fix, and append the ticket macro.",
    script:
      "tell the customer we're sorry the export failed again, the fix shipped in 12.4 and they should update, then reference the usual macro",
    processed:
      "Hi there — really sorry the export failed again. The fix shipped in v12.4, so updating should resolve it right away.\n\n[macro: export-issue-v12.4 · ref #4821]",
  },
];

export function seedLibrary(): LibraryMode[] {
  return [...BUILT_IN_MODES, ...CUSTOM_MODES].map((m) => ({ ...m }));
}

/** Next free ⌘ shortcut (⌘1–⌘9) across the library */
export function nextShortcut(modes: LibraryMode[]): string {
  for (let i = 1; i <= 9; i++) {
    const s = `⌘${i}`;
    if (!modes.some((m) => m.shortcut === s)) return s;
  }
  return "⌘9";
}

/** Adapt a LibraryMode to the shared Mode shape consumed by the mock engine */
export function toEngineMode(m: LibraryMode): Mode {
  const libIcons = ["Mail", "MessageCircle", "StickyNote", "Users", "Mic", "PenLine", "Sparkles"];
  return {
    id: (m.storeId ?? "super") as Mode["id"],
    name: m.name,
    icon: (libIcons.includes(m.icon) ? m.icon : "Sparkles") as Mode["icon"],
    color: m.color,
    shortcut: m.shortcut,
    script: m.script,
    processed: m.processed,
  };
}

/** Generic sample used for brand-new modes in the live preview */
export const NEW_MODE_SAMPLE = {
  script:
    "um okay so the deploy is green and the metrics look fine, I'll send the summary right after lunch",
  processed:
    "Deploy is green and metrics look healthy. Summary goes out right after lunch.",
};
