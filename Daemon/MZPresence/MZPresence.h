#import <Foundation/Foundation.h>

@class MZDiscord;
@class MZAppCatalog;
@class MZTrack;

NS_ASSUME_NONNULL_BEGIN

// Decides what Discord shows: the custom preset when it's switched on
// (Shared/MZCustomActivity.h), else a game on screen ("Playing <game>"), else a
// playing track from an app that's switched on, frozen when it pauses and
// cleared once the pause grace period (MZSettingPauseGrace) runs out. Keeps
// the settings' preview of the last track current too. Main queue only.
@interface MZPresence : NSObject
- (instancetype)initWithDiscord:(MZDiscord *)discord appCatalog:(MZAppCatalog *)appCatalog;
- (void)handleTrack:(nullable MZTrack *)track;
// The apps on screen, the latest first (MZForegroundApps).
- (void)handleVisibleApps:(NSArray<NSString *> *)visibleApps;
// The game list changed, so a game's icon may have arrived.
- (void)appCatalogChanged;
// Applies the settings to what's playing again, and restarts any pause
// countdown with the new grace period.
- (void)settingsChanged;
@end

NS_ASSUME_NONNULL_END
