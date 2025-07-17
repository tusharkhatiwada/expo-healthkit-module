# Expo HealthKit Module

A cross-platform Expo module for integrating health data APIs with your React Native/Expo app. This module supports both Apple HealthKit (iOS) and Android Health Connect, providing unified methods for requesting health permissions and fetching health data across platforms.

## API

### `authorizeHealthKit()`

Requests HealthKit permissions for all supported identifiers.

**Returns:**

```ts
Promise<AuthorizeResult>;
```

**AuthorizeResult:**

```ts
{
  success: boolean;
  granted: string[]; // List of granted identifiers
  denied: string[];  // List of denied identifiers
  error?: string | null; // Error message if any
}
```

---

### `getHealthData(options: GetHealthDataOptions)`

Fetches health data for a given identifier and date range, with optional aggregation.

**Arguments:**

```ts
{
  identifier: string; // HealthKit identifier (e.g., 'HKQuantityTypeIdentifierStepCount')
  startDate: string;  // ISO8601 date string
  endDate: string;    // ISO8601 date string
  aggregation?: 'raw' | 'daily' | 'total'; // Optional, default: 'raw'
}
```

**Returns:**

```ts
Promise<GetHealthDataResult>;
```

**GetHealthDataResult:**

```ts
{
  success: boolean;
  data: any; // Array of samples, daily totals, or total value depending on aggregation
  error?: { code: string; message: string } | null;
}
```

---

## Supported Identifiers

### iOS (HealthKit)

- HKQuantityTypeIdentifierActiveEnergyBurned
- HKQuantityTypeIdentifierAppleExerciseTime
- HKQuantityTypeIdentifierAppleStandTime
- HKQuantityTypeIdentifierBasalEnergyBurned
- HKQuantityTypeIdentifierDistanceCycling
- HKQuantityTypeIdentifierDistanceWalkingRunning
- HKQuantityTypeIdentifierFlightsClimbed
- HKQuantityTypeIdentifierHeartRate
- HKQuantityTypeIdentifierHeartRateRecoveryOneMinute
- HKQuantityTypeIdentifierHeartRateVariabilitySDNN
- HKQuantityTypeIdentifierRespiratoryRate
- HKQuantityTypeIdentifierRestingHeartRate
- HKQuantityTypeIdentifierStepCount
- HKQuantityTypeIdentifierVO2Max
- HKCategoryTypeIdentifierSleepAnalysis
- HKWorkoutTypeIdentifier

### Android (Health Connect)

- ActiveCaloriesBurned
- BasalMetabolicRate
- BodyFat
- CyclingPedalingCadence
- Distance
- ElevationGained
- ExerciseSession
- FloorsClimbed
- HeartRate
- LeanBodyMass
- OxygenSaturation
- RespiratoryRate
- RestingHeartRate
- SleepSession
- Speed
- StepsCadence
- Steps
- TotalCaloriesBurned
- Vo2Max

### Cross-Platform Identifiers

For easier cross-platform development, you can use these unified identifiers:

- `stepCount` → iOS: HKQuantityTypeIdentifierStepCount, Android: Steps
- `heartRate` → iOS: HKQuantityTypeIdentifierHeartRate, Android: HeartRate
- `activeEnergyBurned` → iOS: HKQuantityTypeIdentifierActiveEnergyBurned, Android: ActiveCaloriesBurned
- `distanceWalkingRunning` → iOS: HKQuantityTypeIdentifierDistanceWalkingRunning, Android: Distance
- `flightsClimbed` → iOS: HKQuantityTypeIdentifierFlightsClimbed, Android: FloorsClimbed
- `restingHeartRate` → iOS: HKQuantityTypeIdentifierRestingHeartRate, Android: RestingHeartRate
- `respiratoryRate` → iOS: HKQuantityTypeIdentifierRespiratoryRate, Android: RespiratoryRate
- `vo2Max` → iOS: HKQuantityTypeIdentifierVO2Max, Android: Vo2Max
- `sleepAnalysis` → iOS: HKCategoryTypeIdentifierSleepAnalysis, Android: SleepSession
- `workout` → iOS: HKWorkoutTypeIdentifier, Android: ExerciseSession

To add new identifiers, update the identifier lists in both the Swift (iOS) and Kotlin (Android) implementations and ensure appropriate permissions are set.

---

## Getting Started

### Installation

1. **Install dependencies**:

```bash
npm install # or yarn install
```

2. **Configure EAS Build** for custom development builds (required for native modules):

```bash
# Install EAS CLI if not already installed
npm install -g @expo/eas-cli

# Configure EAS Build
eas build:configure
```

3. **Build custom development client**:

