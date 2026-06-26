// Display config for the generic synced-record viewer. Each entry maps a record
// `type` (matching the iOS `SyncableRecordProvider.recordType`) to how it's
// labeled on the web. The records themselves come from
// `/api/v1/sync/records?type=<type>`; this only governs presentation.

export interface RecordTypeConfig {
  type: string;
  /** Module display name. */
  title: string;
  /** One-line description shown under the page title. */
  description: string;
  /** SF-symbol-ish emoji used as the nav/section glyph. */
  icon: string;
}

export const RECORD_TYPES: RecordTypeConfig[] = [
  { type: "task", title: "Tasks", description: "Your to-dos and weekly plan.", icon: "✓" },
  { type: "note", title: "Notes", description: "Notes and ideas captured in the app.", icon: "📝" },
  { type: "sleep", title: "Sleep", description: "Nightly sleep duration and quality.", icon: "😴" },
  { type: "mood", title: "Mood", description: "Daily mood and energy check-ins.", icon: "🙂" },
  { type: "workout", title: "Workouts", description: "Training sessions you've logged.", icon: "🏋️" },
  { type: "meal", title: "Nutrition", description: "Meals and calories logged.", icon: "🍽️" },
  { type: "medication", title: "Protocol", description: "Active medications and supplements.", icon: "💊" },
  { type: "meditation", title: "Meditation", description: "Mindfulness and breathwork sessions.", icon: "🧘" },
  { type: "stress", title: "Stress", description: "Stress levels and triggers.", icon: "🌊" },
  { type: "symptom", title: "Symptoms", description: "Symptoms you've tracked.", icon: "🌡️" },
  { type: "lab_result", title: "Labs", description: "Lab results and biomarkers.", icon: "🧪" },
  { type: "habit", title: "Habits", description: "Daily habits and streaks.", icon: "🔁" },
  { type: "quit", title: "Quit", description: "Quit programs and streaks.", icon: "🚭" },
  { type: "day_plan", title: "Day Plan", description: "AI-generated daily plans.", icon: "🗓️" },
  { type: "friend_activity", title: "Accountability", description: "Friend activity and check-ins.", icon: "👥" },
  { type: "trip", title: "Travel", description: "Trips, itineraries and budgets.", icon: "✈️" },
];

export function recordTypeConfig(type: string): RecordTypeConfig | undefined {
  return RECORD_TYPES.find((r) => r.type === type);
}
