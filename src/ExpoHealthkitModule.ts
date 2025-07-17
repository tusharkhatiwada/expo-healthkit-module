import { NativeModule, requireNativeModule } from "expo";

import {
  AuthorizeResult,
  BackgroundSyncOptions,
  BackgroundSyncResult,
  BackgroundSyncStatus,
  ExpoHealthkitModuleEvents,
  GetHealthDataOptions,
  GetHealthDataResult,
  HealthDataQuery,
  HealthDataType,
  TypedHealthDataResult,
} from "./ExpoHealthkitModule.types";

declare class ExpoHealthkitModule extends NativeModule<ExpoHealthkitModuleEvents> {
  PI: number;
  hello(): string;
  setValueAsync(value: string): Promise<void>;

  // Core Health Data Methods - with improved typing
  authorizeHealthKit(): Promise<AuthorizeResult>;
  getHealthData(options: GetHealthDataOptions): Promise<GetHealthDataResult>;
  testGetHealthData(options: GetHealthDataOptions): Promise<GetHealthDataResult>;

  // Background Sync Methods - with typed parameters and results
  registerBackgroundTaskHandler(): Promise<BackgroundSyncResult>;
  enableBackgroundSync(options: BackgroundSyncOptions): Promise<BackgroundSyncResult>;
  getBackgroundSyncStatus(): Promise<BackgroundSyncStatus>;
  disableBackgroundSync(): Promise<BackgroundSyncResult>;

  // Enhanced methods for type-safe queries (optional - for future use)
  getTypedHealthData<T extends HealthDataType>(
    options: HealthDataQuery & { identifier: T },
  ): Promise<TypedHealthDataResult<T>>;
}

// This call loads the native module object from the JSI.
export default requireNativeModule<ExpoHealthkitModule>("ExpoHealthkitModule");

// Re-export all types for convenience
export {
  AuthorizeResult,
  BackgroundSyncCompletePayload,
  BackgroundSyncOptions,
  BackgroundSyncResult,
  BackgroundSyncStatus,
  GetHealthDataOptions,
  GetHealthDataResult,
  HealthDataChangePayload,
  HealthDataError,
  HealthDataQuery,
  HealthDataSample,
  HealthDataType,
  HealthKitEventListener,
  HealthUnit,
  TypedHealthDataResult,
} from "./ExpoHealthkitModule.types";
