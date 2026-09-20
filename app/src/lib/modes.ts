export type ModeId =
  | "email"
  | "message"
  | "note"
  | "meeting"
  | "voice-note"
  | "write-for-me"
  | "super";

export interface Mode {
  id: ModeId;
  name: string;
  /** Lucide icon name resolved by components */
  icon: "Mail" | "MessageCircle" | "StickyNote" | "Users" | "Mic" | "PenLine" | "Sparkles";
  color: string;
  shortcut: string; // ⌘1…⌘7
  /** Raw scripted phrase spoken on the teleprompter */
  script: string;
  /** Post-processed result that gets auto-pasted */
  processed: string;
  /** For Write for me: topic chips */
  topicChips?: string[];
}

export const MODES: Mode[] = [
  {
    id: "email",
    name: "Email",
    icon: "Mail",
    color: "#0A84FF",
    shortcut: "⌘1",
    script:
      "Hi Sarah, thanks for sending over the revised mockups. I've reviewed the onboarding flow and left a few comments on frames twelve through fifteen. Could we sync Thursday afternoon to finalize before the stakeholder review?",
    processed:
      "Hi Sarah,\n\nThanks for sending over the revised mockups. I've reviewed the onboarding flow and left a few comments on frames twelve through fifteen.\n\nCould we sync Thursday afternoon to finalize everything before the stakeholder review?\n\nBest,\nAlex",
  },
  {
    id: "message",
    name: "Message",
    icon: "MessageCircle",
    color: "#30D158",
    shortcut: "⌘2",
    script:
      "hey! running about ten minutes late, grabbing coffee on the way — order me the usual if you get there first",
    processed:
      "hey! running ~10 min late, grabbing coffee on the way ☕ order me the usual if you get there first",
  },
  {
    id: "note",
    name: "Note",
    icon: "StickyNote",
    color: "#FF9F0A",
    shortcut: "⌘3",
    script:
      "Remember to update the pricing page copy before Friday's launch. The annual plan discount messaging needs legal sign-off, and the comparison table still shows the old tier names.",
    processed:
      "Pricing page — before Friday's launch:\n• Update pricing page copy\n• Get legal sign-off on annual plan discount messaging\n• Fix comparison table — still shows old tier names",
  },
  {
    id: "meeting",
    name: "Meeting",
    icon: "Users",
    color: "#BF5AF2",
    shortcut: "⌘4",
    script:
      "Action items from today's sync: Alex owns the API migration timeline, Priya drafts the migration comms by Wednesday, and we're moving the retro to accommodate the design review.",
    processed:
      "Action Items — Sync\n\n• Alex — owns the API migration timeline\n• Priya — drafts the migration comms (due Wednesday)\n• Team — retro moved to accommodate the design review",
  },
  {
    id: "voice-note",
    name: "Voice Note",
    icon: "Mic",
    color: "#64D2FF",
    shortcut: "⌘5",
    script:
      "um so i was thinking about the launch and like we should probably get the blog post drafted before thursday and, yeah, also remind design about the hero image",
    processed:
      "um so i was thinking about the launch and like we should probably get the blog post drafted before thursday and, yeah, also remind design about the hero image",
  },
  {
    id: "write-for-me",
    name: "Write for me",
    icon: "PenLine",
    color: "#FF453A",
    shortcut: "⌘6",
    script:
      "Follow-up about the stakeholder review — short and friendly.",
    processed:
      "Just following up on our stakeholder review — I'd love to hear any final thoughts before we lock the scope. Happy to hop on a quick call if that's easier. Thanks!",
    topicChips: ["Follow-up", "Apology", "Intro"],
  },
  {
    id: "super",
    name: "Super Mode",
    icon: "Sparkles",
    color: "#BF5AF2",
    shortcut: "⌘7",
    script:
      "Summarize the note I'm working on and add next steps at the bottom.",
    processed:
      "Summary: Project sync covered onboarding flow feedback and launch readiness.\n\nNext steps:\n• Review frames 12–15 comments\n• Confirm Thursday sync with Sarah\n• Circulate stakeholder-review agenda",
  },
];

export const DEFAULT_MODE: Mode = MODES[0];
