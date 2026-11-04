#import <Foundation/Foundation.h>

#import "../MenzenDiscord/MenzenDiscord.h"
#import "../MenzenNowPlaying/MenzenNowPlaying.h"

NS_ASSUME_NONNULL_BEGIN

// Whether track has anything to show: a title, and isn't an ad.
FOUNDATION_EXPORT BOOL MenzenTrackIsShowable(MenzenTrack *_Nullable track);

// What Discord shows for track, following the card's parts (Shared/MenzenCard.h).
// Timestamps only while playing: Discord can't show a stopped clock, so a
// paused activity has none. logo is the app's icon from the catalog.
FOUNDATION_EXPORT MenzenActivity *_Nullable MenzenActivityForTrack(MenzenTrack *track, NSString *_Nullable logo);

// track as the settings' previews show it: like MenzenActivityForTrack, but with
// the progress bar even when it's paused or stopped (since stoppedDate),
// standing still as of pausedDate.
FOUNDATION_EXPORT MenzenActivity *_Nullable MenzenPreviewForTrack(MenzenTrack *track, NSString *_Nullable logo, NSDate *_Nullable stoppedDate, NSDate *_Nullable *_Nonnull pausedDate);

NS_ASSUME_NONNULL_END
