import fixturesJson from "./fixtures.v1.json" with { type: "json" };
import { scoreIfPossible } from "./score.ts";
import type { VitalityPillar, VitalitySnapshot } from "./types.ts";

type FixtureInput = {
  age: number;
  sleepDurationHours?: number;
  restorativeSleepPercent?: number;
  sleepEfficiencyPercent?: number;
  awakePercent?: number;
  movementMinutes?: number;
  steps?: number;
  activeCalories?: number;
  hrvMs?: number;
  hrvType?: string;
  restingHeartRate?: number;
  breathingRate?: number;
};

type FixtureExpected = {
  totalScore: number;
  sleep: number;
  movement: number;
  stress: number;
};

type Fixture = {
  id: string;
  input: FixtureInput;
  expected?: FixtureExpected;
};

type FixtureFile = {
  schemaVersion: string;
  generatedAt: string;
  fixtures: Fixture[];
};

function pillar(snapshot: VitalitySnapshot, p: VitalityPillar): number {
  return snapshot.pillarScores.find((x) => x.pillar === p)?.score ?? 0;
}

Deno.test("TS scorer matches Swift golden fixtures (v1)", () => {
  const file = fixturesJson as unknown as FixtureFile;
  if (!file.fixtures?.length) throw new Error("No fixtures loaded");

  for (const fx of file.fixtures) {
    const snap = scoreIfPossible({
      age: fx.input.age,
      sleepDurationHours: fx.input.sleepDurationHours ?? null,
      restorativeSleepPercent: fx.input.restorativeSleepPercent ?? null,
      sleepEfficiencyPercent: fx.input.sleepEfficiencyPercent ?? null,
      awakePercent: fx.input.awakePercent ?? null,
      movementMinutes: fx.input.movementMinutes ?? null,
      steps: fx.input.steps ?? null,
      activeCalories: fx.input.activeCalories ?? null,
      hrvMs: fx.input.hrvMs ?? null,
      hrvType: fx.input.hrvType ?? null,
      restingHeartRate: fx.input.restingHeartRate ?? null,
      breathingRate: fx.input.breathingRate ?? null,
    });

    if (!fx.expected) {
      if (snap !== null) {
        throw new Error(`fixture ${fx.id}: expected null but got score=${snap.totalScore}`);
      }
      continue;
    }

    if (snap === null) {
      throw new Error(`fixture ${fx.id}: expected score but got null`);
    }

    const got = {
      totalScore: snap.totalScore,
      sleep: pillar(snap, "sleep"),
      movement: pillar(snap, "movement"),
      stress: pillar(snap, "stress"),
    };

    const exp = fx.expected;
    if (
      got.totalScore !== exp.totalScore ||
      got.sleep !== exp.sleep ||
      got.movement !== exp.movement ||
      got.stress !== exp.stress
    ) {
      throw new Error(
        `fixture ${fx.id}: mismatch\nexpected=${JSON.stringify(exp)}\n     got=${JSON.stringify(got)}`,
      );
    }
  }
});


