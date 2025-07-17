import { NativeModule, registerWebModule } from "expo";

import {
  AuthorizeResult,
  ChangeEventPayload,
  GetHealthDataOptions,
  GetHealthDataResult,
} from "./ExpoHealthkitModule.types";

type ExpoHealthkitModuleEvents = {
  onChange: (params: ChangeEventPayload) => void;
};

class ExpoHealthkitModule extends NativeModule<ExpoHealthkitModuleEvents> {
  PI = Math.PI;
  async setValueAsync(value: string): Promise<void> {
    this.emit("onChange", { value });
  }
  hello() {
    return "Hello world! 👋";
  }

  async authorizeHealthKit(): Promise<AuthorizeResult> {
    return {
      success: false,
      granted: [],
      denied: [],
      error: "Health data is not available on web platform.",
    };
  }

  async getHealthData(options: GetHealthDataOptions): Promise<GetHealthDataResult> {
    return {
      success: false,
      data: [],
      error: {
        code: "unsupported_platform",
        message: "Health data is not available on web platform.",
      },
    };
  }
}

export default registerWebModule(ExpoHealthkitModule, "ExpoHealthkitModule");
