#import <objc/runtime.h>

#import "../../Shared/MZProvider/MZProvider.h"
#import "../../Shared/MZProvider/MZResponses.h"

// The app publishes no IDs. The playing track's row (AMPersistentEntity's
// _objectDictionary) has its ASINs, and the album's cover URL comes from
// -imageURLForRequest: as the app draws it.
//
// Artist pictures come from the app's GraphQL API: the app's latest request
// there is kept as a template for asking about the playing artist.
//
// Podcasts play in another player, driven by the podcast API's
// SetEMPMediaMetadataMethod answers, matched by episode title and show.

static MZCache<NSString *, NSString *> *covers;
static MZCache<NSString *, NSDictionary *> *episodes;

// Main thread only. NSNull for an artist without a picture.
static NSMutableDictionary<NSString *, id> *artistPictures;
static NSMutableSet<NSString *> *artistPicturesLoading;

// Guarded by graphQLLock.
static NSURLRequest *graphQLRequest;
static NSObject *graphQLLock;

static Class entityClass;
static BOOL entityHasRow;

static NSDictionary *MZRow(id entity);

static NSString *MZAmazonImageURL(id value) {
	NSString *url = MZImageURL(value, @[@"m.media-amazon.com"]);
	return url && ![url containsString:@"?"] ? url : nil;
}

static BOOL MZIsPodcastAPI(NSURL *url) {
	return [url.scheme isEqualToString:@"https"] && [url.host.lowercaseString isEqualToString:@"music.amazon.com"] && [url.path containsString:@"/api/podcast/"];
}

static void MZRememberEpisode(NSDictionary *metadata) {
	NSString *title = MZString(metadata[@"trackName"]);
	NSString *show = MZString(metadata[@"artist"]) ?: MZString(metadata[@"playbackSource"]);
	NSString *key = MZPairKey(title, show);
	if (!key) return;
	NSString *showID = MZLinkURL(@"%@", metadata[@"artistId"]);
	NSString *episodeID = MZLinkURL(@"%@", metadata[@"trackId"]);
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	extras[MZExtrasCoverKey] = MZAmazonImageURL(metadata[@"coverId"]);
	if (showID) {
		// The app publishes the show as the album.
		extras[MZExtrasAlbumURLKey] = [@"https://music.amazon.com/podcasts/" stringByAppendingString:showID];
		if (episodeID) extras[MZExtrasTitleURLKey] = [NSString stringWithFormat:@"https://music.amazon.com/podcasts/%@/episodes/%@", showID, episodeID];
	}

	if (extras.count) episodes[key] = extras;
}

static void MZRemember(id object, NSUInteger depth) {
	if (depth > 12) return;
	if ([object isKindOfClass:NSArray.class]) {
		for (id item in object) MZRemember(item, depth + 1);
		return;
	}

	if (![object isKindOfClass:NSDictionary.class]) return;
	NSDictionary *dictionary = object;
	if ([MZString(dictionary[@"__type"]) hasSuffix:@"#SetEMPMediaMetadataMethod"] && [dictionary[@"metadata"] isKindOfClass:NSDictionary.class]) MZRememberEpisode(dictionary[@"metadata"]);
	for (id value in dictionary.allValues) {
		if ([value isKindOfClass:NSArray.class] || [value isKindOfClass:NSDictionary.class]) MZRemember(value, depth + 1);
	}
}

static BOOL MZIsGraphQL(NSURL *url) {
	return [url.scheme isEqualToString:@"https"] && [url.host.lowercaseString isEqualToString:@"gql.music.amazon.dev"];
}

// The smallest profile picture at least 500 wide, else the widest; else the
// banner, the same way.
static NSString *MZArtistPicture(NSArray *images) {
	if (![images isKindOfClass:NSArray.class]) return nil;
	for (NSString *type in @[@"PROFILE", @"BACKGROUND"]) {
		NSString *found = nil;
		double foundWidth = 0;
		for (NSDictionary *image in images) {
			if (![image isKindOfClass:NSDictionary.class] || ![MZString(image[@"imageType"]) isEqualToString:type]) continue;
			NSString *url = MZAmazonImageURL(image[@"url"]);
			double width = [image[@"width"] isKindOfClass:NSNumber.class] ? [image[@"width"] doubleValue] : 0;
			BOOL better = !found || (foundWidth < 500 ? width > foundWidth : width >= 500 && width < foundWidth);
			if (url && better) {
				found = url;
				foundWidth = width;
			}
		}
		if (found) return found;
	}

	return nil;
}

static void MZLoadArtistPicture(NSString *artistASIN) {
	NSMutableURLRequest *request;
	@synchronized(graphQLLock) {
		request = [graphQLRequest mutableCopy];
	}

	if (!request || [artistPicturesLoading containsObject:artistASIN]) return;
	NSDictionary *body = @{
		@"operationName": @"ArtistImages",
		@"variables": @{@"id": artistASIN},
		@"query": @"query ArtistImages($id: String!) { artist(id: $id) { __typename id images { __typename url width imageType } } }",
	};
	request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
	[request setValue:nil forHTTPHeaderField:@"Content-Length"];
	[NSURLProtocol setProperty:@YES forKey:@"moe.waru.menzen" inRequest:request];
	[artistPicturesLoading addObject:artistASIN];
	[[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
		NSDictionary *document = !error && status == 200 && data.length <= 1024 * 1024 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
		NSDictionary *artist = [document isKindOfClass:NSDictionary.class] && [document[@"data"] isKindOfClass:NSDictionary.class] ? document[@"data"][@"artist"] : nil;
		BOOL answered = [artist isKindOfClass:NSDictionary.class] && [MZString(artist[@"id"]) isEqualToString:artistASIN];
		NSString *picture = answered ? MZArtistPicture(artist[@"images"]) : nil;
		dispatch_async(dispatch_get_main_queue(), ^{
			[artistPicturesLoading removeObject:artistASIN];
			// No answer: a later update asks again.
			if (!answered) return;
			if (artistPictures.count > 1000) [artistPictures removeAllObjects];
			artistPictures[artistASIN] = picture ?: (id)NSNull.null;
			if (picture) MZRepublish();
		});
	}] resume];
}

