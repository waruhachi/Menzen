#import <Foundation/Foundation.h>

@class MenzenPresence;

NS_ASSUME_NONNULL_BEGIN

// Serves MenzenConnectedService (Shared/MenzenConnectedApps.h) to any process:
// libmenzen clients register, which lists them in the settings, and send
// activities, which reach MenzenPresence only while Connected Apps is on and
// the user allows them. Of those, the one that sent last shows. Main queue
// only.
@interface MenzenConnectedListener : NSObject
- (instancetype)initWithPresence:(MenzenPresence *)presence;
- (void)start;
// Connected Apps, an app's allowance, Menzen itself or Privacy Mode changed.
- (void)settingsChanged;
@end

NS_ASSUME_NONNULL_END
