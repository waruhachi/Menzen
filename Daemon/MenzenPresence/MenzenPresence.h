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
- (void)setConnectedActivity:(MenzenActivity *)activity;
// Do Not Disturb or a Focus, for MenzenSettingSyncDoNotDisturb.
- (void)setDoNotDisturb:(BOOL)active;
- (void)appCatalogChanged;
- (void)settingsChanged;
@end
