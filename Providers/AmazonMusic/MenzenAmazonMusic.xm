#import <objc/runtime.h>

#import "../../Shared/MenzenProvider/MenzenProvider.h"
#import "../../Shared/MenzenProvider/MenzenResponses.h"

// The app publishes no IDs. The playing track's row (AMPersistentEntity's
// _objectDictionary) has its ASINs, and the album's cover URL comes from
// -imageURLForRequest: as the app draws it.
//
// Artist pictures come from the app's GraphQL API: the app's latest request
// there is kept as a template for asking about the playing artist.
//
// Podcasts play in another player, driven by the podcast API's
// SetEMPMediaMetadataMethod answers, matched by episode title and show.

static MenzenCache<NSString *, NSString *> *covers;
static MenzenCache<NSString *, NSDictionary *> *episodes;

// Main thread only. NSNull for an artist without a picture.
static NSMutableDictionary<NSString *, id> *artistPictures;
static NSMutableSet<NSString *> *artistPicturesLoading;

// Guarded by graphQLLock.
static NSURLRequest *graphQLRequest;
static NSObject *graphQLLock;

static Class entityClass;
static BOOL entityHasRow;

static NSDictionary *MenzenRow(id entity);

static NSString *MenzenAmazonImageURL(id value) {
	NSString *url = MenzenImageURL(value, @[@"m.media-amazon.com"]);
	return url && ![url containsString:@"?"] ? url : nil;
}

static BOOL MenzenIsPodcastAPI(NSURL *url) {
	return [url.scheme isEqualToString:@"https"] && [url.host.lowercaseString isEqualToString:@"music.amazon.com"] && [url.path containsString:@"/api/podcast/"];
}

static void MenzenRememberEpisode(NSDictionary *metadata) {
	NSString *title = MenzenString(metadata[@"trackName"]);
	NSString *show = MenzenString(metadata[@"artist"]) ?: MenzenString(metadata[@"playbackSource"]);
	NSString *key = MenzenPairKey(title, show);
	if (!key) return;
	NSString *showID = MenzenLinkURL(@"%@", metadata[@"artistId"]);
	NSString *episodeID = MenzenLinkURL(@"%@", metadata[@"trackId"]);
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	extras[MenzenExtrasCoverKey] = MenzenAmazonImageURL(metadata[@"coverId"]);
	if (showID) {
		// The app publishes the show as the album.
		extras[MenzenExtrasAlbumURLKey] = [@"https://music.amazon.com/podcasts/" stringByAppendingString:showID];
		if (episodeID) extras[MenzenExtrasTitleURLKey] = [NSString stringWithFormat:@"https://music.amazon.com/podcasts/%@/episodes/%@", showID, episodeID];
	}

	if (extras.count) episodes[key] = extras;
}

static void MenzenRemember(id object, NSUInteger depth) {
	if (depth > 12) return;
	if ([object isKindOfClass:NSArray.class]) {
		for (id item in object) MenzenRemember(item, depth + 1);
		return;
	}

	if (![object isKindOfClass:NSDictionary.class]) return;
	NSDictionary *dictionary = object;
	if ([MenzenString(dictionary[@"__type"]) hasSuffix:@"#SetEMPMediaMetadataMethod"] && [dictionary[@"metadata"] isKindOfClass:NSDictionary.class]) MenzenRememberEpisode(dictionary[@"metadata"]);
	for (id value in dictionary.allValues) {
		if ([value isKindOfClass:NSArray.class] || [value isKindOfClass:NSDictionary.class]) MenzenRemember(value, depth + 1);
	}
}

static BOOL MenzenIsGraphQL(NSURL *url) {
	return [url.scheme isEqualToString:@"https"] && [url.host.lowercaseString isEqualToString:@"gql.music.amazon.dev"];
}

// The smallest profile picture at least 500 wide, else the widest; else the
// banner, the same way.
static NSString *MenzenArtistPicture(NSArray *images) {
	if (![images isKindOfClass:NSArray.class]) return nil;
	for (NSString *type in @[@"PROFILE", @"BACKGROUND"]) {
		NSString *found = nil;
		double foundWidth = 0;
		for (NSDictionary *image in images) {
			if (![image isKindOfClass:NSDictionary.class] || ![MenzenString(image[@"imageType"]) isEqualToString:type]) continue;
			NSString *url = MenzenAmazonImageURL(image[@"url"]);
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

static void MenzenLoadArtistPicture(NSString *artistASIN) {
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
		BOOL answered = [artist isKindOfClass:NSDictionary.class] && [MenzenString(artist[@"id"]) isEqualToString:artistASIN];
		NSString *picture = answered ? MenzenArtistPicture(artist[@"images"]) : nil;
		dispatch_async(dispatch_get_main_queue(), ^{
			[artistPicturesLoading removeObject:artistASIN];
			// No answer: a later update asks again.
			if (!answered) return;
			if (artistPictures.count > 1000) [artistPictures removeAllObjects];
			artistPictures[artistASIN] = picture ?: (id)NSNull.null;
			if (picture) MenzenRepublish();
		});
	}] resume];
}

