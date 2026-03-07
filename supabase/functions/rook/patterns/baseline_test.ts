import fixturesJson from "./fixtures.patterns.v1.json" with { type: "json" };
import type { MetricType, ThresholdConfig } from "./types.ts";
import { computeBaselineForEndDate, computeBaselineWithGapDetection } from "./baseline.ts";
import { evaluateMetricOnDate } from "./evaluate.ts";
import { levelForConsecutiveTrueDays } from "./episode.ts";

type Fixture = {
  id: string;
  metric: MetricType;
  endDate: string;
  series: Array<{ date: string; value: number }>;
  expected: {
    hasBaseline: boolean;
    baselineAvg?: number;
    recentAvg?: number;
    isTrue: boolean;
    expectedLevelForConsecutiveTrueDays?: 3 | 7 | 14 | 21;
  };
};

type FixtureFile = {
  version: string;
  generatedAt: string;
  fixtures: Fixture[];
};

const thresholds = (await (async () => {
  const raw = await Deno.readTextFile(new URL("./thresholds.v1.json", import.meta.url));
  return JSON.parse(raw) as ThresholdConfig;
})()) as ThresholdConfig;

Deno.test("pattern baseline fixtures (v1)", () => {
  const file = fixturesJson as unknown as FixtureFile;
  if (!file.fixtures?.length) throw new Error("No fixtures loaded");

  for (const fx of file.fixtures) {
    const baseline = computeBaselineForEndDate(fx.series, fx.endDate);
    if ((baseline != null) !== fx.expected.hasBaseline) {
      throw new Error(`fixture ${fx.id}: hasBaseline mismatch expected=${fx.expected.hasBaseline} got=${baseline != null}`);
    }

    const evalRes = evaluateMetricOnDate(fx.metric, thresholds, fx.series, fx.endDate);
    if (evalRes.result.isTrue !== fx.expected.isTrue) {
      throw new Error(`fixture ${fx.id}: isTrue mismatch expected=${fx.expected.isTrue} got=${evalRes.result.isTrue}`);
    }

    if (fx.expected.baselineAvg != null && baseline) {
      if (Math.round(baseline.baselineAvg) !== Math.round(fx.expected.baselineAvg)) {
        throw new Error(`fixture ${fx.id}: baselineAvg mismatch expected=${fx.expected.baselineAvg} got=${baseline.baselineAvg}`);
      }
    }
    if (fx.expected.recentAvg != null && baseline) {
      if (Math.round(baseline.recentAvg) !== Math.round(fx.expected.recentAvg)) {
        throw new Error(`fixture ${fx.id}: recentAvg mismatch expected=${fx.expected.recentAvg} got=${baseline.recentAvg}`);
      }
    }

    if (fx.expected.expectedLevelForConsecutiveTrueDays != null) {
      const level = levelForConsecutiveTrueDays(fx.expected.expectedLevelForConsecutiveTrueDays);
      if (level !== fx.expected.expectedLevelForConsecutiveTrueDays) {
        throw new Error(`fixture ${fx.id}: levelForConsecutiveTrueDays mismatch expected=${fx.expected.expectedLevelForConsecutiveTrueDays} got=${level}`);
      }
    }
  }
});

Deno.test("computeBaselineWithGapDetection takes 2 args and returns baseline, recent, gap, and data sufficiency", () => {
  const allDays = [
    { date: "2025-01-01", value: 400 },
    { date: "2025-01-02", value: 410 },
    { date: "2025-01-03", value: 390 },
    { date: "2025-01-04", value: 405 },
    { date: "2025-01-05", value: 395 },
    { date: "2025-01-06", value: 408 },
    { date: "2025-01-07", value: 402 },
  ];
  const endDate = "2025-01-07";
  const result = computeBaselineWithGapDetection(allDays, endDate);
  if (!result) throw new Error("expected non-null result");
  if (typeof result.baseline !== "number" || typeof result.recent !== "number") {
    throw new Error("expected baseline and recent to be numbers");
  }
  if (typeof result.isGapDetected !== "boolean" || typeof result.hasMinimumData !== "boolean") {
    throw new Error("expected isGapDetected and hasMinimumData to be booleans");
  }
  if (typeof result.totalDays !== "number") throw new Error("expected totalDays to be number");
});

Deno.test("computeBaselineWithGapDetection: zero in recent days is not a gap", () => {
  const allDays = [
    { date: "2025-01-01", value: 400 },
    { date: "2025-01-02", value: 410 },
    { date: "2025-01-03", value: 390 },
    { date: "2025-01-04", value: 405 },
    { date: "2025-01-05", value: 395 },
    { date: "2025-01-06", value: 0 },
    { date: "2025-01-07", value: 0 },
  ];
  const endDate = "2025-01-07";
  const result = computeBaselineWithGapDetection(allDays, endDate);
  if (!result) throw new Error("expected non-null result");
  if (result.isGapDetected !== false) {
    throw new Error(`expected isGapDetected false when recent days have 0 (valid data), got ${result.isGapDetected}`);
  }
});

Deno.test("computeBaselineWithGapDetection: null in recent days is a gap", () => {
  const allDays = [
    { date: "2025-01-01", value: 400 },
    { date: "2025-01-02", value: 410 },
    { date: "2025-01-03", value: 390 },
    { date: "2025-01-04", value: 405 },
    { date: "2025-01-05", value: 395 },
    { date: "2025-01-06", value: 408 },
    { date: "2025-01-07", value: null },
  ];
  const endDate = "2025-01-07";
  const result = computeBaselineWithGapDetection(allDays, endDate);
  if (!result) throw new Error("expected non-null result");
  if (result.isGapDetected !== true) {
    throw new Error(`expected isGapDetected true when recent days have null (missing data), got ${result.isGapDetected}`);
  }
});

