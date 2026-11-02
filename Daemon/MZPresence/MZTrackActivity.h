#import <Foundation/Foundation.h>

#import "../MZDiscord/MZDiscord.h"
#import "../MZNowPlaying/MZNowPlaying.h"

NS_ASSUME_NONNULL_BEGIN

// Whether track has anything to show: a title, and isn't an ad.
FOUNDATION_EXPORT BOOL MZTrackIsShowable(MZTrack *_Nullable track);

// What Discord shows for track, following the card's parts (Shared/MZCard.h).
// Timestamps only while playing: Discord can't show a stopped clock, so a
// paused activity has none. logo is the app's icon from the catalog.
FOUNDATION_EXPORT MZActivity *_Nullable MZActivityForTrack(MZTrack *track, NSString *_Nullable logo);

// track as the settings' previews show it: like MZActivityForTrack, but with
// the progress bar even when it's paused or stopped (since stoppedDate),
// standing still as of pausedDate.
FOUNDATION_EXPORT MZActivity *_Nullable MZPreviewForTrack(MZTrack *track, NSString *_Nullable logo, NSDate *_Nullable stoppedDate, NSDate *_Nullable *_Nonnull pausedDate);

NS_ASSUME_NONNULL_END
