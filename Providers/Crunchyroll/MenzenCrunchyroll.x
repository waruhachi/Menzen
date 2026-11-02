#import "../../Shared/MZProvider/MZProvider.h"
#import "../../Shared/MZProvider/MZResponses.h"

// Thumbnails come from the content API, which the app calls through Swift's
// async URLSession API, matched by content ID, else by title and series.
// Untested: found from the app's code only.

// By content ID and by title and series.
static MZCache<NSString *, NSDictionary *> *items;

static BOOL MZIsContent(NSURL *url) {
	NSString *host = url.host.lowercaseString;
	return [url.scheme isEqualToString:@"https"] && ([host isEqualToString:@"crunchyroll.com"] || [host hasSuffix:@".crunchyroll.com"]) && [url.path hasPrefix:@"/content/"];
}

// The smallest picture at least 600 wide, else the widest. Episodes nest
// their pictures in one more array than music.
static NSString *MZThumbnail(id images) {
	if (![images isKindOfClass:NSArray.class]) return nil;
	NSString *found = nil;
	double foundWidth = 0;
	for (id image in images) {
		NSArray *pictures = [image isKindOfClass:NSArray.class] ? image : @[image];
		for (NSDictionary *picture in pictures) {
			if (![picture isKindOfClass:NSDictionary.class]) continue;
			NSString *source = MZString(picture[@"source"]);
			id width = picture[@"width"];
			if (![source hasPrefix:@"https://imgsrv.crunchyroll.com/"] || source.length > 256 || ![width isKindOfClass:NSNumber.class]) continue;
			double w = [width doubleValue];
			BOOL better = !found || (foundWidth < 600 ? w > foundWidth : w >= 600 && w < foundWidth);
			if (better) {
				found = source;
				foundWidth = w;
			}
		}
	}

	return found;
}

static void MZRemember(id object, NSUInteger depth) {
	if (depth > 8) return;
	if ([object isKindOfClass:NSArray.class]) {
		for (id item in object) MZRemember(item, depth + 1);
		return;
	}

	if (![object isKindOfClass:NSDictionary.class]) return;
	NSDictionary *images = object[@"images"];
	NSString *thumbnail = [images isKindOfClass:NSDictionary.class] ? MZThumbnail(images[@"thumbnail"]) : nil;
	if (thumbnail) {
		NSString *ID = MZString(object[@"id"]);
		NSString *title = MZString(object[@"title"]);
		NSDictionary *episode = object[@"episode_metadata"];
		NSString *series = MZString([episode isKindOfClass:NSDictionary.class] ? episode[@"series_title"] : nil);
		NSMutableDictionary *extras = [NSMutableDictionary dictionary];
		extras[MZExtrasCoverKey] = thumbnail;
		extras[MZExtrasTitleURLKey] = MZLinkURL(@"https://www.crunchyroll.com/watch/%@", ID);
		if (ID) items[ID] = extras;
		NSString *key = MZPairKey(title, series);
		if (key) items[key] = extras;
	}

	for (id value in [object allValues]) {
		if ([value isKindOfClass:NSArray.class] || [value isKindOfClass:NSDictionary.class]) MZRemember(value, depth + 1);
	}
}

static NSDictionary *MZExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	if (withExtras[MPNowPlayingInfoPropertyAssetURL]) return nil;
	NSString *ID = MZString(info[MPNowPlayingInfoPropertyExternalContentIdentifier]);
	NSString *key = MZPairKey(MZString(info[MPMediaItemPropertyTitle]), MZString(info[MPMediaItemPropertyAlbumTitle]));
	return (ID ? items[ID] : nil) ?: (key ? items[key] : nil);
}

%ctor {
	items = [[MZCache alloc] initWithLimit:2000];
	MZProviderCheck(@[@"NSURLSession -_dataTaskWithRequest:delegate:completionHandler:"], @[]);
	MZAddExtras(MZExtras);
	MZObserveResponses(^BOOL(NSURL *url) {
		return MZIsContent(url);
	}, ^(NSURL *url, NSData *body) {
		id object = MZJSON(body);
		if (object) MZRemember(object, 0);
	});
}
