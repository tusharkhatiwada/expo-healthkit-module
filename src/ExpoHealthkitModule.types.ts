import type { StyleProp, ViewStyle } from "react-native";

export type OnLoadEventPayload = {
  url: string;
};

export type ExpoHealthkitModuleEvents = {
  onChange: (params: ChangeEventPayload) => void;
  onHealthDataChange?: (params: HealthDataChangePayload) => void;
  onBackgroundSyncComplete?: (params: BackgroundSyncCompletePayload) => void;
};

export type ChangeEventPayload = {
  value: string;
};

export type HealthDataChangePayload = {
  dataType: string;
  samplesAdded: number;
  timestamp: string;
};

export type BackgroundSyncCompletePayload = {
  success: boolean;
  syncedDataTypes: string[];
  timestamp: string;
  error?: string;
};

export type ExpoHealthkitModuleViewProps = {
  url: string;
  onLoad: (event: { nativeEvent: OnLoadEventPayload }) => void;
  style?: StyleProp<ViewStyle>;
};

// Core Result Types - align with Swift Records
export interface AuthorizeResult {
  success: boolean;
  granted: string[];
  denied: string[];
  error?: string;
}

export interface HealthDataError {
  code:
    | "missing_arguments"
    | "invalid_date"
    | "internal_error"
    | "query_error"
    | "unsupported_identifier"
    | "unsupported_platform"
    | "exception"
    | "permission_denied"
    | "network_error"
    | "timeout_error";
  message: string;
}

export interface GetHealthDataOptions {
  identifier: string;
  startDate: string; // ISO 8601 format
  endDate: string; // ISO 8601 format
  aggregation?: "raw" | "hourly" | "daily" | "weekly" | "monthly";
  limit?: number;
  ascending?: boolean;
}

export interface HealthDataSample {
  type: string;
  sourceName: string;
  sourceVersion?: string;
  device?: string;
  creationDate: string;
  startDate: string;
  endDate: string;
  metadata?: Record<string, any>;
  // For Quantity samples
  unit?: string;
  value?: number;
  // For Category samples (like sleep)
  categoryValue?: string | number;
  // For Workout samples
  workoutActivityType?: string;
  duration?: number;
  durationUnit?: string;
  totalEnergyBurned?: number;
  totalEnergyBurnedUnit?: string;
  totalDistance?: number;
  totalDistanceUnit?: string;
}

export interface GetHealthDataResult {
  success: boolean;
  data: HealthDataSample[];
  error?: HealthDataError;
}

// Background Sync Types - align with Swift Records
export interface BackgroundSyncOptions {
  enabled: boolean;
  syncInterval: number; // hours
  dataTypes: string[];
  preferredSyncTime?: string; // HH:MM format
  wifiOnly?: boolean;
  minimumBatteryLevel?: number; // percentage (0-100)
}

export interface BackgroundSyncStatus {
  enabled: boolean;
  lastSync: string | null; // ISO 8601 format
  nextScheduledSync?: string | null; // ISO 8601 format
  syncedDataTypes?: string[];
  failedDataTypes?: string[];
  error?: string;
}

export interface BackgroundSyncResult {
  success: boolean;
  error?: string;
  scheduledNextSync?: string; // ISO 8601 format
}

// Health Data Type Definitions
export type HealthDataType =
  // Quantity Types
  | "HKQuantityTypeIdentifierActiveEnergyBurned"
  | "HKQuantityTypeIdentifierAppleExerciseTime"
  | "HKQuantityTypeIdentifierAppleStandTime"
  | "HKQuantityTypeIdentifierBasalEnergyBurned"
  | "HKQuantityTypeIdentifierDistanceCycling"
  | "HKQuantityTypeIdentifierDistanceWalkingRunning"
  | "HKQuantityTypeIdentifierFlightsClimbed"
  | "HKQuantityTypeIdentifierHeartRate"
  | "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute"
  | "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
  | "HKQuantityTypeIdentifierRespiratoryRate"
  | "HKQuantityTypeIdentifierRestingHeartRate"
  | "HKQuantityTypeIdentifierStepCount"
  | "HKQuantityTypeIdentifierVO2Max"
  // Category Types
  | "HKCategoryTypeIdentifierSleepAnalysis"
  // Workout Types
  | "HKWorkoutTypeIdentifier"
  // Cross-platform identifiers
  | "stepCount"
  | "heartRate"
  | "activeEnergyBurned"
  | "distanceWalkingRunning"
  | "flightsClimbed"
  | "restingHeartRate"
  | "respiratoryRate"
  | "vo2Max"
  | "sleepAnalysis"
  | "workout";

// Unit Types
export type HealthUnit =
  | "count"
  | "count/min"
  | "kcal"
  | "km"
  | "min"
  | "ms"
  | "ml/(kg*min)"
  | "s";

// Helper Types for Type Safety
export interface HealthDataQuery extends GetHealthDataOptions {
  identifier: HealthDataType;
}

export interface TypedHealthDataResult<T extends HealthDataType>
  extends Omit<GetHealthDataResult, "data"> {
  data: Array<
    HealthDataSample & {
      type: T;
    }
  >;
}

// Export utility type for event listener management
export type HealthKitEventListener<T extends keyof ExpoHealthkitModuleEvents> =
  ExpoHealthkitModuleEvents[T] extends (params: infer P) => void ? P : never;
