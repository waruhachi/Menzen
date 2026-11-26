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
- (ObjectType)objectForKeyedSubscript:(KeyType)key;
- (void)setObject:(ObjectType)object forKeyedSubscript:(KeyType)key;
- (void)removeAllObjects;
@end

typedef NSDictionary<NSString *, NSString *> *(*MenzenExtrasFunction)(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras);

FOUNDATION_EXPORT void MenzenAddExtras(MenzenExtrasFunction extrasFor);
FOUNDATION_EXPORT void MenzenRepublish(void);

FOUNDATION_EXPORT void MenzenProviderCheck(NSArray<NSString *> *required, NSArray<NSString *> *optional);
FOUNDATION_EXPORT void MenzenProviderWorked(void);
