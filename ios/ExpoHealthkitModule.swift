import ExpoModulesCore
import HealthKit
import BackgroundTasks
import OSLog

// Global logger to avoid `self` capture issues inside @Sendable closures
private let healthkitLogger = Logger(subsystem: "ae.fithack.mobile", category: "healthkit")

// MARK: - Type Safety Notes
// We keep type definitions in TypeScript for JavaScript interface
// Swift functions return dictionaries that get automatically converted

public class ExpoHealthkitModule: Module {
  let healthStore = HKHealthStore()
  let isoFormatter = ISO8601DateFormatter() // Reusable formatter
  private let backgroundTaskIdentifier = "ae.fithack.mobile.health-sync"
  // Default sync interval (in hours). Can be overridden via JS options.
  private var syncIntervalHours: Double = 24
  private var observerQueries: [HKObserverQuery] = []
  private var backgroundSyncEnabled: Bool = false
  private var lastSyncTimestamp: String?
  private var backgroundTaskHandlerRegistered: Bool = false

  // List of supported HealthKit identifiers (extensible)
  let quantityTypeIdentifiers: [String] = [
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
    "HKQuantityTypeIdentifierVO2Max"
  ]
  let categoryTypeIdentifiers: [String] = [
    "HKCategoryTypeIdentifierSleepAnalysis"
  ]
  let workoutTypeIdentifiers: [String] = [
    "HKWorkoutTypeIdentifier"
  ]

