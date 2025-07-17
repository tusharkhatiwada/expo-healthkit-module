// Reexport the native module. On web, it will be resolved to ExpoHealthkitModule.web.ts
// and on native platforms to ExpoHealthkitModule.ts

import { Platform } from "react-native";
import NativeModule, {
  AuthorizeResult,
  BackgroundSyncOptions,
  BackgroundSyncResult,
  BackgroundSyncStatus,
  GetHealthDataOptions,
  GetHealthDataResult,
  HealthDataError,
  HealthDataType,
} from "./src/ExpoHealthkitModule";

export { default } from "./src/ExpoHealthkitModule";
export * from "./src/ExpoHealthkitModule.types";
export { default as ExpoHealthkitModuleView } from "./src/ExpoHealthkitModuleView";

// Cross-platform identifier mapping with type safety
const IDENTIFIER_MAPPING: Record<string, { ios: HealthDataType; android: string }> = {
  stepCount: {
    ios: "HKQuantityTypeIdentifierStepCount",
    android: "Steps",
  },
  heartRate: {
    ios: "HKQuantityTypeIdentifierHeartRate",
    android: "HeartRate",
  },
  activeEnergyBurned: {
    ios: "HKQuantityTypeIdentifierActiveEnergyBurned",
    android: "ActiveCaloriesBurned",
  },
  distanceWalkingRunning: {
    ios: "HKQuantityTypeIdentifierDistanceWalkingRunning",
    android: "Distance",
  },
  flightsClimbed: {
    ios: "HKQuantityTypeIdentifierFlightsClimbed",
    android: "FloorsClimbed",
  },
  restingHeartRate: {
    ios: "HKQuantityTypeIdentifierRestingHeartRate",
    android: "RestingHeartRate",
  },
  respiratoryRate: {
    ios: "HKQuantityTypeIdentifierRespiratoryRate",
    android: "RespiratoryRate",
  },
  vo2Max: {
    ios: "HKQuantityTypeIdentifierVO2Max",
    android: "Vo2Max",
  },
  sleepAnalysis: {
    ios: "HKCategoryTypeIdentifierSleepAnalysis",
    android: "SleepSession",
  },
  workout: {
    ios: "HKWorkoutTypeIdentifier",
    android: "ExerciseSession",
  },
};

// Enhanced error handling with typed errors
function createHealthDataError(
  code: HealthDataError["code"],
  message: string,
): HealthDataError {
  return { code, message };
}

function createUnsupportedPlatformError(): GetHealthDataResult {
  return {
    success: false,
    data: [],
    error: createHealthDataError(
      "permission_denied",
      "Health data is only available on iOS and Android.",
    ),
  };
}

function createExceptionError(error: unknown): GetHealthDataResult {
  const message =
    error instanceof Error
      ? error.message
      : "An unexpected error occurred while fetching health data.";
  return {
    success: false,
    data: [],
    error: createHealthDataError("exception", message),
  };
}

// Core API functions with improved error handling and type safety
export async function authorizeHealthKit(): Promise<AuthorizeResult> {
  if (Platform.OS === "ios") {
    return NativeModule.authorizeHealthKit();
  } else if (Platform.OS === "android") {
    return NativeModule.authorizeHealthKit();
  } else {
    return {
      success: false,
      granted: [],
      denied: [],
      error: "Health data is only available on iOS and Android.",
    };
  }
}

export async function getHealthData(
  options: GetHealthDataOptions,
): Promise<GetHealthDataResult> {
  try {
    // Validate required parameters
    if (!options.identifier || !options.startDate || !options.endDate) {
      return {
        success: false,
        data: [],
        error: createHealthDataError(
          "missing_arguments",
          "Missing required options: identifier, startDate, endDate.",
        ),
      };
    }

    // Validate date format (basic ISO 8601 check)
    const dateRegex = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z?$/;
    if (!dateRegex.test(options.startDate) || !dateRegex.test(options.endDate)) {
      return {
        success: false,
        data: [],
        error: createHealthDataError(
          "invalid_date",
          "Dates must be in ISO 8601 format (YYYY-MM-DDTHH:mm:ss.sssZ)",
        ),
      };
    }

    if (Platform.OS === "ios") {
      // Use iOS identifier directly or map from cross-platform identifier
      const identifier = options.identifier.startsWith("HK")
        ? options.identifier
        : IDENTIFIER_MAPPING[options.identifier]?.ios || options.identifier;

      console.log("===GETTING HEALTH DATA FROM MODULE OPTIONS===", options);

      console.log("🟦 [JS] About to call NativeModule.getHealthData");
      console.time("🟦 [JS] NativeModule.getHealthData");

      // Filter out undefined values to prevent conversion errors
      const healthDataOptions: any = {
        identifier,
        startDate: options.startDate,
        endDate: options.endDate,
      };

      // Only add optional fields if they have values
      if (options.aggregation !== undefined) {
        healthDataOptions.aggregation = options.aggregation;
      }
      if (options.limit !== undefined) {
        healthDataOptions.limit = options.limit;
      }
      if (options.ascending !== undefined) {
        healthDataOptions.ascending = options.ascending;
      }

      const res = await NativeModule.getHealthData(healthDataOptions);

      console.timeEnd("🟦 [JS] NativeModule.getHealthData");
      console.log("🟦 [JS] NativeModule.getHealthData completed");

      console.log("===GETTING HEALTH DATA FROM MODULE===", res);
      return res;
    } else if (Platform.OS === "android") {
      // Use Android identifier directly or map from cross-platform identifier
      const identifier = Object.values(IDENTIFIER_MAPPING).some(
        (mapping) => mapping.android === options.identifier,
      )
        ? options.identifier
        : IDENTIFIER_MAPPING[options.identifier]?.android || options.identifier;

      return NativeModule.getHealthData({
        ...options,
        identifier,
        aggregation: options.aggregation ?? "raw",
      });
    } else {
      return createUnsupportedPlatformError();
    }
  } catch (error: unknown) {
    console.error("[expo-healthkit-module] getHealthData error:", error);
    return createExceptionError(error);
  }
}

