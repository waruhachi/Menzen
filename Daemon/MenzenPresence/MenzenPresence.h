#import <Foundation/Foundation.h>

@class MenzenActivity;
@class MenzenDiscord;
@class MenzenAppCatalog;
@class MenzenTrack;

// A paused track or a game that's been left stays until the grace period
// (MenzenSettingPauseGrace) runs out. Main queue only.
@interface MenzenPresence : NSObject
- (instancetype)initWithDiscord:(MenzenDiscord *)discord appCatalog:(MenzenAppCatalog *)appCatalog;
- (void)handleTrack:(MenzenTrack *)track;
- (void)handleVisibleApps:(NSArray<NSString *> *)visibleApps;
// What the connected app that updated last wants shown; nil when none does.
- (void)setConnectedActivity:(nullable MenzenActivity *)activity;
// The game list changed, so a game's icon may have arrived.
- (void)appCatalogChanged;
- (void)settingsChanged;
@end
