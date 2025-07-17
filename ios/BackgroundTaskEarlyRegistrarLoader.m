#import <Foundation/Foundation.h>

// Forward declaration of the Swift class
@interface BackgroundTaskEarlyRegistrar : NSObject
+ (void)registerEarly;
@end

@interface BackgroundTaskEarlyRegistrarLoader : NSObject
@end

@implementation BackgroundTaskEarlyRegistrarLoader

+ (void)load {
    // Call the Swift class method to register the background task handler early
    [BackgroundTaskEarlyRegistrar registerEarly];
}

@end
