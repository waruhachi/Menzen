#import <Foundation/Foundation.h>

// Launches apps in the background, one at a time, so each provider has checked
// its app's version before the user opens it.
@interface MenzenAppChecker : NSObject
// The apps on screen, from MenzenForegroundApps.
@property (nonatomic, copy) NSArray<NSString *> *visibleApps;
- (void)start;
- (void)openAppToCheck:(NSString *)bundleIdentifier returningTo:(NSString *)returnBundleIdentifier;
@end
