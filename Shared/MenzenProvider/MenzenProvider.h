#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>

#import "../MenzenTrackExtras.h"

FOUNDATION_EXPORT NSString *MenzenString(id value);
FOUNDATION_EXPORT NSDictionary *MenzenDictionary(id value);
FOUNDATION_EXPORT NSArray *MenzenArray(id value);
FOUNDATION_EXPORT id MenzenPath(id object, NSArray<NSString *> *keys);
FOUNDATION_EXPORT id MenzenGet(id object, NSString *name);
// Discord rejects URLs over 256 characters.
FOUNDATION_EXPORT NSString *MenzenImageURL(id value, NSArray<NSString *> *hosts);
FOUNDATION_EXPORT BOOL MenzenIsBetterWidth(double width, double bestWidth, double target);
FOUNDATION_EXPORT NSString *MenzenPairKey(NSString *first, NSString *second);

@interface MenzenCache<KeyType, ObjectType> : NSObject
- (instancetype)initWithLimit:(NSUInteger)limit;
- (nullable ObjectType)objectForKeyedSubscript:(KeyType)key;
- (void)setObject:(nullable ObjectType)object forKeyedSubscript:(KeyType)key;
- (void)removeAllObjects;
@end

// Returns the extras (MenzenTrackExtras.h) for info as the app publishes it, on
// the app's thread. withExtras is what gets published, with any extras left
// over from an earlier update already taken out.
typedef NSDictionary<NSString *, NSString *> *_Nullable (*MenzenExtrasFunction)(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras);

// Call once, from the provider's %ctor.
FOUNDATION_EXPORT void MenzenAddExtras(MenzenExtrasFunction extrasFor);
// Publishes the current info again, for extras that arrived late.
FOUNDATION_EXPORT void MenzenRepublish(void);

// Checks, each time the app opens, that it still has what the provider uses,
// and saves the result for the settings pane (MenzenSupport.h). Missing required
// parts get one alert per app version. Each requirement is "Class",
// "Class -method", "Class +method" or "Class _ivar" (an object), or
// alternatives joined by " | ". Call once, from the provider's %ctor.
FOUNDATION_EXPORT void MenzenProviderCheck(NSArray<NSString *> *required, NSArray<NSString *> *optional);
// For providers that add to the app some way other than MenzenAddExtras.
FOUNDATION_EXPORT void MenzenProviderWorked(void);

NS_ASSUME_NONNULL_END
