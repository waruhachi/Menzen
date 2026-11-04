#import "../../Shared/MenzenProvider/MenzenProvider.h"
#import "../../Shared/MenzenProvider/MenzenResponses.h"

// An episode is published as its show, with "S1:E1 <episode>" as the artist
// and the stream's signed URL as the asset URL, which is replaced here. The
// player has nothing readable, and what it fetches only has the show's
// pictures; the episode's comes from the explore API's lists, by the
// published ID.
//
// A live event's ID is listed as "<content ID>:<…>:<…>". Its time slot is
// published as start and end, since a live stream's info has no duration.

// The app's image server, from its configuration
// (ripcut-delivery/{version}/variant/{partnerId}/{imageId}/scale).
static NSString *const MenzenImageServer = @"https://disney.images.edge.bamgrid.com/ripcut-delivery/v2/variant/disney/";

#define MenzenItemShowKey @"show"
#define MenzenItemEpisodeTitleKey @"episodeTitle"
#define MenzenItemSeasonKey @"season"
#define MenzenItemEpisodeKey @"episode"
#define MenzenItemImageKey @"image"
#define MenzenItemLeagueKey @"league"
#define MenzenItemStartKey @"start"
#define MenzenItemEndKey @"end"
#define MenzenItemPageKey @"page"

static NSMutableDictionary<NSString *, NSDictionary *> *items;

// The item's 16:9 picture: its thumbnail (an episode's still), else its tile
// or background.
static NSString *MenzenImageID(NSDictionary *artwork) {
	static NSCharacterSet *invalid;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		invalid = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF-"].invertedSet;
	});
	for (NSString *kind in @[@"thumbnail", @"tile", @"background"]) {
		NSString *imageID = MenzenString(MenzenPath(artwork, @[@"standard", kind, @"1.78", @"imageId"]));
		if (imageID && [imageID rangeOfCharacterFromSet:invalid].location == NSNotFound) return imageID;
	}

	return nil;
}

// The movie's or the episode's show's.
static NSString *MenzenPage(NSArray *actions) {
	if (![actions isKindOfClass:NSArray.class]) return nil;
	for (NSDictionary *action in actions) {
		NSString *page = [action isKindOfClass:NSDictionary.class] ? MenzenString(action[@"pageId"]) : nil;
		if ([page hasPrefix:@"entity-"]) return page;
	}

	return nil;
}

static NSString *MenzenSeconds(id value) {
	static NSISO8601DateFormatter *formatter;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		formatter = [NSISO8601DateFormatter new];
	});
	NSDate *date = [value isKindOfClass:NSString.class] ? [formatter dateFromString:value] : nil;
	return date ? @((long long)date.timeIntervalSince1970).stringValue : nil;
}

static void MenzenRememberItems(id object) {
	if ([object isKindOfClass:NSArray.class]) {
		for (id child in object) MenzenRememberItems(child);
		return;
	}

	if (![object isKindOfClass:NSDictionary.class]) return;
	NSString *ID = MenzenString(object[@"id"]);
	NSDictionary *visuals = object[@"visuals"];
	if (ID && [visuals isKindOfClass:NSDictionary.class]) {
		NSMutableDictionary *item = [NSMutableDictionary dictionary];
		item[MenzenItemShowKey] = MenzenString(visuals[@"title"]);
		item[MenzenItemEpisodeTitleKey] = MenzenString(visuals[@"episodeTitle"]);
		item[MenzenItemSeasonKey] = MenzenString(visuals[@"seasonNumber"]);
		item[MenzenItemEpisodeKey] = MenzenString(visuals[@"episodeNumber"]);
		item[MenzenItemImageKey] = MenzenImageID(visuals[@"artwork"]);
		item[MenzenItemLeagueKey] = MenzenString(MenzenPath(visuals, @[@"metastringParts", @"sportsLeague", @"name"]));
		NSDictionary *timeline = MenzenPath(visuals, @[@"badging", @"airingEventState", @"timeline"]);
		item[MenzenItemStartKey] = MenzenSeconds(MenzenPath(timeline, @[@"startTime"]));
		item[MenzenItemEndKey] = MenzenSeconds(MenzenPath(timeline, @[@"endTime"]));
		item[MenzenItemPageKey] = MenzenPage(object[@"actions"]);
		if (item[MenzenItemImageKey] || item[MenzenItemEpisodeTitleKey]) {
			// A live event's info has the first part of its ID.
			NSString *contentID = [ID componentsSeparatedByString:@":"].firstObject;
			@synchronized(items) {
				if (items.count > 1000) [items removeAllObjects];
				items[ID] = item;
				if (![contentID isEqualToString:ID] && !items[contentID]) items[contentID] = item;
			}
		}
	}

	for (id child in [object allValues]) {
		if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class]) MenzenRememberItems(child);
	}
}

