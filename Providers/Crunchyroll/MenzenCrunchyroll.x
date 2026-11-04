#import "../../Shared/MenzenProvider/MenzenProvider.h"
#import "../../Shared/MenzenProvider/MenzenResponses.h"

// Thumbnails come from the content API, which the app calls through Swift's
// async URLSession API, matched by content ID, else by title and series.
// Untested: found from the app's code only.

// By content ID and by title and series.
static MenzenCache<NSString *, NSDictionary *> *items;

static BOOL MenzenIsContent(NSURL *url) {
	NSString *host = url.host.lowercaseString;
	return [url.scheme isEqualToString:@"https"] && ([host isEqualToString:@"crunchyroll.com"] || [host hasSuffix:@".crunchyroll.com"]) && [url.path hasPrefix:@"/content/"];
}

// The smallest picture at least 600 wide, else the widest. Episodes nest
// their pictures in one more array than music.
static NSString *MenzenThumbnail(id images) {
	if (![images isKindOfClass:NSArray.class]) return nil;
	NSString *found = nil;
	double foundWidth = 0;
	for (id image in images) {
		NSArray *pictures = [image isKindOfClass:NSArray.class] ? image : @[image];
		for (NSDictionary *picture in pictures) {
			if (![picture isKindOfClass:NSDictionary.class]) continue;
			NSString *source = MenzenString(picture[@"source"]);
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

static void MenzenRemember(id object, NSUInteger depth) {
	if (depth > 8) return;
	if ([object isKindOfClass:NSArray.class]) {
		for (id item in object) MenzenRemember(item, depth + 1);
		return;
	}

	if (![object isKindOfClass:NSDictionary.class]) return;
	NSDictionary *images = object[@"images"];
	NSString *thumbnail = [images isKindOfClass:NSDictionary.class] ? MenzenThumbnail(images[@"thumbnail"]) : nil;
	if (thumbnail) {
		NSString *ID = MenzenString(object[@"id"]);
		NSString *title = MenzenString(object[@"title"]);
		NSDictionary *episode = object[@"episode_metadata"];
		NSString *series = MenzenString([episode isKindOfClass:NSDictionary.class] ? episode[@"series_title"] : nil);
		NSMutableDictionary *extras = [NSMutableDictionary dictionary];
		extras[MenzenExtrasCoverKey] = thumbnail;
		extras[MenzenExtrasTitleURLKey] = MenzenLinkURL(@"https://www.crunchyroll.com/watch/%@", ID);
		if (ID) items[ID] = extras;
		NSString *key = MenzenPairKey(title, series);
		if (key) items[key] = extras;
	}

	for (id value in [object allValues]) {
		if ([value isKindOfClass:NSArray.class] || [value isKindOfClass:NSDictionary.class]) MenzenRemember(value, depth + 1);
	}
}

static NSDictionary *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	if (withExtras[MPNowPlayingInfoPropertyAssetURL]) return nil;
	NSString *ID = MenzenString(info[MPNowPlayingInfoPropertyExternalContentIdentifier]);
	NSString *key = MenzenPairKey(MenzenString(info[MPMediaItemPropertyTitle]), MenzenString(info[MPMediaItemPropertyAlbumTitle]));
	return (ID ? items[ID] : nil) ?: (key ? items[key] : nil);
}

%ctor {
	items = [[MenzenCache alloc] initWithLimit:2000];
	MenzenProviderCheck(@[@"NSURLSession -_dataTaskWithRequest:delegate:completionHandler:"], @[]);
	MenzenAddExtras(MenzenExtras);
	MenzenObserveResponses(^BOOL(NSURL *url) {
		return MenzenIsContent(url);
	}, ^(NSURL *url, NSData *body) {
		id object = MenzenJSON(body);
		if (object) MenzenRemember(object, 0);
	});
}
