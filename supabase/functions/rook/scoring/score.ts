import { ageGroupFromAge, scoringSchema } from "./schema.ts";
import type {
  AgeGroup,
  MetricRange,
  PillarDefinition,
  PillarScore,
  ScoringDirection,
  SubMetricDefinition,
  SubMetricScore,
  VitalityPillar,
  VitalityRawMetrics,
  VitalitySnapshot,
  VitalitySubMetric,
} from "./types.ts";

/**
 * TypeScript port of `VitalityScoringEngine` (Swift).
 * Goals:
 * - Match Swift outputs exactly (parity tests will enforce).
 * - Missing metrics do NOT penalize (weights renormalize over available submetrics/pillars).
 * - Eligibility: at least 2 pillars have >=1 available submetric (rawValue != null).
 */

export function score(raw: VitalityRawMetrics, schema: PillarDefinition[] = scoringSchema.pillars): VitalitySnapshot {
  return scoreInternal(raw, schema).snapshot;
}

export function scoreIfPossible(
  raw: VitalityRawMetrics,
  schema: PillarDefinition[] = scoringSchema.pillars,
): VitalitySnapshot | null {
  const scored = scoreInternal(raw, schema);
  const availablePillars = scored.snapshot.pillarScores.filter((p) =>
    p.subMetricScores.some((s) => s.rawValue != null)
  );
  if (availablePillars.length < 2) return null;
  return scored.snapshot;
}

function scoreInternal(
  raw: VitalityRawMetrics,
  schema: PillarDefinition[],
): { snapshot: VitalitySnapshot } {
  const ageGroup = ageGroupFromAge(raw.age);

  const pillarScores: PillarScore[] = [];
  for (const pillarDef of schema) {
    const subMetricScores: SubMetricScore[] = [];

    for (const subMetricDef of pillarDef.subMetrics) {
      const v = getRawValue(subMetricDef.id, raw);
      if (v == null) {
        subMetricScores.push({ subMetric: subMetricDef.id, rawValue: null, score: 0 });
        continue;
      }

      const range = subMetricDef.ageSpecificBenchmarks[ageGroup];
      const s = scoreValue(v, range, subMetricDef.scoringDirection);
      subMetricScores.push({ subMetric: subMetricDef.id, rawValue: v, score: s });
    }

    const pillarScore = computePillarScore(subMetricScores, pillarDef.subMetrics);
    pillarScores.push({ pillar: pillarDef.id, score: pillarScore, subMetricScores });
  }

  const totalScore = computeTotalVitality(pillarScores, schema);

  return {
    snapshot: {
      age: raw.age,
      ageGroup,
      totalScore,
      pillarScores,
    },
  };
}

function getRawValue(subMetric: VitalitySubMetric, raw: VitalityRawMetrics): number | null {
  switch (subMetric) {
    case "sleepDuration":
      return asNumOrNull(raw.sleepDurationHours);
    case "restorativeSleepPercent":
      return asNumOrNull(raw.restorativeSleepPercent);
    case "sleepEfficiency":
      return asNumOrNull(raw.sleepEfficiencyPercent);
    case "sleepFragmentationAwakePercent":
      return asNumOrNull(raw.awakePercent);
    case "movementMinutes":
      return asNumOrNull(raw.movementMinutes);
    case "steps":
      return raw.steps == null ? null : Number(raw.steps);
    case "activeCalories":
      return asNumOrNull(raw.activeCalories);
    case "hrv":
      return asNumOrNull(raw.hrvMs);
    case "restingHeartRate":
      return asNumOrNull(raw.restingHeartRate);
    case "breathingRate":
      return asNumOrNull(raw.breathingRate);
  }
}

function asNumOrNull(x: number | null | undefined): number | null {
  if (x == null) return null;
  const n = Number(x);
  return Number.isFinite(n) ? n : null;
}

function scoreValue(value: number, range: MetricRange, direction: ScoringDirection): number {
  const r = normalizedRange(range);
  switch (direction) {
    case "optimalRange":
      return scoreOptimalRange(value, r);
    case "higherIsBetter":
      return scoreHigherIsBetter(value, r);
    case "lowerIsBetter":
      return scoreLowerIsBetter(value, r);
  }
}

/**
 * Mirror Swift `normalizedRange(_:)` to prevent degenerate poor bounds causing cliffs to 0.
 */
function normalizedRange(range: MetricRange): MetricRange {
  let poorLowMax = range.poorLowMax;
  let poorHighMin = range.poorHighMin;

  if (poorLowMax >= range.acceptableLowMin) {
    const delta = range.optimalMin - range.acceptableLowMin;
    poorLowMax = range.acceptableLowMin - delta;
  }

  if (poorHighMin <= range.acceptableHighMax) {
    const delta = range.acceptableHighMax - range.optimalMax;
    poorHighMin = range.acceptableHighMax + delta;
  }

  return {
    optimalMin: range.optimalMin,
    optimalMax: range.optimalMax,
    acceptableLowMin: range.acceptableLowMin,
    acceptableLowMax: range.acceptableLowMax,
    acceptableHighMin: range.acceptableHighMin,
    acceptableHighMax: range.acceptableHighMax,
    poorLowMax,
    poorHighMin,
  };
}

