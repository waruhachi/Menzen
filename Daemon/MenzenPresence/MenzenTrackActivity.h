#import <Foundation/Foundation.h>

#import "../MenzenDiscord/MenzenDiscord.h"
#import "../MenzenNowPlaying/MenzenNowPlaying.h"

FOUNDATION_EXPORT BOOL MenzenTrackIsShowable(MenzenTrack *track);

// The line the user picked for member lists, the first one when it's empty.
FOUNDATION_EXPORT void MenzenApplyMemberList(MenzenActivity *activity);

// Timestamps only while playing: Discord can't show a stopped clock.
FOUNDATION_EXPORT MenzenActivity *MenzenActivityForTrack(MenzenTrack *track, NSString *logo);

FOUNDATION_EXPORT MenzenActivity *MenzenPreviewForTrack(MenzenTrack *track, NSString *logo, NSDate *stoppedDate, NSDate **pausedDate);