static NSDictionary *MZEpisodeExtras(NSDictionary *info) {
	NSString *key = MZPairKey(MZString(info[MPMediaItemPropertyTitle]), MZString(info[MPMediaItemPropertyAlbumTitle]));
	return key ? episodes[key] : nil;
}

static NSDictionary *MZTrackExtras(NSDictionary *info) {
	id track = MZGet(MZGet(%c(AMPlayer), @"sharedPlayer"), @"currentTrack");
	NSDictionary *row = MZRow(track);
	// Only the playing track's; else an episode's.
	NSString *title = MZString(row[@"name"]);
	if (!title || ![title isEqualToString:MZString(info[MPMediaItemPropertyTitle])]) return MZEpisodeExtras(info);

	NSString *trackASIN = MZLinkURL(@"%@", row[@"asin"]);
	NSString *albumASIN = MZLinkURL(@"%@", row[@"albumASIN"]);
	NSString *artistASIN = MZLinkURL(@"%@", row[@"trackArtistASIN"]) ?: MZLinkURL(@"%@", row[@"albumArtistASIN"]);
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	if (albumASIN) {
		extras[MZExtrasCoverKey] = covers[albumASIN];
		extras[MZExtrasAlbumURLKey] = [@"https://music.amazon.com/albums/" stringByAppendingString:albumASIN];
		if (trackASIN) extras[MZExtrasTitleURLKey] = [NSString stringWithFormat:@"https://music.amazon.com/albums/%@?trackAsin=%@", albumASIN, trackASIN];
	}

	if (artistASIN) {
		extras[MZExtrasArtistURLKey] = [@"https://music.amazon.com/artists/" stringByAppendingString:artistASIN];
		extras[MZExtrasArtistNameKey] = MZString(row[@"trackArtistName"]);
		id picture = artistPictures[artistASIN];
		if ([picture isKindOfClass:NSString.class]) extras[MZExtrasArtistImageKey] = picture;
		else if (!picture) MZLoadArtistPicture(artistASIN);
	}

	return extras;
}

%hook AMPersistedAlbum

- (NSURL *)imageURLForRequest:(id)request {
	NSURL *url = %orig;
	NSString *asin = MZLinkURL(@"%@", MZRow(self)[@"asin"]);
	NSString *cover = MZAmazonImageURL(url);
	if (asin && cover) covers[asin] = cover;
	return url;
}

%end

// Read from the ivar: the entity's methods expect the app's own threads and
// state.
static NSDictionary *MZRow(id entity) {
	if (!entityHasRow || ![entity isKindOfClass:entityClass]) return nil;
	id row = MSHookIvar<id>(entity, "_objectDictionary");
	return [row isKindOfClass:NSDictionary.class] ? row : nil;
}

static NSDictionary<NSString *, NSString *> *MZExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	if (withExtras[MPNowPlayingInfoPropertyAssetURL]) return nil;
	// The player belongs to the main thread, where the app publishes tracks.
	return NSThread.isMainThread ? MZTrackExtras(info) : MZEpisodeExtras(info);
}

%ctor {
	entityClass = %c(AMPersistentEntity);
	// MSHookIvar can't tell a missing ivar, so it's checked once here.
	Ivar ivar = entityClass ? class_getInstanceVariable(entityClass, "_objectDictionary") : NULL;
	const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
	entityHasRow = type && type[0] == '@';

	covers = [[MZCache alloc] initWithLimit:2000];
	episodes = [[MZCache alloc] initWithLimit:2000];
	artistPictures = [NSMutableDictionary dictionary];
	artistPicturesLoading = [NSMutableSet set];
	graphQLLock = [NSObject new];
	MZProviderCheck(@[
		@"AMPlayer +sharedPlayer",
		@"AMPlayer -currentTrack",
		@"AMPersistentEntity _objectDictionary",
		@"AMPersistedAlbum -imageURLForRequest:",
	], @[]);
	MZAddExtras(MZExtras);
	MZModifyRequests(^NSURLRequest *(NSURLRequest *request) {
		if (MZIsGraphQL(request.URL) && [request.HTTPMethod isEqualToString:@"POST"] && ![NSURLProtocol propertyForKey:@"moe.waru.menzen" inRequest:request]) {
			@synchronized(graphQLLock) {
				graphQLRequest = [request copy];
			}
		}
		return request;
	});
	MZObserveResponses(^BOOL(NSURL *url) {
		return MZIsPodcastAPI(url);
	}, ^(NSURL *url, NSData *body) {
		id object = MZJSON(body);
		if (object) MZRemember(object, 0);
	});
	%init;
}