// Background Sync Methods with enhanced error handling

// CRITICAL: Register background task handler early (during app launch)
export async function registerBackgroundTaskHandler(): Promise<BackgroundSyncResult> {
  if (Platform.OS === "ios") {
    return NativeModule.registerBackgroundTaskHandler();
  } else if (Platform.OS === "android") {
    // TODO: Implement Android WorkManager registration
    return {
      success: true,
      error: undefined,
    };
  } else {
    return {
      success: false,
      error: "Background sync is only available on iOS and Android.",
    };
  }
}

export async function enableBackgroundSync(
  options: BackgroundSyncOptions,
): Promise<BackgroundSyncResult> {
  if (Platform.OS === "ios") {
    return NativeModule.enableBackgroundSync(options);
  } else if (Platform.OS === "android") {
    return NativeModule.enableBackgroundSync(options);
  } else {
    return {
      success: false,
      error: "Background sync is only available on iOS and Android.",
    };
  }
}

export async function getBackgroundSyncStatus(): Promise<BackgroundSyncStatus> {
  if (Platform.OS === "ios") {
    return NativeModule.getBackgroundSyncStatus();
  } else if (Platform.OS === "android") {
    return NativeModule.getBackgroundSyncStatus();
  } else {
    return {
      enabled: false,
      lastSync: null,
      error: "Background sync is only available on iOS and Android.",
    };
  }
}

export async function disableBackgroundSync(): Promise<BackgroundSyncResult> {
  if (Platform.OS === "ios") {
    return NativeModule.disableBackgroundSync();
  } else if (Platform.OS === "android") {
    return NativeModule.disableBackgroundSync();
  } else {
    return {
      success: false,
      error: "Background sync is only available on iOS and Android.",
    };
  }
}

// Helper function to get platform-specific identifier with type safety
export function getPlatformIdentifier(crossPlatformId: string): string {
  const mapping = IDENTIFIER_MAPPING[crossPlatformId];
  if (!mapping) return crossPlatformId;

  return Platform.OS === "ios" ? mapping.ios : mapping.android;
}

// Helper function to get all supported identifiers for current platform with type safety
export function getSupportedIdentifiers(): HealthDataType[] {
  if (Platform.OS === "ios") {
    return [
      "HKQuantityTypeIdentifierActiveEnergyBurned",
      "HKQuantityTypeIdentifierAppleExerciseTime",
      "HKQuantityTypeIdentifierAppleStandTime",
      "HKQuantityTypeIdentifierBasalEnergyBurned",
      "HKQuantityTypeIdentifierDistanceCycling",
      "HKQuantityTypeIdentifierDistanceWalkingRunning",
      "HKQuantityTypeIdentifierFlightsClimbed",
      "HKQuantityTypeIdentifierHeartRate",
      "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute",
      "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
      "HKQuantityTypeIdentifierRespiratoryRate",
      "HKQuantityTypeIdentifierRestingHeartRate",
      "HKQuantityTypeIdentifierStepCount",
      "HKQuantityTypeIdentifierVO2Max",
      "HKCategoryTypeIdentifierSleepAnalysis",
      "HKWorkoutTypeIdentifier",
    ];
  } else {
    // Return cross-platform identifiers for Android or web
    return [
      "stepCount",
      "heartRate",
      "activeEnergyBurned",
      "distanceWalkingRunning",
      "flightsClimbed",
      "restingHeartRate",
      "respiratoryRate",
      "vo2Max",
      "sleepAnalysis",
      "workout",
    ];
  }
}

// Validate health data identifier
export function isValidHealthDataIdentifier(
  identifier: string,
): identifier is HealthDataType {
  const supportedIdentifiers = getSupportedIdentifiers();
  return supportedIdentifiers.includes(identifier as HealthDataType);
}

// Type guard for checking if a result has an error
export function hasHealthDataError(
  result: GetHealthDataResult,
): result is GetHealthDataResult & { error: HealthDataError } {
  return !result.success && result.error !== undefined;
}

// Utility function to format dates for the API
export function formatDateForHealthAPI(date: Date): string {
  return date.toISOString();
}

// Utility function to create date range for common periods
export function createDateRange(
  period: "today" | "yesterday" | "week" | "month" | "year",
): { startDate: string; endDate: string } {
  const now = new Date();
  const endDate = formatDateForHealthAPI(now);

  let startDate: Date;

  switch (period) {
    case "today":
      startDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      break;
    case "yesterday":
      startDate = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
      return {
        startDate: formatDateForHealthAPI(startDate),
        endDate: formatDateForHealthAPI(
          new Date(startDate.getTime() + 24 * 60 * 60 * 1000),
        ),
      };
    case "week":
      startDate = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
      break;
    case "month":
      startDate = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
      break;
    case "year":
      startDate = new Date(now.getTime() - 365 * 24 * 60 * 60 * 1000);
      break;
    default:
      startDate = new Date(now.getTime() - 24 * 60 * 60 * 1000); // Default to last 24 hours
  }

  return {
    startDate: formatDateForHealthAPI(startDate),
    endDate,
  };
}
