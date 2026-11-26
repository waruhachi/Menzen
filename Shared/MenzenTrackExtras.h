#import <Foundation/Foundation.h>

// What a provider hook knows that MediaRemote has no field for (the cover's
// URL, the artist's picture, links), passed to menzend as the now playing
// info's asset URL:
//   menzen:extras?cover=<url>&artistImage=<url>&artistName=<name>&titleURL=<url>&artistURL=<url>&albumURL=<url>&season=<n>&episode=<n>&start=<t>&end=<t>
// Every field is optional. menzend only uses URLs on the provider's own hosts.
// season and episode are numbers, for apps whose titles don't say. start
// and end are a live listing's time slot (seconds since 1970), for live
// streams, whose duration and elapsed time MediaRemote drops.

#define MenzenRefetchNotification "moe.waru.menzen.refetch"

#define MenzenExtrasScheme @"menzen"
#define MenzenExtrasCoverKey @"cover"
#define MenzenExtrasArtistImageKey @"artistImage"
#define MenzenExtrasArtistNameKey @"artistName"
#define MenzenExtrasTitleURLKey @"titleURL"
#define MenzenExtrasArtistURLKey @"artistURL"
#define MenzenExtrasAlbumURLKey @"albumURL"
#define MenzenExtrasSeasonKey @"season"
#define MenzenExtrasEpisodeKey @"episode"
#define MenzenExtrasStartKey @"start"
#define MenzenExtrasEndKey @"end"

static inline NSURL *MenzenExtrasURL(NSDictionary<NSString *, NSString *> *extras) {
	if (!extras.count) return nil;
	NSURLComponents *components = [NSURLComponents new];
	components.scheme = MenzenExtrasScheme;
	components.path = @"extras";
	NSMutableArray *items = [NSMutableArray array];
	for (NSString *key in [extras.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
		[items addObject:[NSURLQueryItem queryItemWithName:key value:extras[key]]];
	}
	components.queryItems = items;
	return components.URL;
}

// nil unless ID is only letters, digits, "-", "_", ".", ":", so it can't
// change where the link goes.
static inline NSString *MenzenLinkURL(NSString *format, id ID) {
	static NSCharacterSet *invalid;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		invalid = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:"].invertedSet;
	});
	if ([ID isKindOfClass:NSNumber.class]) ID = [ID stringValue];
	if (![ID isKindOfClass:NSString.class] || ![ID length] || [ID length] > 100 || [ID rangeOfCharacterFromSet:invalid].location != NSNotFound || [ID containsString:@".."]) return nil;
	return [format stringByReplacingOccurrencesOfString:@"%@" withString:ID];
}

static inline NSDictionary<NSString *, NSString *> *MenzenExtrasFromURL(NSString *url) {
	NSURLComponents *components = url ? [NSURLComponents componentsWithString:url] : nil;
	if (![components.scheme isEqualToString:MenzenExtrasScheme]) return nil;
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	for (NSURLQueryItem *item in components.queryItems) {
		if (item.value.length) extras[item.name] = item.value;
	}
	return extras;
}