static BOOL MenzenIsExplore(NSURL *url) {
	return [url.host isEqualToString:@"disney.api.edge.bamgrid.com"] && [url.path hasPrefix:@"/explore/"];
}

// "S1:E1 <episode>" as season, episode and title.
static NSArray<NSString *> *MenzenEpisodeParts(NSString *text) {
	static NSRegularExpression *expression;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		expression = [NSRegularExpression regularExpressionWithPattern:@"^S(\\d+):E(\\d+)\\s+(.+)$" options:0 error:nil];
	});
	NSTextCheckingResult *match = [text isKindOfClass:NSString.class] ? [expression firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] : nil;
	if (!match) return nil;
	return @[[text substringWithRange:[match rangeAtIndex:1]], [text substringWithRange:[match rangeAtIndex:2]], [text substringWithRange:[match rangeAtIndex:3]]];
}

// The player publishes through its MPNowPlayingSession's own center.
static NSDictionary *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	NSString *contentID = MenzenString(info[MPNowPlayingInfoPropertyExternalContentIdentifier]);
	NSString *show = contentID ? MenzenString(info[MPMediaItemPropertyTitle]) : nil;
	if (!show) return nil;
	NSDictionary *item = nil;
	@synchronized(items) {
		item = items[contentID];
	}

	NSString *title = item[MenzenItemEpisodeTitleKey];
	NSString *season = item[MenzenItemSeasonKey], *episode = item[MenzenItemEpisodeKey];
	NSArray *parts = MenzenEpisodeParts(info[MPMediaItemPropertyArtist]);
	if (!title && parts) {
		season = parts[0];
		episode = parts[1];
		title = parts[2];
	}

	// Never pass on the stream's URL.
	[withExtras removeObjectForKey:MPNowPlayingInfoPropertyAssetURL];
	if (title) {
		withExtras[MPMediaItemPropertyTitle] = title;
		withExtras[MPMediaItemPropertyArtist] = item[MenzenItemShowKey] ?: show;
		// An album that's the artist again is taken as none.
		withExtras[MPMediaItemPropertyAlbumTitle] = item[MenzenItemShowKey] ?: show;
	} else if (item[MenzenItemLeagueKey]) {
		withExtras[MPMediaItemPropertyArtist] = item[MenzenItemLeagueKey];
		withExtras[MPMediaItemPropertyAlbumTitle] = item[MenzenItemLeagueKey];
	}

	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	if (item[MenzenItemImageKey]) extras[MenzenExtrasCoverKey] = [NSString stringWithFormat:@"%@%@/scale?width=600&format=jpeg", MenzenImageServer, item[MenzenItemImageKey]];
	if (title) {
		extras[MenzenExtrasSeasonKey] = season.integerValue > 0 ? season : nil;
		extras[MenzenExtrasEpisodeKey] = episode.integerValue > 0 ? episode : nil;
	}

	NSString *page = MenzenLinkURL(@"https://www.disneyplus.com/browse/%@", item[MenzenItemPageKey]);
	extras[MenzenExtrasTitleURLKey] = page;
	if (title) extras[MenzenExtrasArtistURLKey] = page;
	if ([item[MenzenItemEndKey] longLongValue] > [item[MenzenItemStartKey] longLongValue]) {
		extras[MenzenExtrasStartKey] = item[MenzenItemStartKey];
		extras[MenzenExtrasEndKey] = item[MenzenItemEndKey];
	}

	return extras;
}

%ctor {
	items = [NSMutableDictionary dictionary];
	MenzenProviderCheck(@[], @[]);
	MenzenAddExtras(MenzenExtras);
	MenzenObserveResponses(^BOOL(NSURL *url) {
		return MenzenIsExplore(url);
	}, ^(NSURL *url, NSData *body) {
		MenzenRememberItems(MenzenJSON(body));
	});
}
