#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Has each provider check its app's installed version (Shared/MenzenSupport.h)
// before the user opens it: when menzend starts (so after Menzen is installed
// or updated) and when apps are installed or updated, it launches each app
// with a provider and no check of this version in the background, one at a
// time, and closes it again once the provider has saved its check. Waits for
// the device to be unlocked, and leaves apps that are already running alone.
@interface MenzenAppChecker : NSObject
- (void)start;
// The settings pane's "Open <app> to Check": opens the app, and once its
// provider has saved the check, brings back returnBundleIdentifier (the app
// the pane is in).
- (void)openAppToCheck:(NSString *)bundleIdentifier returningTo:(NSString *)returnBundleIdentifier;
@end

NS_ASSUME_NONNULL_END
