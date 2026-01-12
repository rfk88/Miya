import type { MetricType, PatternEvalResult, ThresholdConfig, ThresholdRule } from "./types.ts";
import { computeBaselineForEndDate } from "./baseline.ts";

function applyRule(
  rule: ThresholdRule,
  baselineAvg: number,
  recentAvg: number,
): { matched: boolean; deviationPercent: number | null } {
  const diff = recentAvg - baselineAvg;
  const pct = baselineAvg === 0 ? null : diff / baselineAvg; // negative=drop, positive=rise

  switch (rule.kind) {
    case "percent_drop_at_least": {
      if (pct == null) return { matched: false, deviationPercent: null };
      const drop = -pct;
      return { matched: drop >= rule.percent, deviationPercent: pct };
    }
    case "percent_rise_at_least": {
      if (pct == null) return { matched: false, deviationPercent: null };
      return { matched: pct >= rule.percent, deviationPercent: pct };
    }
    case "absolute_drop_at_least": {
      const dropAbs = baselineAvg - recentAvg;
      return { matched: dropAbs >= rule.value, deviationPercent: pct };
    }
    case "absolute_rise_at_least": {
      const riseAbs = recentAvg - baselineAvg;
      return { matched: riseAbs >= rule.value, deviationPercent: pct };
    }
    default: {
      const _exhaustive: never = rule;
      return { matched: false, deviationPercent: null };
    }
  }
}

export function evaluateMetricOnDate(
  metric: MetricType,
  thresholds: ThresholdConfig,
  values: Array<{ date: string; value: number }>,
  endDate: string,
): { baseline: ReturnType<typeof computeBaselineForEndDate>; result: PatternEvalResult } {
  const baseline = computeBaselineForEndDate(values, endDate);
  if (!baseline) {
    return {
      baseline,
      result: { isTrue: false, deviationPercent: null, reason: "insufficient_data_for_baseline_or_recent" },
    };
  }

  const cfg = thresholds[metric];
  const matches = cfg.rules
    .map((r) => applyRule(r, baseline.baselineAvg, baseline.recentAvg))
    .filter((x) => x.matched);

  const deviationPercent = baseline.baselineAvg === 0
    ? null
    : (baseline.recentAvg - baseline.baselineAvg) / baseline.baselineAvg;

  if (matches.length > 0) {
    return {
      baseline,
      result: { isTrue: true, deviationPercent, reason: "threshold_matched" },
    };
  }

  return {
    baseline,
    result: { isTrue: false, deviationPercent, reason: "no_threshold_matched" },
  };
}

