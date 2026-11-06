#import <Foundation/Foundation.h>

@class MenzenActivity;
@class MenzenDiscord;
@class MenzenAppCatalog;
@class MenzenTrack;

NS_ASSUME_NONNULL_BEGIN

// Decides what Discord shows: of the custom preset (Shared/MenzenCustomActivity.h),
// a connected app's activity, the game on screen ("Playing <game>") and the
// playing track, the first in MenzenPriority() that has one. A paused track or
// a game that's been left stays until the grace period (MenzenSettingPauseGrace)
// runs out. Keeps the settings' preview of the last track current too. Main
// queue only.
@interface MenzenPresence : NSObject
- (instancetype)initWithDiscord:(MenzenDiscord *)discord appCatalog:(MenzenAppCatalog *)appCatalog;
- (void)handleTrack:(nullable MenzenTrack *)track;
// The apps on screen, the latest first (MenzenForegroundApps).
- (void)handleVisibleApps:(NSArray<NSString *> *)visibleApps;
// What the connected app that updated last wants shown; nil when none does.
- (void)setConnectedActivity:(nullable MenzenActivity *)activity;
// The game list changed, so a game's icon may have arrived.
- (void)appCatalogChanged;
// Applies the settings to what's playing again, and restarts any pause
// countdown with the new grace period.
- (void)settingsChanged;
@end

NS_ASSUME_NONNULL_END