static NSDictionary *MenzenEpisodeExtras(NSDictionary *info) {
	NSString *key = MenzenPairKey(MenzenString(info[MPMediaItemPropertyTitle]), MenzenString(info[MPMediaItemPropertyAlbumTitle]));
	return key ? episodes[key] : nil;
}

static NSDictionary *MenzenTrackExtras(NSDictionary *info) {
	id track = MenzenGet(MenzenGet(%c(AMPlayer), @"sharedPlayer"), @"currentTrack");
	NSDictionary *row = MenzenRow(track);
	// Only the playing track's; else an episode's.
	NSString *title = MenzenString(row[@"name"]);
	if (!title || ![title isEqualToString:MenzenString(info[MPMediaItemPropertyTitle])]) return MenzenEpisodeExtras(info);

	NSString *trackASIN = MenzenLinkURL(@"%@", row[@"asin"]);
	NSString *albumASIN = MenzenLinkURL(@"%@", row[@"albumASIN"]);
	NSString *artistASIN = MenzenLinkURL(@"%@", row[@"trackArtistASIN"]) ?: MenzenLinkURL(@"%@", row[@"albumArtistASIN"]);
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	if (albumASIN) {
		extras[MenzenExtrasCoverKey] = covers[albumASIN];
		extras[MenzenExtrasAlbumURLKey] = [@"https://music.amazon.com/albums/" stringByAppendingString:albumASIN];
		if (trackASIN) extras[MenzenExtrasTitleURLKey] = [NSString stringWithFormat:@"https://music.amazon.com/albums/%@?trackAsin=%@", albumASIN, trackASIN];
	}

	if (artistASIN) {
		extras[MenzenExtrasArtistURLKey] = [@"https://music.amazon.com/artists/" stringByAppendingString:artistASIN];
		extras[MenzenExtrasArtistNameKey] = MenzenString(row[@"trackArtistName"]);
		id picture = artistPictures[artistASIN];
		if ([picture isKindOfClass:NSString.class]) extras[MenzenExtrasArtistImageKey] = picture;
		else if (!picture) MenzenLoadArtistPicture(artistASIN);
	}

	return extras;
}

%hook AMPersistedAlbum

- (NSURL *)imageURLForRequest:(id)request {
	NSURL *url = %orig;
	NSString *asin = MenzenLinkURL(@"%@", MenzenRow(self)[@"asin"]);
	NSString *cover = MenzenAmazonImageURL(url);
	if (asin && cover) covers[asin] = cover;
	return url;
}

%end

// Read from the ivar: the entity's methods expect the app's own threads and
// state.
static NSDictionary *MenzenRow(id entity) {
	if (!entityHasRow || ![entity isKindOfClass:entityClass]) return nil;
	id row = MSHookIvar<id>(entity, "_objectDictionary");
	return [row isKindOfClass:NSDictionary.class] ? row : nil;
}

static NSDictionary<NSString *, NSString *> *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	if (withExtras[MPNowPlayingInfoPropertyAssetURL]) return nil;
	// The player belongs to the main thread, where the app publishes tracks.
	return NSThread.isMainThread ? MenzenTrackExtras(info) : MenzenEpisodeExtras(info);
}

%ctor {
	entityClass = %c(AMPersistentEntity);
	// MSHookIvar can't tell a missing ivar, so it's checked once here.
	Ivar ivar = entityClass ? class_getInstanceVariable(entityClass, "_objectDictionary") : NULL;
	const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
	entityHasRow = type && type[0] == '@';

	covers = [[MenzenCache alloc] initWithLimit:2000];
	episodes = [[MenzenCache alloc] initWithLimit:2000];
	artistPictures = [NSMutableDictionary dictionary];
	artistPicturesLoading = [NSMutableSet set];
	graphQLLock = [NSObject new];
	MenzenProviderCheck(@[
		@"AMPlayer +sharedPlayer",
		@"AMPlayer -currentTrack",
		@"AMPersistentEntity _objectDictionary",
		@"AMPersistedAlbum -imageURLForRequest:",
	], @[]);
	MenzenAddExtras(MenzenExtras);
	MenzenModifyRequests(^NSURLRequest *(NSURLRequest *request) {
		if (MenzenIsGraphQL(request.URL) && [request.HTTPMethod isEqualToString:@"POST"] && ![NSURLProtocol propertyForKey:@"moe.waru.menzen" inRequest:request]) {
			@synchronized(graphQLLock) {
				graphQLRequest = [request copy];
			}
		}
		return request;
	});
	MenzenObserveResponses(^BOOL(NSURL *url) {
		return MenzenIsPodcastAPI(url);
	}, ^(NSURL *url, NSData *body) {
		id object = MenzenJSON(body);
		if (object) MenzenRemember(object, 0);
	});
	%init;
}
