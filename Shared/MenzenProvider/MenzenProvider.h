#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>

#import "../MenzenTrackExtras.h"

NS_ASSUME_NONNULL_BEGIN

// A non-empty string, or a number as a string.
FOUNDATION_EXPORT NSString *_Nullable MenzenString(id _Nullable value);
FOUNDATION_EXPORT NSDictionary *_Nullable MenzenDictionary(id _Nullable value);
FOUNDATION_EXPORT NSArray *_Nullable MenzenArray(id _Nullable value);
FOUNDATION_EXPORT id _Nullable MenzenPath(id _Nullable object, NSArray<NSString *> *keys);
// The getter's value, numbers boxed; nil when object doesn't have it.
FOUNDATION_EXPORT id _Nullable MenzenGet(id _Nullable object, NSString *name);
// An https URL on one of hosts ("example.com", or ".example.com" for any
// subdomain), at most 256 characters: Discord rejects longer ones.
FOUNDATION_EXPORT NSString *_Nullable MenzenImageURL(id _Nullable value, NSArray<NSString *> *hosts);
// For caches keyed by two names; nil without both.
FOUNDATION_EXPORT NSString *_Nullable MenzenPairKey(NSString *_Nullable first, NSString *_Nullable second);

// Thread safe, dropping its oldest entries past limit.
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
