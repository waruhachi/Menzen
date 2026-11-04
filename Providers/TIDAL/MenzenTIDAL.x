#import "../../Shared/MenzenProvider/MenzenProvider.h"
#import "../../Shared/MenzenProvider/MenzenResponses.h"

// The app publishes no IDs. Before playing a track it loads it from the API
// with albums.coverArt included; the request is changed to also include the
// artists' pictures, and the answer is matched by title and album.

// By title and album.
static MenzenCache<NSString *, NSDictionary *> *items;

static BOOL MenzenIsTrack(NSURL *url) {
	if (![url.scheme isEqualToString:@"https"] || ![url.host.lowercaseString isEqualToString:@"openapi.tidal.com"]) return NO;
	NSArray *components = url.path.pathComponents;
	return components.count == 4 && [components[1] isEqualToString:@"v2"] && [components[2] isEqualToString:@"tracks"];
}

// url with artists.profileArt added to its include when it includes the
// album's cover; nil when it doesn't.
static NSURL *MenzenWithArtists(NSURL *url) {
	NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
	NSMutableArray<NSURLQueryItem *> *query = [components.queryItems mutableCopy];
	for (NSUInteger i = 0; i < query.count; i++) {
		NSURLQueryItem *item = query[i];
		if (![item.name isEqualToString:@"include"]) continue;
		NSArray *included = [item.value componentsSeparatedByString:@","];
		if (![included containsObject:@"albums.coverArt"]) return nil;
		if ([included containsObject:@"artists.profileArt"]) return url;
		query[i] = [NSURLQueryItem queryItemWithName:@"include" value:[item.value stringByAppendingString:@",artists.profileArt"]];
		components.queryItems = query;
		return components.URL;
	}

	return nil;
}

static NSArray<NSString *> *MenzenRelated(NSDictionary *resource, NSString *relationship) {
	NSArray *data = MenzenDictionary(MenzenDictionary(MenzenDictionary(resource[@"relationships"])[relationship]))[@"data"];
	if (![data isKindOfClass:NSArray.class]) return @[];
	NSMutableArray *IDs = [NSMutableArray array];
	for (id reference in data) {
		NSString *ID = MenzenString(MenzenDictionary(reference)[@"id"]);
		if (ID) [IDs addObject:ID];
	}

	return IDs;
}

// The smallest of an artwork's files at least 600 wide, else the widest.
static NSString *MenzenImage(NSDictionary *artwork) {
	NSArray *files = MenzenDictionary(artwork[@"attributes"])[@"files"];
	if (![files isKindOfClass:NSArray.class]) return nil;
	NSString *found = nil;
	double foundWidth = 0;
	for (id file in files) {
		NSString *href = MenzenString(MenzenDictionary(file)[@"href"]);
		id width = MenzenDictionary(MenzenDictionary(file)[@"meta"])[@"width"];
		if (![href hasPrefix:@"https://resources.tidal.com/"] || href.length > 256 || ![width isKindOfClass:NSNumber.class]) continue;
		double w = [width doubleValue];
		BOOL better = !found || (foundWidth < 600 ? w > foundWidth : w >= 600 && w < foundWidth);
		if (better) {
			found = href;
			foundWidth = w;
		}
	}

	return found;
}

static void MenzenRemember(NSDictionary *document) {
	NSMutableDictionary<NSString *, NSDictionary *> *included = [NSMutableDictionary dictionary];
	NSArray *resources = document[@"included"];
	if ([resources isKindOfClass:NSArray.class]) {
		for (id resource in resources) {
			NSString *type = MenzenString(MenzenDictionary(resource)[@"type"]);
			NSString *ID = MenzenString(MenzenDictionary(resource)[@"id"]);
			if (type && ID) included[[NSString stringWithFormat:@"%@/%@", type, ID]] = resource;
		}
	}

	NSDictionary *track = MenzenDictionary(document[@"data"]);
	NSString *trackID = MenzenString(track[@"id"]);
	NSDictionary *attributes = MenzenDictionary(track[@"attributes"]);
	NSString *title = MenzenString(attributes[@"title"]);
	if (![MenzenString(track[@"type"]) isEqualToString:@"tracks"] || !title) return;

	NSString *albumID = MenzenRelated(track, @"albums").firstObject;
	NSDictionary *album = albumID ? included[[@"albums/" stringByAppendingString:albumID]] : nil;
	NSString *albumTitle = MenzenString(MenzenDictionary(album[@"attributes"])[@"title"]);
	NSString *coverID = MenzenRelated(album, @"coverArt").firstObject;
	NSString *artistID = MenzenRelated(track, @"artists").firstObject;
	NSDictionary *artist = artistID ? included[[@"artists/" stringByAppendingString:artistID]] : nil;
	NSString *pictureID = MenzenRelated(artist, @"profileArt").firstObject;

	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	extras[MenzenExtrasCoverKey] = coverID ? MenzenImage(included[[@"artworks/" stringByAppendingString:coverID]]) : nil;
	extras[MenzenExtrasArtistImageKey] = pictureID ? MenzenImage(included[[@"artworks/" stringByAppendingString:pictureID]]) : nil;
	extras[MenzenExtrasArtistNameKey] = MenzenString(MenzenDictionary(artist[@"attributes"])[@"name"]);
	extras[MenzenExtrasTitleURLKey] = MenzenLinkURL(@"https://tidal.com/browse/track/%@", trackID);
	extras[MenzenExtrasAlbumURLKey] = MenzenLinkURL(@"https://tidal.com/browse/album/%@", albumID);
	extras[MenzenExtrasArtistURLKey] = MenzenLinkURL(@"https://tidal.com/browse/artist/%@", artistID);
	if (!albumTitle || !extras.count) return;

	items[MenzenPairKey(title, albumTitle)] = extras;
	// The app may show the version in the title: "Song (Remix)".
	NSString *version = MenzenString(attributes[@"version"]);
	if (version) items[MenzenPairKey([NSString stringWithFormat:@"%@ (%@)", title, version], albumTitle)] = extras;
}

static NSDictionary *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	if (withExtras[MPNowPlayingInfoPropertyAssetURL]) return nil;
	NSString *key = MenzenPairKey(MenzenString(info[MPMediaItemPropertyTitle]), MenzenString(info[MPMediaItemPropertyAlbumTitle]));
	return key ? items[key] : nil;
}

%ctor {
	items = [[MenzenCache alloc] initWithLimit:2000];
	MenzenProviderCheck(@[], @[]);
	MenzenAddExtras(MenzenExtras);
	MenzenModifyRequests(^NSURLRequest *(NSURLRequest *request) {
		NSURL *url = MenzenIsTrack(request.URL) ? MenzenWithArtists(request.URL) : nil;
		if (!url || [url isEqual:request.URL]) return request;
		NSMutableURLRequest *withArtists = [request mutableCopy];
		withArtists.URL = url;
		return withArtists;
	});
	MenzenObserveResponses(^BOOL(NSURL *url) {
		return MenzenIsTrack(url);
	}, ^(NSURL *url, NSData *body) {
		NSDictionary *document = MenzenDictionary(MenzenJSON(body));
		if (document) MenzenRemember(document);
	});
}
