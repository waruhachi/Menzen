#import <Foundation/Foundation.h>

// An app is on screen while FrontBoard gives it the visibility endowment, so
// the home screen, the lock screen and the app switcher take it away. Nothing
// is injected into the apps or SpringBoard.
@interface MenzenForegroundApps : NSObject
// visible: the bundle IDs on screen, the one that came last first (two with
// Split View).
- (instancetype)initWithHandler:(void (^)(NSArray<NSString *> *visible))handler;
- (BOOL)start;
@end
