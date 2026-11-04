#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Finds a season and episode in a title, like Tubi's "S01:E01 - Leslie
// Reeves": "S1E1", "S01 E01", "S1 · Ep. 1", "Season 1, Episode 1", or just
// "Episode 4" or "Ep. 4" (season 0). rest is the title without it when it's
// at the start or end (with the separator next to it, or the brackets around
// it), and the whole title when it's in the middle.
FOUNDATION_EXPORT BOOL MenzenFindEpisode(NSString *title, NSInteger *season, NSInteger *episode, NSString *_Nonnull *_Nonnull rest);
// "Season 1, Episode 2", "Episode 2" or "Season 1"; nil when both are 0.
FOUNDATION_EXPORT NSString *_Nullable MenzenEpisodeText(NSInteger season, NSInteger episode);

NS_ASSUME_NONNULL_END