  // Helper function to get the appropriate HKUnit for a given identifier
  private func getUnit(forIdentifier identifier: String) -> HKUnit? {
    switch identifier {
      // Energy
      case "HKQuantityTypeIdentifierActiveEnergyBurned",
           "HKQuantityTypeIdentifierBasalEnergyBurned":
        return HKUnit.kilocalorie()
      // Time
      case "HKQuantityTypeIdentifierAppleExerciseTime",
           "HKQuantityTypeIdentifierAppleStandTime":
        return HKUnit.minute()
      // Distance
      case "HKQuantityTypeIdentifierDistanceCycling",
           "HKQuantityTypeIdentifierDistanceWalkingRunning":
        return HKUnit.meterUnit(with: .kilo) // km
      // Count
      case "HKQuantityTypeIdentifierFlightsClimbed",
           "HKQuantityTypeIdentifierStepCount":
        return HKUnit.count()
      // Heart Rate related (Count / Time)
      case "HKQuantityTypeIdentifierHeartRate",
           "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute",
           "HKQuantityTypeIdentifierRestingHeartRate",
           "HKQuantityTypeIdentifierRespiratoryRate":
        return HKUnit.count().unitDivided(by: HKUnit.minute()) // count/min
      // HRV (Time)
      case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN":
        return HKUnit.secondUnit(with: .milli) // ms
      // VO2Max (Volume / Mass / Time)
      case "HKQuantityTypeIdentifierVO2Max":
         // ml/(kg*min)
        return HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: HKUnit.minute()))
      default:
        // Should not happen if identifier is in quantityTypeIdentifiers list,
        // but return nil as a fallback
        healthkitLogger.error("Unsupported quantity identifier for unit mapping: \\(identifier)")
        return nil
    }
  }

  // Helper to convert metadata dictionary
  private func formatMetadata(_ metadata: [String: Any]?) -> [String: AnyCodable]? {
    guard let metadata = metadata else { return nil }
    // Convert complex types (like HKDevice) if necessary, otherwise just wrap
    // For now, we'll just wrap existing serializable values
    var formattedMeta: [String: AnyCodable] = [:]
        for (key, value) in metadata {
            // Attempt to wrap known serializable types
             if let stringValue = value as? String {
                formattedMeta[key] = AnyCodable(stringValue)
            } else if let numberValue = value as? NSNumber { // Catches Int, Double, Bool
                formattedMeta[key] = AnyCodable(numberValue)
            } else if let dateValue = value as? Date {
                 formattedMeta[key] = AnyCodable(isoFormatter.string(from: dateValue))
             }
            // Add more type checks if specific metadata keys are known
            // to contain non-standard types that need custom serialization.
            // HKDevice requires specific handling if needed:
            // else if let deviceValue = value as? HKDevice {
            //    formattedMeta[key] = AnyCodable(["name": deviceValue.name, ...])
            // }
        }
    return formattedMeta.isEmpty ? nil : formattedMeta
  }

  // Helper to map HKCategoryValueSleepAnalysis integer values to descriptive strings
 private func mapSleepAnalysisValue(value: Int) -> String {
    switch value {
    case HKCategoryValueSleepAnalysis.inBed.rawValue: // 0
        return "HKCategoryValueSleepAnalysisInBed"
    case HKCategoryValueSleepAnalysis.awake.rawValue: // 2
        return "HKCategoryValueSleepAnalysisAwake"
    default:
        // For iOS 16+ values, we need to handle them differently
        if #available(iOS 16.0, *) {
            switch value {
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue: // 3
                return "HKCategoryValueSleepAnalysisAsleepCore"
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: // 4
                return "HKCategoryValueSleepAnalysisAsleepDeep"
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue: // 5
                return "HKCategoryValueSleepAnalysisAsleepREM"
            default:
                return "UNKNOWN_SLEEP_VALUE_\(value)"
            }
        } else {
            // On iOS < 16, handle raw values if they appear
            switch value {
            case 3:
                return "HKCategoryValueSleepAnalysisAsleepCore"
            case 4:
                return "HKCategoryValueSleepAnalysisAsleepDeep"
            case 5:
                return "HKCategoryValueSleepAnalysisAsleepREM"
            default:
                return "UNKNOWN_SLEEP_VALUE_\(value)"
            }
        }
    }
}

  // Each module class must implement the definition function. The definition consists of components
  // that describes the module's functionality and behavior.
  // See https://docs.expo.dev/modules/module-api for more details about available components.
  public func definition() -> ModuleDefinition {
    // Sets the name of the module that JavaScript code will use to refer to the module. Takes a string as an argument.
    // Can be inferred from module's class name, but it's recommended to set it explicitly for clarity.
    // The module will be accessible from `requireNativeModule('ExpoHealthkitModule')` in JavaScript.
    Name("ExpoHealthkitModule")

    // Sets constant properties on the module. Can take a dictionary or a closure that returns a dictionary.
    Constants([
      "PI": Double.pi
    ])

    // Defines event names that the module can send to JavaScript.
    Events("onChange", "onHealthDataChange", "onBackgroundSyncComplete")

    // Defines a JavaScript synchronous function that runs the native code on the JavaScript thread.
    Function("hello") {
      return "Hello world! 👋"
    }

    // Defines a JavaScript function that always returns a Promise and whose native code
    // is by default dispatched on the different thread than the JavaScript runtime runs on.
    AsyncFunction("setValueAsync") { (value: String) in
      // Send an event to JavaScript.
      self.sendEvent("onChange", [
        "value": value
      ])
    }

    // Enables the module to be used as a native view. Definition components that are accepted as part of the
    // view definition: Prop, Events.
    View(ExpoHealthkitModuleView.self) {
      // Defines a setter for the `url` prop.
      Prop("url") { (view: ExpoHealthkitModuleView, url: URL) in
        if view.webView.url != url {
          view.webView.load(URLRequest(url: url))
        }
      }

      Events("onLoad")
    }

    AsyncFunction("authorizeHealthKit") { () async -> [String: Any] in
      var toRequest: Set<HKObjectType> = []
      for id in quantityTypeIdentifiers {
        if let type = HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: id)) {
          toRequest.insert(type)
        }
      }
      for id in categoryTypeIdentifiers {
        if let type = HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: id)) {
          toRequest.insert(type)
        }
      }
      for _ in workoutTypeIdentifiers {
        toRequest.insert(HKObjectType.workoutType())
      }
      var granted: [String] = []
      var denied: [String] = []
      var errorMsg: String? = nil
      let semaphore = DispatchSemaphore(value: 0)
      healthStore.requestAuthorization(toShare: nil, read: toRequest) { success, error in
        if let error = error {
          errorMsg = error.localizedDescription
        } else if success {
          granted = toRequest.map { $0.identifier }
          denied = []
        } else {
          errorMsg = "Authorization failed for unknown reasons."
          denied = toRequest.map { $0.identifier }
          granted = []
        }
        semaphore.signal()
      }
      semaphore.wait()
      return [
        "success": errorMsg == nil,
        "granted": granted,
        "denied": denied,
        "error": errorMsg ?? NSNull()
      ]
    }

    // TEST FUNCTION - same signature as getHealthData but simpler
    AsyncFunction("testGetHealthData") { (options: [String: String]) async -> [String: Any] in
      print("🔥 [HealthKit] TEST FUNCTION CALLED!")
      healthkitLogger.debug("🔥 TEST FUNCTION CALLED!")
      return [
        "success": true,
        "data": ["test": "worked"],
        "options": options
      ]
    }

    AsyncFunction("getHealthData") { (options: [String: Any], promise: Promise) in
       // IMMEDIATE DEBUG - this should appear first
       print("🟢 [HealthKit] NATIVE METHOD CALLED - getHealthData START")
       healthkitLogger.debug("🟢 NATIVE METHOD CALLED - getHealthData START")

       do {
         // BEGIN NEW LOGS
         healthkitLogger.debug("getHealthData called with options: \(options, privacy: .public)")
         // Fallback print so logs appear even without OSLog stream
         print("[HealthKit][getHealthData] options: \(options)")
         // END NEW LOGS
                   let identifier = options["identifier"] as? String ?? ""
          let startDateString = options["startDate"] as? String ?? ""
          let endDateString = options["endDate"] as? String ?? ""

          guard !identifier.isEmpty, !startDateString.isEmpty, !endDateString.isEmpty else {
           // BEGIN NEW LOGS
           healthkitLogger.error("Missing required arguments – returning early")
           print("[HealthKit][getHealthData] ERROR: missing arguments")
           // END NEW LOGS
                       promise.resolve([
              "success": false,
              "data": [],
              "error": [
                "code": "missing_arguments",
                "message": "Missing required options: identifier, startDate, endDate."
              ]
            ])
           return
         }

         print("🟡 [HealthKit] Arguments parsed successfully")

         // BEGIN NEW LOGS
         healthkitLogger.debug("Parsed identifier: \(identifier, privacy: .public)  start: \(startDateString, privacy: .public)  end: \(endDateString, privacy: .public)")
         print("[HealthKit][getHealthData] identifier: \(identifier)  start: \(startDateString)  end: \(endDateString)")
         // END NEW LOGS
         // Aggregation is no longer supported for JSONL format
         // let aggregation = options["aggregation"]

         guard let start = isoFormatter.date(from: startDateString),
               let end = isoFormatter.date(from: endDateString) else {
                       print("🔴 [HealthKit] Date parsing failed")
                         promise.resolve([
               "success": false,
               "data": [],
               "error": [
                 "code": "invalid_date",
                 "message": "Invalid date format."
               ]
             ])
            return
         }

         print("🟡 [HealthKit] Dates parsed successfully: \(start) to \(end)")

         var result: [String: Any] = ["success": false, "data": [], "error": NSNull()]
         let semaphore = DispatchSemaphore(value: 0)

         // Common predicate for all sample types
         let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate])

         print("🟡 [HealthKit] Predicate created, checking identifier type...")

         if quantityTypeIdentifiers.contains(identifier),
            let type = HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: identifier)) {

           guard let specificUnit = getUnit(forIdentifier: identifier) else {
             // BEGIN NEW LOGS
             healthkitLogger.error("Could not determine unit for identifier: \(identifier, privacy: .public)")
             print("[HealthKit] ERROR: Could not determine unit for identifier: \(identifier)")
             // END NEW LOGS
                                                       promise.resolve([
                              "success": false,
                              "data": [],
                              "error": [
                                "code": "internal_error",
                                "message": "Could not determine unit for identifier: \(identifier)"
                              ]
                            ])
              return
           }

           // BEGIN NEW LOGS
           healthkitLogger.debug("Executing HKSampleQuery for \(identifier, privacy: .public)")
           print("[HealthKit] Executing HKSampleQuery for \(identifier)")
           print("🟡 [HealthKit] About to execute query...")
           // END NEW LOGS

           let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
             print("🟢 [HealthKit] Query completion handler called!")
             // BEGIN NEW LOGS
             healthkitLogger.debug("HKSampleQuery completed for \(identifier, privacy: .public). Samples: \(samples?.count ?? 0, privacy: .public)  Error: \(String(describing: error), privacy: .public)")
             print("[HealthKit] Query finished for \(identifier). Samples: \(samples?.count ?? 0)  Error: \(String(describing: error))")
             // END NEW LOGS
             if let error = error {
               result = [
                 "success": false,
                 "data": [],
                 "error": [
                   "code": "query_error",
                   "message": error.localizedDescription
                 ]
               ]
             } else if let samples = samples as? [HKQuantitySample] {
               let formattedSamples = samples.map { sample -> [String: Any?] in
                 return [
                   "type": sample.quantityType.identifier,
                   "sourceName": sample.sourceRevision.source.name,
                   "sourceVersion": sample.sourceRevision.version, // Optional
                   "device": sample.device?.name, // Optional
                   "creationDate": self.isoFormatter.string(from: sample.endDate ?? sample.startDate), // Use creationDate if available
                   "startDate": self.isoFormatter.string(from: sample.startDate),
                   "endDate": self.isoFormatter.string(from: sample.endDate),
                   "metadata": self.formatMetadata(sample.metadata), // Optional
                   "unit": specificUnit.unitString,
                   "value": sample.quantity.doubleValue(for: specificUnit)
                 ]
               }
               result = ["success": true, "data": formattedSamples, "error": NSNull()]
             } else {
               result = ["success": true, "data": [], "error": NSNull()] // No samples found
             }
             print("🟢 [HealthKit] About to signal semaphore")
             semaphore.signal()
           }

           print("🟡 [HealthKit] About to execute healthStore.execute(query)")
           healthStore.execute(query)
           print("🟡 [HealthKit] healthStore.execute(query) completed, waiting for semaphore...")

         } else if categoryTypeIdentifiers.contains(identifier),
                   let type = HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: identifier)) {

           print("🟡 [HealthKit] Processing category type: \(identifier)")
           let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
             print("🟢 [HealthKit] Category query completion handler called!")
             if let error = error {
                 result = [
                   "success": false,
                   "data": [],
                   "error": [
                     "code": "query_error",
                     "message": error.localizedDescription
                   ]
                 ]
             } else if let samples = samples as? [HKCategorySample] {
                 let formattedSamples = samples.map { sample -> [String: Any?] in
                   // Check if this is sleep analysis data to map the value
                   let valueToStore: Any?
                   if sample.categoryType.identifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue {
                       valueToStore = self.mapSleepAnalysisValue(value: sample.value)
                   } else {
                       valueToStore = sample.value // Store the raw integer for other category types
                   }

                   return [
                     "type": sample.categoryType.identifier,
                     "sourceName": sample.sourceRevision.source.name,
                     "sourceVersion": sample.sourceRevision.version, // Optional
                     "device": sample.device?.name, // Optional
                     "creationDate": self.isoFormatter.string(from: sample.endDate ?? sample.startDate),
                     "startDate": self.isoFormatter.string(from: sample.startDate),
                     "endDate": self.isoFormatter.string(from: sample.endDate),
                     "metadata": self.formatMetadata(sample.metadata), // Optional
                     "value": valueToStore // Use the mapped or raw value
                   ]
                 }
                 result = ["success": true, "data": formattedSamples, "error": NSNull()]
             } else {
                result = ["success": true, "data": [], "error": NSNull()] // No samples found
             }
             semaphore.signal()
           }
           healthStore.execute(query)

         } else if identifier == HKObjectType.workoutType().identifier {
           print("🟡 [HealthKit] Processing workout type")
           // Directly use the non-optional workout type for the query
           let type = HKObjectType.workoutType()
           let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
               print("🟢 [HealthKit] Workout query completion handler called!")
               if let error = error {
                   result = [
                     "success": false,
                     "data": [],
                     "error": [
                       "code": "query_error",
                       "message": error.localizedDescription
                     ]
                   ]
               } else if let samples = samples as? [HKWorkout] {
                   let formattedSamples = samples.map { sample -> [String: Any?] in
                      // Workout specific fields
                      let durationUnit = HKUnit.second() // Standard unit for duration
                      let totalEnergyBurnedUnit = HKUnit.kilocalorie()
                      let totalDistanceUnit = HKUnit.meterUnit(with: .kilo)

                      return [
                        "type": HKObjectType.workoutType().identifier, // Use the generic workout identifier string
                        "sourceName": sample.sourceRevision.source.name,
                        "sourceVersion": sample.sourceRevision.version, // Optional
                        "device": sample.device?.name, // Optional
                        "creationDate": self.isoFormatter.string(from: sample.endDate ?? sample.startDate),
                        "startDate": self.isoFormatter.string(from: sample.startDate),
                        "endDate": self.isoFormatter.string(from: sample.endDate),
                        "metadata": self.formatMetadata(sample.metadata), // Optional
                        "workoutActivityType": sample.workoutActivityType.name, // Use the descriptive name
                        "duration": sample.duration, // Duration in seconds
                        "durationUnit": durationUnit.unitString, // "s"
                        // Optional fields based on workout data
                        "totalEnergyBurned": sample.totalEnergyBurned?.doubleValue(for: totalEnergyBurnedUnit),
                        "totalEnergyBurnedUnit": sample.totalEnergyBurned != nil ? totalEnergyBurnedUnit.unitString : nil, // "kcal"
                        "totalDistance": sample.totalDistance?.doubleValue(for: totalDistanceUnit),
                        "totalDistanceUnit": sample.totalDistance != nil ? totalDistanceUnit.unitString : nil // "km"
                        // Consider adding workout events if needed: sample.workoutEvents
                      ]
                   }
                   result = ["success": true, "data": formattedSamples, "error": NSNull()]
               } else {
                   result = ["success": true, "data": [], "error": NSNull()] // No samples found
               }
               semaphore.signal()
           }
           healthStore.execute(query)

         } else {
           print("🔴 [HealthKit] Unsupported identifier: \(identifier)")
           result = [
             "success": false,
             "data": [],
             "error": [
               "code": "unsupported_identifier",
               "message": "Identifier not supported."
             ]
           ]
           semaphore.signal() // Signal semaphore for unsupported identifier case
         }

         // Wait only if a query was potentially executed
         if quantityTypeIdentifiers.contains(identifier) || categoryTypeIdentifiers.contains(identifier) || workoutTypeIdentifiers.contains(identifier) {
            print("🟡 [HealthKit] About to wait for semaphore...")
            semaphore.wait()
            print("🟢 [HealthKit] Semaphore signaled, continuing...")
         }

                  print("🟢 [HealthKit] Resolving promise with result: \(result)")
         promise.resolve(result)

                } catch {
           print("🔴 [HealthKit] EXCEPTION CAUGHT: \(error)")
           healthkitLogger.error("Exception in getHealthData: \(error.localizedDescription, privacy: .public)")
           promise.resolve([
             "success": false,
             "data": [],
             "error": [
               "code": "exception",
               "message": error.localizedDescription
             ]
           ])
         }
     }

     // Background Sync Methods
           AsyncFunction("enableBackgroundSync") { (options: [String: Any]) async -> [String: Any] in
       return await self.enableBackgroundSync(options: options)
     }

           AsyncFunction("getBackgroundSyncStatus") { () async -> [String: Any] in
       return await self.getBackgroundSyncStatus()
     }

           AsyncFunction("disableBackgroundSync") { () async -> [String: Any] in
       return await self.disableBackgroundSync()
     }

     // Register background task handler early (called during app launch)
     AsyncFunction("registerBackgroundTaskHandler") { () async -> [String: Any] in
       return await self.registerBackgroundTaskHandler()
     }

      OnCreate {
        // Don't mark as registered here - let registerBackgroundTaskHandler do the actual registration
        // self.backgroundTaskHandlerRegistered = true

        // Listen for background task triggered if registered elsewhere
        NotificationCenter.default.addObserver(forName: Notification.Name("ExpoHealthkitBackgroundTask"), object: nil, queue: nil) { [weak self] notification in
          guard let self = self, let task = notification.object as? BGAppRefreshTask else {
            return
          }
          self.handleBackgroundRefresh(task: task)
        }
      }
  }

  // Background sync implementation methods

  // CRITICAL: Register background task handler early (during app launch)
  private func registerBackgroundTaskHandler() async -> [String: Any] {
    // Prevent duplicate registration attempts
    if backgroundTaskHandlerRegistered {
      return ["success": true, "error": NSNull()]
    }
    do {
      BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
        if let refreshTask = task as? BGAppRefreshTask {
          self.handleBackgroundRefresh(task: refreshTask)
        } else {
          task.setTaskCompleted(success: false)
        }
      }

      backgroundTaskHandlerRegistered = true
      print("✅ [HealthKit] Background task handler registered successfully (early)")
      return ["success": true, "error": NSNull()]
    } catch {
      print("❌ [HealthKit] Failed to register background task handler: \(error.localizedDescription)")
      return ["success": false, "error": "Failed to register background task handler: \(error.localizedDescription)" ]
    }
  }

     private func enableBackgroundSync(options: [String: Any]) async -> [String: Any] {
    do {
      // Respect custom sync interval if provided
      if let interval = options["syncInterval"] as? Double {
        syncIntervalHours = interval
      }

      // Now it's safe to enable background sync
      backgroundSyncEnabled = true

      // Setup HKObserverQuery for health data changes
      setupHealthDataObserver()

      // Schedule initial background refresh (now safe since handler is registered)
      scheduleBackgroundHealthSync()

      // Emit event for successful background sync enablement
      sendEvent("onBackgroundSyncComplete", [
        "success": true,
        "syncedDataTypes": options["dataTypes"] as? [String] ?? [],
        "timestamp": isoFormatter.string(from: Date()),
        "error": NSNull()
      ])

      return ["success": true, "error": NSNull()]
    } catch {
      return ["success": false, "error": "Failed to enable background sync: \(error.localizedDescription)" ]
    }
  }

     private func getBackgroundSyncStatus() async -> [String: Any] {
         return ["enabled": backgroundSyncEnabled, "lastSync": lastSyncTimestamp ?? NSNull(), "error": NSNull()]
  }

     private func disableBackgroundSync() async -> [String: Any] {
    // Remove HKObserverQuery observers
    for query in observerQueries {
      healthStore.stop(query)
    }
    observerQueries.removeAll()

    // Cancel scheduled background tasks
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)

    backgroundSyncEnabled = false

    return ["success": true, "error": NSNull()]
  }

  // Setup observer for health data changes
  private func setupHealthDataObserver() {
    let sampleTypes: [HKSampleType] = [
      HKObjectType.quantityType(forIdentifier: .stepCount)!,
      HKObjectType.quantityType(forIdentifier: .heartRate)!,
      HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
      HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
      HKObjectType.quantityType(forIdentifier: .flightsClimbed)!,
      HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
      HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
      HKObjectType.quantityType(forIdentifier: .vo2Max)!,
      HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
      HKObjectType.workoutType()
    ]

    for sampleType in sampleTypes {
      let observerQuery = HKObserverQuery(sampleType: sampleType, predicate: nil) {
        (query, completionHandler, error) in

        if error == nil {
          // Only schedule background sync if it's enabled and properly configured
          if self.backgroundSyncEnabled {
            self.scheduleBackgroundHealthSync()
          }

          // Emit event for health data change
          self.sendEvent("onHealthDataChange", [
            "dataType": sampleType.identifier,
            "samplesAdded": 1, // We don't know the exact count here, just indicating change
            "timestamp": self.isoFormatter.string(from: Date())
          ])
        } else {
          healthkitLogger.error("Observer query error for \(sampleType.identifier): \(error?.localizedDescription ?? "Unknown error")")
        }
        completionHandler()
      }

      healthStore.execute(observerQuery)
      observerQueries.append(observerQuery)
    }
  }

  // Schedule background health sync
  private func scheduleBackgroundHealthSync() {
    // Only schedule if background sync is enabled and handler is registered
    guard backgroundSyncEnabled else {
      print("Background sync disabled - skipping scheduling")
      return
    }

    let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
    // Convert hours -> seconds; enforce minimum of 15 min (BGTaskScheduler lower bound)
    let requestedSeconds = max(syncIntervalHours * 60 * 60, 15 * 60)
    request.earliestBeginDate = Date(timeIntervalSinceNow: requestedSeconds)

    do {
      try BGTaskScheduler.shared.submit(request)
      print("Background health sync scheduled successfully")
    } catch {
      print("Failed to schedule background health sync: \(error)")
      // Don't crash the app if scheduling fails
    }
  }

  // Handle the background refresh issued by the system
  private func handleBackgroundRefresh(task: BGAppRefreshTask) {
    scheduleBackgroundHealthSync() // Schedule the next one early

    // Perform lightweight work and then call JS side for heavy processing
    let queue = OperationQueue()

    queue.maxConcurrentOperationCount = 1

    let operation = BlockOperation {
      // Placeholder: we could perform small checks here; heavy work should be done via JS bridge
      self.lastSyncTimestamp = self.isoFormatter.string(from: Date())

      // Emit background sync completion event
      self.sendEvent("onBackgroundSyncComplete", [
        "success": true,
        "syncedDataTypes": [], // Would be populated with actual synced types
        "timestamp": self.lastSyncTimestamp ?? self.isoFormatter.string(from: Date()),
        "error": NSNull()
      ])
    }

    task.expirationHandler = {
      queue.cancelAllOperations()
    }

    operation.completionBlock = {
      task.setTaskCompleted(success: !operation.isCancelled)
    }

    queue.addOperation(operation)
  }
}

