export type ISODate = string; // YYYY-MM-DD

export type MetricType = "sleep_minutes" | "steps" | "hrv_ms" | "resting_hr";

export type PatternType = "drop_vs_baseline" | "rise_vs_baseline";

export type AlertLevel = 3 | 7 | 14 | 21;

export type DailyValue = { date: ISODate; value: number };

export type BaselineComputation = {
  baselineAvg: number;
  recentAvg: number;
  baselineDays: number;
  recentDays: number; // always 3 when present
  baselineStart: ISODate;
  baselineEnd: ISODate;
  recentStart: ISODate;
  recentEnd: ISODate;
};

export type PatternEvalResult = {
  isTrue: boolean;
  deviationPercent: number | null; // e.g. -0.25 for 25% drop, +0.10 for 10% rise
  reason: string;
};

export type ThresholdRule =
  | { kind: "percent_drop_at_least"; percent: number } // percent=0.25 means 25% drop
  | { kind: "percent_rise_at_least"; percent: number } // percent=0.10 means 10% rise
  | { kind: "absolute_drop_at_least"; value: number } // e.g. 45 minutes
  | { kind: "absolute_rise_at_least"; value: number }; // e.g. 5 bpm

export type ThresholdConfig = Record<
  MetricType,
  {
    patternType: PatternType;
    rules: ThresholdRule[]; // OR semantics: if any rule matches => pattern true
  }
>;

