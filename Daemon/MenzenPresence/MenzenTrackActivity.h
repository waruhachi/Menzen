#import <Foundation/Foundation.h>

#import "../MenzenDiscord/MenzenDiscord.h"
#import "../MenzenNowPlaying/MenzenNowPlaying.h"

NS_ASSUME_NONNULL_BEGIN

// Whether track has anything to show: a title, and isn't an ad.
FOUNDATION_EXPORT BOOL MenzenTrackIsShowable(MenzenTrack *_Nullable track);

// Timestamps only while playing: Discord can't show a stopped clock.
FOUNDATION_EXPORT MenzenActivity *MenzenActivityForTrack(MenzenTrack *track, NSString *logo);

FOUNDATION_EXPORT MenzenActivity *MenzenPreviewForTrack(MenzenTrack *track, NSString *logo, NSDate *stoppedDate, NSDate **pausedDate);
