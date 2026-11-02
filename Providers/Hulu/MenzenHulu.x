#import "../../Shared/MZProvider/MZProvider.h"
#import "../../Shared/MZProvider/MZResponses.h"

// An episode is published as "<show> | S1 E1 - <episode>". The content API
// describes each episode and movie by the ID the app publishes; its stills
// need a size added before the image server serves them.

static MZCache<NSString *, NSDictionary *> *entities;

static NSString *MZArtworkURL(NSDictionary *entity, NSString *ID) {
	NSDictionary *artwork = [entity[@"artwork"] isKindOfClass:NSDictionary.class] ? entity[@"artwork"] : nil;
	for (NSString *type in @[@"video.horizontal.hero", @"detail.horizontal.hero", @"program.tile"]) {
		NSDictionary *image = [artwork[type] isKindOfClass:NSDictionary.class] ? artwork[type] : nil;
		NSURLComponents *components = [NSURLComponents componentsWithString:MZString(image[@"path"]) ?: @""];
		NSString *host = components.host.lowercaseString;
		if (![components.scheme isEqualToString:@"https"] || !([host isEqualToString:@"img.hulu.com"] || ([host hasPrefix:@"img"] && [host hasSuffix:@".hulu.com"])) || ![components.path isEqualToString:[@"/user/v3/artwork/" stringByAppendingString:ID]]) continue;
		// Only which image it is.
		NSMutableArray *items = [NSMutableArray array];
		for (NSURLQueryItem *item in components.queryItems) {
			if (([item.name isEqualToString:@"base_image_bucket_name"] || [item.name isEqualToString:@"base_image"]) && MZLinkURL(@"%@", item.value)) [items addObject:item];
		}
		[items addObject:[NSURLQueryItem queryItemWithName:@"size" value:@"600x338"]];
		[items addObject:[NSURLQueryItem queryItemWithName:@"format" value:@"jpeg"]];
		components.queryItems = items;
		components.fragment = nil;
		NSString *url = components.URL.absoluteString;
		if (url.length <= 300) return url;
	}

	return nil;
}

static void MZRemember(NSData *body) {
	MZEachDictionary(MZJSON(body), ^(NSDictionary *entity) {
		NSString *type = MZString(entity[@"_type"]);
		NSString *ID = MZLinkURL(@"%@", entity[@"id"]);
		NSString *name = MZString(entity[@"name"]);
		if (!ID || !name || !([type isEqualToString:@"episode"] || [type isEqualToString:@"movie"])) return;
		NSMutableDictionary *kept = [NSMutableDictionary dictionary];
		kept[@"name"] = name;
		kept[@"show"] = MZString(entity[@"series_name"]);
		kept[@"season"] = MZString(entity[@"season"]);
		kept[@"number"] = MZString(entity[@"number"]);
		kept[@"cover"] = MZArtworkURL(entity, ID);
		entities[ID] = kept;
	});
}

static NSDictionary *MZExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	NSString *contentID = MZString(info[MPNowPlayingInfoPropertyExternalContentIdentifier]);
	NSDictionary *entity = contentID ? entities[contentID] : nil;
	if (!entity || center != MPNowPlayingInfoCenter.defaultCenter) return nil;

	withExtras[MPMediaItemPropertyTitle] = entity[@"name"];
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	NSString *show = entity[@"show"];
	if (show) {
		withExtras[MPMediaItemPropertyArtist] = show;
		// An album that's the artist again is taken as none.
		withExtras[MPMediaItemPropertyAlbumTitle] = show;
		NSInteger season = [entity[@"season"] integerValue];
		NSInteger episode = [entity[@"number"] integerValue];
		extras[MZExtrasSeasonKey] = season > 0 ? @(season).stringValue : nil;
		extras[MZExtrasEpisodeKey] = episode > 0 ? @(episode).stringValue : nil;
	} else {
		[withExtras removeObjectForKey:MPMediaItemPropertyArtist];
		if (withExtras[MPMediaItemPropertyAlbumTitle]) withExtras[MPMediaItemPropertyAlbumTitle] = @"";
	}

	extras[MZExtrasCoverKey] = entity[@"cover"];
	extras[MZExtrasTitleURLKey] = MZLinkURL(@"https://www.hulu.com/watch/%@", contentID);
	return extras;
}

%ctor {
	entities = [[MZCache alloc] initWithLimit:2000];
	MZProviderCheck(@[], @[]);
	MZAddExtras(MZExtras);
	MZObserveResponses(^BOOL(NSURL *url) {
		return [url.host.lowercaseString isEqualToString:@"discover.hulu.com"] && [url.path hasPrefix:@"/content/"];
	}, ^(NSURL *url, NSData *body) {
		MZRemember(body);
	});
}
