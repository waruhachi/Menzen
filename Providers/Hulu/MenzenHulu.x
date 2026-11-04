#import "../../Shared/MenzenProvider/MenzenProvider.h"
#import "../../Shared/MenzenProvider/MenzenResponses.h"

// An episode is published as "<show> | S1 E1 - <episode>". The content API
// describes each episode and movie by the ID the app publishes; its stills
// need a size added before the image server serves them.

static MenzenCache<NSString *, NSDictionary *> *entities;

static NSString *MenzenArtworkURL(NSDictionary *entity, NSString *ID) {
	NSDictionary *artwork = [entity[@"artwork"] isKindOfClass:NSDictionary.class] ? entity[@"artwork"] : nil;
	for (NSString *type in @[@"video.horizontal.hero", @"detail.horizontal.hero", @"program.tile"]) {
		NSDictionary *image = [artwork[type] isKindOfClass:NSDictionary.class] ? artwork[type] : nil;
		NSURLComponents *components = [NSURLComponents componentsWithString:MenzenString(image[@"path"]) ?: @""];
		NSString *host = components.host.lowercaseString;
		if (![components.scheme isEqualToString:@"https"] || !([host isEqualToString:@"img.hulu.com"] || ([host hasPrefix:@"img"] && [host hasSuffix:@".hulu.com"])) || ![components.path isEqualToString:[@"/user/v3/artwork/" stringByAppendingString:ID]]) continue;
		// Only which image it is.
		NSMutableArray *items = [NSMutableArray array];
		for (NSURLQueryItem *item in components.queryItems) {
			if (([item.name isEqualToString:@"base_image_bucket_name"] || [item.name isEqualToString:@"base_image"]) && MenzenLinkURL(@"%@", item.value)) [items addObject:item];
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

static void MenzenRemember(NSData *body) {
	MenzenEachDictionary(MenzenJSON(body), ^(NSDictionary *entity) {
		NSString *type = MenzenString(entity[@"_type"]);
		NSString *ID = MenzenLinkURL(@"%@", entity[@"id"]);
		NSString *name = MenzenString(entity[@"name"]);
		if (!ID || !name || !([type isEqualToString:@"episode"] || [type isEqualToString:@"movie"])) return;
		NSMutableDictionary *kept = [NSMutableDictionary dictionary];
		kept[@"name"] = name;
		kept[@"show"] = MenzenString(entity[@"series_name"]);
		kept[@"season"] = MenzenString(entity[@"season"]);
		kept[@"number"] = MenzenString(entity[@"number"]);
		kept[@"cover"] = MenzenArtworkURL(entity, ID);
		entities[ID] = kept;
	});
}

static NSDictionary *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	NSString *contentID = MenzenString(info[MPNowPlayingInfoPropertyExternalContentIdentifier]);
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
		extras[MenzenExtrasSeasonKey] = season > 0 ? @(season).stringValue : nil;
		extras[MenzenExtrasEpisodeKey] = episode > 0 ? @(episode).stringValue : nil;
	} else {
		[withExtras removeObjectForKey:MPMediaItemPropertyArtist];
		if (withExtras[MPMediaItemPropertyAlbumTitle]) withExtras[MPMediaItemPropertyAlbumTitle] = @"";
	}

	extras[MenzenExtrasCoverKey] = entity[@"cover"];
	extras[MenzenExtrasTitleURLKey] = MenzenLinkURL(@"https://www.hulu.com/watch/%@", contentID);
	return extras;
}

%ctor {
	entities = [[MenzenCache alloc] initWithLimit:2000];
	MenzenProviderCheck(@[], @[]);
	MenzenAddExtras(MenzenExtras);
	MenzenObserveResponses(^BOOL(NSURL *url) {
		return [url.host.lowercaseString isEqualToString:@"discover.hulu.com"] && [url.path hasPrefix:@"/content/"];
	}, ^(NSURL *url, NSData *body) {
		MenzenRemember(body);
	});
}
