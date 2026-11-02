#import "../../Shared/MZProvider/MZProvider.h"
#import "../../Shared/MZProvider/MZResponses.h"

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
static NSString *const MZImageServer = @"https://disney.images.edge.bamgrid.com/ripcut-delivery/v2/variant/disney/";

#define MZItemShowKey @"show"
#define MZItemEpisodeTitleKey @"episodeTitle"
#define MZItemSeasonKey @"season"
#define MZItemEpisodeKey @"episode"
#define MZItemImageKey @"image"
#define MZItemLeagueKey @"league"
#define MZItemStartKey @"start"
#define MZItemEndKey @"end"
#define MZItemPageKey @"page"

static NSMutableDictionary<NSString *, NSDictionary *> *items;

// The item's 16:9 picture: its thumbnail (an episode's still), else its tile
// or background.
static NSString *MZImageID(NSDictionary *artwork) {
	static NSCharacterSet *invalid;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		invalid = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF-"].invertedSet;
	});
	for (NSString *kind in @[@"thumbnail", @"tile", @"background"]) {
		NSString *imageID = MZString(MZPath(artwork, @[@"standard", kind, @"1.78", @"imageId"]));
		if (imageID && [imageID rangeOfCharacterFromSet:invalid].location == NSNotFound) return imageID;
	}

	return nil;
}

// The movie's or the episode's show's.
static NSString *MZPage(NSArray *actions) {
	if (![actions isKindOfClass:NSArray.class]) return nil;
	for (NSDictionary *action in actions) {
		NSString *page = [action isKindOfClass:NSDictionary.class] ? MZString(action[@"pageId"]) : nil;
		if ([page hasPrefix:@"entity-"]) return page;
	}

	return nil;
}

static NSString *MZSeconds(id value) {
	static NSISO8601DateFormatter *formatter;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		formatter = [NSISO8601DateFormatter new];
	});
	NSDate *date = [value isKindOfClass:NSString.class] ? [formatter dateFromString:value] : nil;
	return date ? @((long long)date.timeIntervalSince1970).stringValue : nil;
}

static void MZRememberItems(id object) {
	if ([object isKindOfClass:NSArray.class]) {
		for (id child in object) MZRememberItems(child);
		return;
	}

	if (![object isKindOfClass:NSDictionary.class]) return;
	NSString *ID = MZString(object[@"id"]);
	NSDictionary *visuals = object[@"visuals"];
	if (ID && [visuals isKindOfClass:NSDictionary.class]) {
		NSMutableDictionary *item = [NSMutableDictionary dictionary];
		item[MZItemShowKey] = MZString(visuals[@"title"]);
		item[MZItemEpisodeTitleKey] = MZString(visuals[@"episodeTitle"]);
		item[MZItemSeasonKey] = MZString(visuals[@"seasonNumber"]);
		item[MZItemEpisodeKey] = MZString(visuals[@"episodeNumber"]);
		item[MZItemImageKey] = MZImageID(visuals[@"artwork"]);
		item[MZItemLeagueKey] = MZString(MZPath(visuals, @[@"metastringParts", @"sportsLeague", @"name"]));
		NSDictionary *timeline = MZPath(visuals, @[@"badging", @"airingEventState", @"timeline"]);
		item[MZItemStartKey] = MZSeconds(MZPath(timeline, @[@"startTime"]));
		item[MZItemEndKey] = MZSeconds(MZPath(timeline, @[@"endTime"]));
		item[MZItemPageKey] = MZPage(object[@"actions"]);
		if (item[MZItemImageKey] || item[MZItemEpisodeTitleKey]) {
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
		if ([child isKindOfClass:NSDictionary.class] || [child isKindOfClass:NSArray.class]) MZRememberItems(child);
	}
}

static BOOL MZIsExplore(NSURL *url) {
	return [url.host isEqualToString:@"disney.api.edge.bamgrid.com"] && [url.path hasPrefix:@"/explore/"];
}

// "S1:E1 <episode>" as season, episode and title.
static NSArray<NSString *> *MZEpisodeParts(NSString *text) {
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
static NSDictionary *MZExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	NSString *contentID = MZString(info[MPNowPlayingInfoPropertyExternalContentIdentifier]);
	NSString *show = contentID ? MZString(info[MPMediaItemPropertyTitle]) : nil;
	if (!show) return nil;
	NSDictionary *item = nil;
	@synchronized(items) {
		item = items[contentID];
	}

	NSString *title = item[MZItemEpisodeTitleKey];
	NSString *season = item[MZItemSeasonKey], *episode = item[MZItemEpisodeKey];
	NSArray *parts = MZEpisodeParts(info[MPMediaItemPropertyArtist]);
	if (!title && parts) {
		season = parts[0];
		episode = parts[1];
		title = parts[2];
	}

	// Never pass on the stream's URL.
	[withExtras removeObjectForKey:MPNowPlayingInfoPropertyAssetURL];
	if (title) {
		withExtras[MPMediaItemPropertyTitle] = title;
		withExtras[MPMediaItemPropertyArtist] = item[MZItemShowKey] ?: show;
		// An album that's the artist again is taken as none.
		withExtras[MPMediaItemPropertyAlbumTitle] = item[MZItemShowKey] ?: show;
	} else if (item[MZItemLeagueKey]) {
		withExtras[MPMediaItemPropertyArtist] = item[MZItemLeagueKey];
		withExtras[MPMediaItemPropertyAlbumTitle] = item[MZItemLeagueKey];
	}

	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	if (item[MZItemImageKey]) extras[MZExtrasCoverKey] = [NSString stringWithFormat:@"%@%@/scale?width=600&format=jpeg", MZImageServer, item[MZItemImageKey]];
	if (title) {
		extras[MZExtrasSeasonKey] = season.integerValue > 0 ? season : nil;
		extras[MZExtrasEpisodeKey] = episode.integerValue > 0 ? episode : nil;
	}

	NSString *page = MZLinkURL(@"https://www.disneyplus.com/browse/%@", item[MZItemPageKey]);
	extras[MZExtrasTitleURLKey] = page;
	if (title) extras[MZExtrasArtistURLKey] = page;
	if ([item[MZItemEndKey] longLongValue] > [item[MZItemStartKey] longLongValue]) {
		extras[MZExtrasStartKey] = item[MZItemStartKey];
		extras[MZExtrasEndKey] = item[MZItemEndKey];
	}

	return extras;
}

%ctor {
	items = [NSMutableDictionary dictionary];
	MZProviderCheck(@[], @[]);
	MZAddExtras(MZExtras);
	MZObserveResponses(^BOOL(NSURL *url) {
		return MZIsExplore(url);
	}, ^(NSURL *url, NSData *body) {
		MZRememberItems(MZJSON(body));
	});
}
