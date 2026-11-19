#import <Foundation/Foundation.h>

@class MenzenPresence;

NS_ASSUME_NONNULL_BEGIN

// Serves MenzenConnectedService (Shared/MenzenConnectedApps.h) to any process:
// libmenzen clients register, which lists them in the settings, and send
// activities, which reach MenzenPresence only while Connected Apps is on and
// the user allows them. Of those, the one that sent last shows. A new app
// asking while Connected Apps is on is passed to SpringBoard to ask the
// user. Main queue only.
@interface MenzenConnectedListener : NSObject
- (instancetype)initWithPresence:(MenzenPresence *)presence;
- (void)start;
// Connected Apps, an app's allowance, Menzen itself or Privacy Mode changed.
- (void)settingsChanged;
// Takes the app off the list. Its open connections stop counting as it, so it
// comes back once it connects again.
- (void)removeApp:(NSString *)identifier;
@end

NS_ASSUME_NONNULL_END
