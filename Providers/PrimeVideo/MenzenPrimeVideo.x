#import "../../Shared/MenzenProvider/MenzenProvider.h"

// An episode is published as its show, with "Season 1, Ep. 1 <episode>" as
// the artist. The cover and ID come from the playing AIVPlaybackTitle; the
// external content ID is its ASIN plus ":<country>".

@interface NSObject (MenzenPrimeVideo)
- (id)titleId;
- (id)nowPlayingImageURL;
- (NSString *)internalString;
@end

// Guarded by lock.
static NSString *titleID;
static NSString *titleCover;
static NSObject *lock;

static void MenzenRememberTitle(id title, id image) {
	id ASIN = [title respondsToSelector:@selector(titleId)] ? [title titleId] : nil;
	if ([ASIN respondsToSelector:@selector(internalString)]) ASIN = [ASIN internalString];
	NSString *ID = MenzenLinkURL(@"%@", ASIN);
	if (!ID) return;
	NSString *cover = MenzenImageURL(image, @[@"m.media-amazon.com", @"ssl-images-amazon.com", @".ssl-images-amazon.com"]);
	@synchronized(lock) {
		titleID = ID;
		titleCover = cover;
	}
}

// "Season 1, Ep. 1 <episode>" as season, episode and title.
static NSArray<NSString *> *MenzenEpisodeParts(NSString *text) {
	static NSRegularExpression *expression;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		expression = [NSRegularExpression regularExpressionWithPattern:@"^Season (\\d+), Ep\\. (\\d+)\\s+(.+)$" options:0 error:nil];
	});
	NSTextCheckingResult *match = [text isKindOfClass:NSString.class] ? [expression firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] : nil;
	if (!match) return nil;
	return @[[text substringWithRange:[match rangeAtIndex:1]], [text substringWithRange:[match rangeAtIndex:2]], [text substringWithRange:[match rangeAtIndex:3]]];
}

%hook AIVPlaybackTitle

- (id)nowPlayingImageURL {
	id image = %orig;
	MenzenRememberTitle(self, image);
	return image;
}

%end

static NSDictionary *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	NSString *contentID = MenzenString(info[MPNowPlayingInfoPropertyExternalContentIdentifier]);
	NSString *ID, *cover;
	@synchronized(lock) {
		ID = titleID;
		cover = titleCover;
	}

	// Only the title's own info.
	if (!ID || !contentID || center != MPNowPlayingInfoCenter.defaultCenter || !([contentID isEqualToString:ID] || [contentID hasPrefix:[ID stringByAppendingString:@":"]])) return nil;

	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	NSArray *parts = MenzenEpisodeParts(info[MPMediaItemPropertyArtist]);
	NSString *show = MenzenString(info[MPMediaItemPropertyTitle]);
	if (parts && show) {
		withExtras[MPMediaItemPropertyTitle] = parts[2];
		withExtras[MPMediaItemPropertyArtist] = show;
		// An album that's the artist again is taken as none.
		withExtras[MPMediaItemPropertyAlbumTitle] = show;
		extras[MenzenExtrasSeasonKey] = [parts[0] integerValue] > 0 ? parts[0] : nil;
		extras[MenzenExtrasEpisodeKey] = [parts[1] integerValue] > 0 ? parts[1] : nil;
	}

	extras[MenzenExtrasCoverKey] = cover;
	extras[MenzenExtrasTitleURLKey] = MenzenLinkURL(@"https://www.primevideo.com/detail/%@", ID);
	return extras;
}

%ctor {
	lock = [NSObject new];
	MenzenProviderCheck(@[@"AIVPlaybackTitle -nowPlayingImageURL", @"AIVPlaybackTitle -titleId"], @[]);
	MenzenAddExtras(MenzenExtras);
	%init;
}
