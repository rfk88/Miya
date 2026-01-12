import schemaJson from "./schema.v1.json" with { type: "json" };
import type { AgeGroup, PillarDefinition, ScoringSchema, VitalityPillar } from "./types.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function nearlyEqual(a: number, b: number, eps = 1e-6): boolean {
  return Math.abs(a - b) <= eps;
}

function sum(xs: number[]): number {
  return xs.reduce((acc, x) => acc + x, 0);
}

function uniq<T>(xs: T[]): T[] {
  return Array.from(new Set(xs));
}

function isFiniteNumber(x: unknown): x is number {
  return typeof x === "number" && Number.isFinite(x);
}

function validateMetricRange(range: any, ctx: string) {
  const fields = [
    "optimalMin",
    "optimalMax",
    "acceptableLowMin",
    "acceptableLowMax",
    "acceptableHighMin",
    "acceptableHighMax",
    "poorLowMax",
    "poorHighMin",
  ];
  for (const f of fields) {
    assert(isFiniteNumber(range?.[f]), `${ctx}: missing/invalid ${f}`);
  }
  assert(range.optimalMin <= range.optimalMax, `${ctx}: optimalMin must be <= optimalMax`);
  // These mirror the Swift debug validator expectations.
  assert(range.acceptableLowMax <= range.optimalMin, `${ctx}: acceptableLowMax must connect to optimalMin`);
  assert(range.acceptableHighMin >= range.optimalMax, `${ctx}: acceptableHighMin must connect to optimalMax`);
  assert(range.poorLowMax <= range.acceptableLowMin, `${ctx}: poorLowMax must be <= acceptableLowMin`);
  assert(range.poorHighMin >= range.acceptableHighMax, `${ctx}: poorHighMin must be >= acceptableHighMax`);
}

function validateSchema(schema: ScoringSchema): void {
  assert(typeof schema.schemaVersion === "string" && schema.schemaVersion.length > 0, "schemaVersion missing");

  const ageGroups = schema.ageGroups;
  assert(Array.isArray(ageGroups) && ageGroups.length > 0, "ageGroups missing");
  assert(uniq(ageGroups).length === ageGroups.length, "ageGroups must be unique");

  assert(Array.isArray(schema.pillars) && schema.pillars.length > 0, "pillars missing");

  const pillarIds = schema.pillars.map((p) => p.id);
  assert(uniq(pillarIds).length === pillarIds.length, "pillar IDs must be unique");

  // Pillar weights sum to ~1.0
  const pillarWeightSum = sum(schema.pillars.map((p) => p.weightInVitality));
  assert(nearlyEqual(pillarWeightSum, 1.0, 1e-3), `pillar weights must sum to 1.0, got ${pillarWeightSum}`);

  for (const pillar of schema.pillars) {
    assert(pillar.subMetrics?.length > 0, `pillar ${pillar.id}: no subMetrics`);

    const subIds = pillar.subMetrics.map((s) => s.id);
    assert(uniq(subIds).length === subIds.length, `pillar ${pillar.id}: subMetric IDs must be unique`);

    const wSum = sum(pillar.subMetrics.map((s) => s.weightWithinPillar));
    assert(nearlyEqual(wSum, 1.0, 1e-3), `pillar ${pillar.id}: subMetric weights must sum to 1.0, got ${wSum}`);

    for (const sm of pillar.subMetrics) {
      for (const ag of ageGroups) {
        const r = (sm.ageSpecificBenchmarks as any)?.[ag];
        assert(r != null, `pillar ${pillar.id} subMetric ${sm.id}: missing benchmarks for ageGroup ${ag}`);
        validateMetricRange(r, `pillar ${pillar.id} subMetric ${sm.id} ageGroup ${ag}`);
      }
    }
  }
}

// Validate at module load so the webhook fails loudly if schema is broken.
export const scoringSchema: ScoringSchema = schemaJson as unknown as ScoringSchema;
validateSchema(scoringSchema);

export function pillarDefinition(pillar: VitalityPillar): PillarDefinition {
  const def = scoringSchema.pillars.find((p) => p.id === pillar);
  assert(def, `missing pillar definition: ${pillar}`);
  return def;
}

export function ageGroupFromAge(age: number): AgeGroup {
  if (age < 40) return "young";
  if (age < 60) return "middle";
  if (age < 75) return "senior";
  return "elderly";
}