// Helper extension for HKWorkoutActivityType to get a string name
extension HKWorkoutActivityType {
    var name: String {
        switch self {
            case .americanFootball: return "American Football"
            case .archery: return "Archery"
            case .australianFootball: return "Australian Football"
            case .badminton: return "Badminton"
            case .baseball: return "Baseball"
            case .basketball: return "Basketball"
            case .bowling: return "Bowling"
            case .boxing: return "Boxing"
            case .climbing: return "Climbing"
            case .cricket: return "Cricket"
            case .crossTraining: return "Cross Training"
            case .curling: return "Curling"
            case .cycling: return "Cycling"
            case .dance: return "Dance"
            case .danceInspiredTraining: return "Dance Inspired Training"
            case .elliptical: return "Elliptical"
            case .equestrianSports: return "Equestrian Sports"
            case .fencing: return "Fencing"
            case .fishing: return "Fishing"
            case .functionalStrengthTraining: return "Functional Strength Training"
            case .golf: return "Golf"
            case .gymnastics: return "Gymnastics"
            case .handball: return "Handball"
            case .hiking: return "Hiking"
            case .hockey: return "Hockey"
            case .hunting: return "Hunting"
            case .lacrosse: return "Lacrosse"
            case .martialArts: return "Martial Arts"
            case .mindAndBody: return "Mind and Body"
            case .mixedMetabolicCardioTraining: return "Mixed Metabolic Cardio Training"
            case .paddleSports: return "Paddle Sports"
            case .play: return "Play"
            case .preparationAndRecovery: return "Preparation and Recovery"
            case .racquetball: return "Racquetball"
            case .rowing: return "Rowing"
            case .rugby: return "Rugby"
            case .running: return "Running"
            case .sailing: return "Sailing"
            case .skatingSports: return "Skating Sports"
            case .snowSports: return "Snow Sports"
            case .soccer: return "Soccer"
            case .softball: return "Softball"
            case .squash: return "Squash"
            case .stairClimbing: return "Stair Climbing"
            case .surfingSports: return "Surfing Sports"
            case .swimming: return "Swimming"
            case .tableTennis: return "Table Tennis"
            case .tennis: return "Tennis"
            case .trackAndField: return "Track and Field"
            case .traditionalStrengthTraining: return "Traditional Strength Training"
            case .volleyball: return "Volleyball"
            case .walking: return "Walking"
            case .waterFitness: return "Water Fitness"
            case .waterPolo: return "Water Polo"
            case .waterSports: return "Water Sports"
            case .wrestling: return "Wrestling"
            case .yoga: return "Yoga"
            // iOS 10+:
            case .barre: return "Barre"
            case .coreTraining: return "Core Training"
            case .crossCountrySkiing: return "Cross Country Skiing"
            case .downhillSkiing: return "Downhill Skiing"
            case .flexibility: return "Flexibility"
            case .highIntensityIntervalTraining: return "High Intensity Interval Training"
            case .jumpRope: return "Jump Rope"
            case .kickboxing: return "Kickboxing"
            case .pilates: return "Pilates"
            case .snowboarding: return "Snowboarding"
            case .stairs: return "Stairs"
            case .stepTraining: return "Step Training"
            case .wheelchairWalkPace: return "Wheelchair Walk Pace"
            case .wheelchairRunPace: return "Wheelchair Run Pace"
            // iOS 11+:
            case .taiChi: return "Tai Chi"
            case .mixedCardio: return "Mixed Cardio"
            case .handCycling: return "Hand Cycling"
            // iOS 13+:
            case .discSports: return "Disc Sports"
            case .fitnessGaming: return "Fitness Gaming"
            // iOS 14+:
            case .cardioDance: return "Cardio Dance"
            case .socialDance: return "Social Dance"
            case .pickleball: return "Pickleball"
            case .cooldown: return "Cooldown"
            // iOS 16+:
            case .swimBikeRun: return "Swim Bike Run"
            case .transition: return "Transition"
            // iOS 17+:
            case .underwaterDiving: return "Underwater Diving"
            // Default/Other:
            case .other: return "Other"
            // Catch-all for potential future types not explicitly handled above
            @unknown default: return "Unknown Workout Type (\\(self.rawValue))"
        }
    }
}

// Need AnyCodable struct if not already present in the project
// This allows mixed types in the metadata dictionary
struct AnyCodable: Codable {
    let value: Any

    init<T>(_ value: T?) {
        self.value = value ?? ()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self.value = stringValue
        } else if let intValue = try? container.decode(Int.self) {
            self.value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            self.value = doubleValue
        } else if let boolValue = try? container.decode(Bool.self) {
            self.value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
             self.value = arrayValue.map { $0.value }
         } else if let dictionaryValue = try? container.decode([String: AnyCodable].self) {
             self.value = dictionaryValue.mapValues { $0.value }
        } else {
           throw DecodingError.typeMismatch(AnyCodable.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
        }
    }


     func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else if let boolValue = value as? Bool {
            try container.encode(boolValue)
         } else if let arrayValue = value as? [Any] {
             try container.encode(arrayValue.map { AnyCodable($0) })
         } else if let dictionaryValue = value as? [String: Any] {
             try container.encode(dictionaryValue.mapValues { AnyCodable($0) })
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type for encoding"))
        }
    }
}
