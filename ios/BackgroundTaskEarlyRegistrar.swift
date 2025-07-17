import BackgroundTasks
import Foundation

@objc(BackgroundTaskEarlyRegistrar)
public class BackgroundTaskEarlyRegistrar: NSObject {
  private static let taskIdentifier = "ae.fithack.mobile.health-sync"
  
  // Use a static initializer to register the background task handler early
  static let shared = BackgroundTaskEarlyRegistrar()
  
  private override init() {
    super.init()
    // Register the background task handler during initialization
    BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundTaskEarlyRegistrar.taskIdentifier, using: nil) { task in
      // Forward the task to the module via NotificationCenter so we don't need
      // a direct reference to the module instance here.
      NotificationCenter.default.post(name: Notification.Name("ExpoHealthkitBackgroundTask"), object: task)
    }
  }
  
  // This method will be called from Objective-C to ensure early initialization
  @objc
  public static func registerEarly() {
    // Just accessing the shared instance will trigger the init and registration
    _ = shared
  }
}
