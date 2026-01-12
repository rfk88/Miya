export type AgeGroup = "young" | "middle" | "senior" | "elderly";

export type VitalityPillar = "sleep" | "movement" | "stress";

export type ScoringDirection = "higherIsBetter" | "lowerIsBetter" | "optimalRange";

export type VitalitySubMetric =
  | "sleepDuration"
  | "restorativeSleepPercent"
  | "sleepEfficiency"
  | "sleepFragmentationAwakePercent"
  | "movementMinutes"
  | "steps"
  | "activeCalories"
  | "hrv"
  | "restingHeartRate"
  | "breathingRate";

export type MetricRange = {
  optimalMin: number;
  optimalMax: number;
  acceptableLowMin: number;
  acceptableLowMax: number;
  acceptableHighMin: number;
  acceptableHighMax: number;
  poorLowMax: number;
  poorHighMin: number;
};

export type SubMetricDefinition = {
  id: VitalitySubMetric;
  weightWithinPillar: number; // sum per pillar = 1.0
  scoringDirection: ScoringDirection;
  description?: string;
  ageSpecificBenchmarks: Record<AgeGroup, MetricRange>;
};

export type PillarDefinition = {
  id: VitalityPillar;
  weightInVitality: number; // sum across pillars ≈ 1.0
  subMetrics: SubMetricDefinition[];
};

export type ScoringSchema = {
  schemaVersion: string;
  ageGroups: AgeGroup[];
  pillars: PillarDefinition[];
};

export type VitalityRawMetrics = {
  age: number;

  // Sleep
  sleepDurationHours?: number | null;
  restorativeSleepPercent?: number | null;
  sleepEfficiencyPercent?: number | null;
  awakePercent?: number | null;

  // Movement
  movementMinutes?: number | null;
  steps?: number | null; // integer in Swift; allow number here
  activeCalories?: number | null;

  // Stress
  hrvMs?: number | null;
  hrvType?: string | null;
  restingHeartRate?: number | null;
  breathingRate?: number | null;
};

export type SubMetricScore = {
  subMetric: VitalitySubMetric;
  rawValue: number | null;
  score: number; // 0..100
};

export type PillarScore = {
  pillar: VitalityPillar;
  score: number; // 0..100
  subMetricScores: SubMetricScore[];
};

export type VitalitySnapshot = {
  age: number;
  ageGroup: AgeGroup;
  totalScore: number; // 0..100
  pillarScores: PillarScore[];
};