```bash
# For iOS
eas build --profile development --platform ios

# For Android
eas build --profile development --platform android
```

### Setup Requirements

#### iOS Setup

Ensure your `app.json` or `app.config.js` includes HealthKit permissions:

```json
{
  "expo": {
    "ios": {
      "infoPlist": {
        "NSHealthShareUsageDescription": "This app needs access to health data to provide personalized fitness insights.",
        "NSHealthUpdateUsageDescription": "This app needs to update health data to track your progress."
      }
    }
  }
}
```

#### Android Setup

Health Connect permissions are automatically included via the module's AndroidManifest.xml. Ensure your `app.json` targets the correct SDK version:

```json
{
  "expo": {
    "android": {
      "compileSdkVersion": 34,
      "targetSdkVersion": 34,
      "minSdkVersion": 26
    }
  }
}
```

---

## Example Usage

```ts
import {
  authorizeHealthKit,
  getHealthData,
  getPlatformIdentifier,
  getSupportedIdentifiers,
} from "expo-healthkit-module";
import { Platform } from "react-native";

// Request permissions (works on both iOS and Android)
const authResult = await authorizeHealthKit();
if (!authResult.success) {
  console.error("Authorization failed:", authResult.error);
}

// Method 1: Using cross-platform identifiers (recommended)
const stepDataResult = await getHealthData({
  identifier: "stepCount", // Automatically maps to platform-specific identifier
  startDate: "2024-01-01T00:00:00Z",
  endDate: "2024-01-31T23:59:59Z",
  aggregation: "raw",
});

// Method 2: Using platform-specific identifiers
const platformSpecificIdentifier =
  Platform.OS === "ios" ? "HKQuantityTypeIdentifierStepCount" : "Steps";

const dataResult = await getHealthData({
  identifier: platformSpecificIdentifier,
  startDate: "2024-01-01T00:00:00Z",
  endDate: "2024-01-31T23:59:59Z",
  aggregation: "raw",
});

// Method 3: Using helper function
const heartRateIdentifier = getPlatformIdentifier("heartRate");
const heartRateData = await getHealthData({
  identifier: heartRateIdentifier,
  startDate: "2024-01-01T00:00:00Z",
  endDate: "2024-01-31T23:59:59Z",
  aggregation: "raw",
});

// Get all supported identifiers for current platform
const supportedIds = getSupportedIdentifiers();
console.log("Supported identifiers:", supportedIds);

if (dataResult.success) {
  console.log("Health data:", dataResult.data);
} else {
  console.error("Data fetch error:", dataResult.error);
}
```

---

## Error Handling

All errors are returned as structured objects with a `code` and `message` property. Example error codes:

### Common Error Codes

- `invalid_date` - Invalid date format provided
- `query_error` - Error occurred during data query
- `unsupported_identifier` - Identifier not supported on current platform
- `unsupported_platform` - Platform not supported (not iOS or Android)
- `missing_arguments` - Required arguments missing

### Android-Specific Error Codes

- `health_connect_unavailable` - Health Connect app not installed
- `permission_denied` - User denied health permissions
- `health_connect_error` - General Health Connect API error

### iOS-Specific Error Codes

- Standard HealthKit error codes and messages

---

## Platform Support

- **iOS**: Uses Apple HealthKit API
- **Android**: Uses Android Health Connect API (requires Android 8.0+ / API level 26+)
- **Other platforms**: Methods return structured errors indicating unsupported platform

### Requirements

#### iOS

- iOS 15.1 or later
- HealthKit capability enabled in app
- Appropriate HealthKit usage descriptions in Info.plist

#### Android

- Android 8.0+ (API level 26+)
- Health Connect app installed on device
- Health Connect permissions declared in AndroidManifest.xml

---

## Adding New Identifiers

### iOS (HealthKit)

1. Add the identifier to the appropriate list in `ios/ExpoHealthkitModule.swift`
2. Update Info.plist with the required HealthKit usage description if needed
3. Update the `getUnit(forIdentifier:)` method for proper unit mapping

### Android (Health Connect)

1. Add the identifier and record class mapping to `recordTypeMap` in `android/src/main/java/expo/modules/healthkitmodule/ExpoHealthkitModule.kt`
2. Add the corresponding permission to `android/src/main/AndroidManifest.xml`
3. Update the `getUnitForRecord()` and `getValueForRecord()` methods
4. Add the Health Connect dependency if using a new record type

### Cross-Platform

1. Add the mapping to `IDENTIFIER_MAPPING` in `index.ts` for unified cross-platform usage
2. Update this README with the new identifier documentation
3. Test on both platforms to ensure compatibility