// Swift: scoreOptimalRange(value:range:)
function scoreOptimalRange(value: number, range: MetricRange): number {
  // Optimal band
  if (value >= range.optimalMin && value <= range.optimalMax) {
    const progress = (value - range.optimalMin) / (range.optimalMax - range.optimalMin);
    return Math.trunc(80 + progress * 20);
  }

  // Acceptable low
  if (value >= range.acceptableLowMin && value < range.optimalMin) {
    const progress = (value - range.acceptableLowMin) / (range.optimalMin - range.acceptableLowMin);
    return Math.trunc(50 + progress * 30);
  }

  // Acceptable high
  if (value > range.optimalMax && value <= range.acceptableHighMax) {
    const progress = (value - range.optimalMax) / (range.acceptableHighMax - range.optimalMax);
    return Math.trunc(100 - progress * 20);
  }

  // Below acceptable low (poor)
  if (value < range.acceptableLowMin) {
    if (value <= range.poorLowMax) return 0;
    const progress = (value - range.poorLowMax) / (range.acceptableLowMin - range.poorLowMax);
    return Math.trunc(progress * 50);
  }

  // Above acceptable high (poor)
  if (value > range.acceptableHighMax) {
    if (value >= range.poorHighMin) return 0;
    const progress = (value - range.acceptableHighMax) / (range.poorHighMin - range.acceptableHighMax);
    return Math.trunc(80 - progress * 30);
  }

  return 0;
}

// Swift: scoreHigherIsBetter(value:range:)
function scoreHigherIsBetter(value: number, range: MetricRange): number {
  if (value >= range.optimalMax) return 100;

  if (value >= range.optimalMin && value < range.optimalMax) {
    const progress = (value - range.optimalMin) / (range.optimalMax - range.optimalMin);
    return Math.trunc(80 + progress * 20);
  }

  // Acceptable high range above optimal: cap at 100 (Swift returns 100)
  if (value > range.optimalMax && value <= range.acceptableHighMax) return 100;

  if (value >= range.acceptableLowMin && value < range.optimalMin) {
    const progress = (value - range.acceptableLowMin) / (range.optimalMin - range.acceptableLowMin);
    return Math.trunc(60 + progress * 20);
  }

  if (value < range.acceptableLowMin) {
    if (value <= range.poorLowMax) return 0;
    const progress = (value - range.poorLowMax) / (range.acceptableLowMin - range.poorLowMax);
    return Math.trunc(progress * 60);
  }

  return 0;
}

// Swift: scoreLowerIsBetter(value:range:)
function scoreLowerIsBetter(value: number, range: MetricRange): number {
  if (value <= range.optimalMin) return 100;

  if (value > range.optimalMin && value <= range.optimalMax) {
    const progress = (value - range.optimalMin) / (range.optimalMax - range.optimalMin);
    return Math.trunc(100 - progress * 20);
  }

  // Acceptable low range below optimal (rare for lower-is-better)
  if (value < range.optimalMin && value >= range.acceptableLowMin) {
    const progress = (value - range.acceptableLowMin) / (range.optimalMin - range.acceptableLowMin);
    return Math.trunc(60 + progress * 40);
  }

  if (value > range.optimalMax && value <= range.acceptableHighMax) {
    const progress = (value - range.optimalMax) / (range.acceptableHighMax - range.optimalMax);
    return Math.trunc(80 - progress * 20);
  }

  if (value > range.acceptableHighMax) {
    if (value >= range.poorHighMin) return 0;
    const progress = (value - range.acceptableHighMax) / (range.poorHighMin - range.acceptableHighMax);
    return Math.trunc(60 - progress * 60);
  }

  return 0;
}

// Swift: computePillarScore (renormalize weight over available submetrics only)
function computePillarScore(subMetricScores: SubMetricScore[], defs: SubMetricDefinition[]): number {
  let weightedSum = 0;
  let totalWeight = 0;

  for (const sms of subMetricScores) {
    const def = defs.find((d) => d.id === sms.subMetric);
    if (!def) continue;
    if (sms.rawValue == null) continue;
    weightedSum += sms.score * def.weightWithinPillar;
    totalWeight += def.weightWithinPillar;
  }

  if (totalWeight <= 0) return 0;
  return Math.round(weightedSum / totalWeight);
}

// Swift: computeTotalVitality (exclude pillars with no available submetrics)
function computeTotalVitality(pillarScores: PillarScore[], defs: PillarDefinition[]): number {
  let weightedSum = 0;
  let totalWeight = 0;

  for (const ps of pillarScores) {
    const hasAnyAvailable = ps.subMetricScores.some((s) => s.rawValue != null);
    if (!hasAnyAvailable) continue;
    const def = defs.find((d) => d.id === ps.pillar);
    if (!def) continue;
    weightedSum += ps.score * def.weightInVitality;
    totalWeight += def.weightInVitality;
  }

  if (totalWeight <= 0) return 0;
  return Math.round(weightedSum / totalWeight);
}

export function hasMinimumData(raw: VitalityRawMetrics, schema: PillarDefinition[] = scoringSchema.pillars): boolean {
  // Mirror Swift scoreIfPossible: >=2 pillars have >=1 available submetric.
  const ageGroup: AgeGroup = ageGroupFromAge(raw.age);
  let availablePillars = 0;

  for (const pillar of schema) {
    let hasAny = false;
    for (const sm of pillar.subMetrics) {
      const v = getRawValue(sm.id, raw);
      if (v != null) {
        // Access ageGroup benchmarks to ensure schema is present (and keep parity w/ Swift path).
        void sm.ageSpecificBenchmarks[ageGroup];
        hasAny = true;
        break;
      }
    }
    if (hasAny) availablePillars += 1;
    if (availablePillars >= 2) return true;
  }
  return false;
}


