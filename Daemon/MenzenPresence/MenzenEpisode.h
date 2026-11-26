#import <Foundation/Foundation.h>

FOUNDATION_EXPORT BOOL MenzenFindEpisode(NSString *title, NSInteger *season, NSInteger *episode, NSString **rest);
FOUNDATION_EXPORT NSString *MenzenEpisodeText(NSInteger season, NSInteger episode);
