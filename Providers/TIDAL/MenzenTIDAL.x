#import "../../Shared/MZProvider/MZProvider.h"
#import "../../Shared/MZProvider/MZResponses.h"

// The app publishes no IDs. Before playing a track it loads it from the API
// with albums.coverArt included; the request is changed to also include the
// artists' pictures, and the answer is matched by title and album.

// By title and album.
static MZCache<NSString *, NSDictionary *> *items;

static BOOL MZIsTrack(NSURL *url) {
	if (![url.scheme isEqualToString:@"https"] || ![url.host.lowercaseString isEqualToString:@"openapi.tidal.com"]) return NO;
	NSArray *components = url.path.pathComponents;
	return components.count == 4 && [components[1] isEqualToString:@"v2"] && [components[2] isEqualToString:@"tracks"];
}

// url with artists.profileArt added to its include when it includes the
// album's cover; nil when it doesn't.
static NSURL *MZWithArtists(NSURL *url) {
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

static NSArray<NSString *> *MZRelated(NSDictionary *resource, NSString *relationship) {
	NSArray *data = MZDictionary(MZDictionary(MZDictionary(resource[@"relationships"])[relationship]))[@"data"];
	if (![data isKindOfClass:NSArray.class]) return @[];
	NSMutableArray *IDs = [NSMutableArray array];
	for (id reference in data) {
		NSString *ID = MZString(MZDictionary(reference)[@"id"]);
		if (ID) [IDs addObject:ID];
	}

	return IDs;
}

// The smallest of an artwork's files at least 600 wide, else the widest.
static NSString *MZImage(NSDictionary *artwork) {
	NSArray *files = MZDictionary(artwork[@"attributes"])[@"files"];
	if (![files isKindOfClass:NSArray.class]) return nil;
	NSString *found = nil;
	double foundWidth = 0;
	for (id file in files) {
		NSString *href = MZString(MZDictionary(file)[@"href"]);
		id width = MZDictionary(MZDictionary(file)[@"meta"])[@"width"];
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

static void MZRemember(NSDictionary *document) {
	NSMutableDictionary<NSString *, NSDictionary *> *included = [NSMutableDictionary dictionary];
	NSArray *resources = document[@"included"];
	if ([resources isKindOfClass:NSArray.class]) {
		for (id resource in resources) {
			NSString *type = MZString(MZDictionary(resource)[@"type"]);
			NSString *ID = MZString(MZDictionary(resource)[@"id"]);
			if (type && ID) included[[NSString stringWithFormat:@"%@/%@", type, ID]] = resource;
		}
	}

	NSDictionary *track = MZDictionary(document[@"data"]);
	NSString *trackID = MZString(track[@"id"]);
	NSDictionary *attributes = MZDictionary(track[@"attributes"]);
	NSString *title = MZString(attributes[@"title"]);
	if (![MZString(track[@"type"]) isEqualToString:@"tracks"] || !title) return;

	NSString *albumID = MZRelated(track, @"albums").firstObject;
	NSDictionary *album = albumID ? included[[@"albums/" stringByAppendingString:albumID]] : nil;
	NSString *albumTitle = MZString(MZDictionary(album[@"attributes"])[@"title"]);
	NSString *coverID = MZRelated(album, @"coverArt").firstObject;
	NSString *artistID = MZRelated(track, @"artists").firstObject;
	NSDictionary *artist = artistID ? included[[@"artists/" stringByAppendingString:artistID]] : nil;
	NSString *pictureID = MZRelated(artist, @"profileArt").firstObject;

	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	extras[MZExtrasCoverKey] = coverID ? MZImage(included[[@"artworks/" stringByAppendingString:coverID]]) : nil;
	extras[MZExtrasArtistImageKey] = pictureID ? MZImage(included[[@"artworks/" stringByAppendingString:pictureID]]) : nil;
	extras[MZExtrasArtistNameKey] = MZString(MZDictionary(artist[@"attributes"])[@"name"]);
	extras[MZExtrasTitleURLKey] = MZLinkURL(@"https://tidal.com/browse/track/%@", trackID);
	extras[MZExtrasAlbumURLKey] = MZLinkURL(@"https://tidal.com/browse/album/%@", albumID);
	extras[MZExtrasArtistURLKey] = MZLinkURL(@"https://tidal.com/browse/artist/%@", artistID);
	if (!albumTitle || !extras.count) return;

	items[MZPairKey(title, albumTitle)] = extras;
	// The app may show the version in the title: "Song (Remix)".
	NSString *version = MZString(attributes[@"version"]);
	if (version) items[MZPairKey([NSString stringWithFormat:@"%@ (%@)", title, version], albumTitle)] = extras;
}

static NSDictionary *MZExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	if (withExtras[MPNowPlayingInfoPropertyAssetURL]) return nil;
	NSString *key = MZPairKey(MZString(info[MPMediaItemPropertyTitle]), MZString(info[MPMediaItemPropertyAlbumTitle]));
	return key ? items[key] : nil;
}

%ctor {
	items = [[MZCache alloc] initWithLimit:2000];
	MZProviderCheck(@[], @[]);
	MZAddExtras(MZExtras);
	MZModifyRequests(^NSURLRequest *(NSURLRequest *request) {
		NSURL *url = MZIsTrack(request.URL) ? MZWithArtists(request.URL) : nil;
		if (!url || [url isEqual:request.URL]) return request;
		NSMutableURLRequest *withArtists = [request mutableCopy];
		withArtists.URL = url;
		return withArtists;
	});
	MZObserveResponses(^BOOL(NSURL *url) {
		return MZIsTrack(url);
	}, ^(NSURL *url, NSData *body) {
		NSDictionary *document = MZDictionary(MZJSON(body));
		if (document) MZRemember(document);
	});
}
