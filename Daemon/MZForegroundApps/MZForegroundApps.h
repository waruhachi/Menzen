#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Watches which apps are on screen, through RunningBoard: an app is on
// screen while FrontBoard gives it the visibility endowment, so the home
// screen, the lock screen and the app switcher take it away. Nothing is
// injected into the apps or SpringBoard. Main queue only.
@interface MZForegroundApps : NSObject
// visible: the bundle IDs on screen, the one that came last first (two with
// Split View).
- (instancetype)initWithHandler:(void (^)(NSArray<NSString *> *visible))handler;
- (BOOL)start;
@end

NS_ASSUME_NONNULL_END
