#import <Foundation/Foundation.h>

@class MenzenDiscord;
@class MenzenAppCatalog;
@class MenzenTrack;

NS_ASSUME_NONNULL_BEGIN

// Decides what Discord shows: the custom preset when it's switched on
// (Shared/MenzenCustomActivity.h), else a game on screen ("Playing <game>"), else a
// playing track from an app that's switched on, frozen when it pauses and
// cleared once the pause grace period (MenzenSettingPauseGrace) runs out. Keeps
// the settings' preview of the last track current too. Main queue only.
@interface MenzenPresence : NSObject
- (instancetype)initWithDiscord:(MenzenDiscord *)discord appCatalog:(MenzenAppCatalog *)appCatalog;
- (void)handleTrack:(nullable MenzenTrack *)track;
// The apps on screen, the latest first (MenzenForegroundApps).
- (void)handleVisibleApps:(NSArray<NSString *> *)visibleApps;
// The game list changed, so a game's icon may have arrived.
- (void)appCatalogChanged;
// Applies the settings to what's playing again, and restarts any pause
// countdown with the new grace period.
- (void)settingsChanged;
@end

NS_ASSUME_NONNULL_END
