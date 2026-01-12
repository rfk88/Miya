import type { AlertLevel } from "./types.ts";

export function levelForConsecutiveTrueDays(days: number): AlertLevel {
  if (days >= 21) return 21;
  if (days >= 14) return 14;
  if (days >= 7) return 7;
  return 3;
}

export type AlertSeverity = "watch" | "attention" | "critical";

export function severityForLevel(level: AlertLevel | number): AlertSeverity {
  const v = Number(level);
  if (v <= 6) return "watch";
  if (v <= 13) return "attention";
  return "critical";
}

export function shouldEnqueueNotification(params: {
  shadowMode: boolean;
  newLevel: AlertLevel;
  lastNotifiedLevel: number | null;
}): boolean {
  const { shadowMode, newLevel, lastNotifiedLevel } = params;
  if (shadowMode) return false;
  if (lastNotifiedLevel == null) return true;
  return newLevel > lastNotifiedLevel;
}

