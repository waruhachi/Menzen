#import "../../Shared/MenzenProvider/MenzenProvider.h"
#import "../../Shared/MenzenProvider/MenzenResponses.h"

// The app publishes no IDs. Tracks and artist pictures come from the API,
// which the app calls through Swift's async URLSession API, matched by title
// and album.

@interface MenzenQobuzTrack : NSObject
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *extras;
@property (nonatomic, copy) NSString *artistID;
@end

@implementation MenzenQobuzTrack
@end

// By title and album.
static NSMutableDictionary<NSString *, MenzenQobuzTrack *> *tracks;
static NSMutableDictionary<NSString *, NSString *> *pictures;

// Only what the API answers about the catalog; never stream URLs (file/) or
// the account (user/).
static BOOL MenzenIsCatalog(NSURL *url) {
	if (![url.scheme isEqualToString:@"https"] || ![url.host.lowercaseString isEqualToString:@"www.qobuz.com"]) return NO;
	NSString *path = url.path;
	if (![path hasPrefix:@"/api.json/0.2/"]) return NO;
	NSString *method = [path substringFromIndex:@"/api.json/0.2/".length];
	for (NSString *prefix in @[@"track/get", @"album/", @"artist/", @"playlist/", @"favorite/", @"catalog/", @"dynamic/", @"discover/"]) {
		if ([method hasPrefix:prefix]) return YES;
	}

	return NO;
}

static NSString *MenzenQobuzImageURL(id value) {
	return MenzenImageURL(value, @[@"static.qobuz.com"]);
}

static NSString *MenzenArtistImageURL(id value) {
	NSString *url = MenzenQobuzImageURL(value);
	return [url hasPrefix:@"https://static.qobuz.com/images/artists/"] ? url : nil;
}

// An artist's picture: image (sized URLs), picture (a URL), or
// images.portrait (a hash). Playlists and labels have IDs, names and images
// too, but not in images/artists/.
static NSString *MenzenPicture(NSDictionary *artist) {
	NSDictionary *image = MenzenDictionary(artist[@"image"]);
	for (NSString *size in @[@"extralarge", @"large", @"mega", @"medium"]) {
		NSString *url = MenzenArtistImageURL(image[size]);
		if (url) return url;
	}

	NSString *picture = MenzenArtistImageURL(artist[@"picture"]);
	if (picture) return picture;
	NSDictionary *portrait = MenzenDictionary(MenzenDictionary(artist[@"images"])[@"portrait"]);
	NSString *hash = MenzenString(portrait[@"hash"]);
	NSString *format = MenzenString(portrait[@"format"]) ?: @"jpg";
	NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefghijklmnopqrstuvwxyz"].invertedSet;
	if (hash.length && hash.length <= 64 && [hash rangeOfCharacterFromSet:invalid].location == NSNotFound && [format rangeOfCharacterFromSet:invalid].location == NSNotFound) {
		return [NSString stringWithFormat:@"https://static.qobuz.com/images/artists/covers/large/%@.%@", hash, format];
	}

	return nil;
}

static void MenzenRememberTrack(NSDictionary *track) {
	NSString *title = MenzenString(track[@"title"]);
	NSDictionary *album = MenzenDictionary(track[@"album"]);
	NSString *albumTitle = MenzenString(album[@"title"]);
	NSString *trackID = MenzenString(track[@"id"]);
	if (!title || !albumTitle || !trackID) return;
	// Artist pages give tracks an artist, named as name.display, in place of
	// a performer.
	NSDictionary *performer = MenzenDictionary(track[@"performer"]) ?: MenzenDictionary(track[@"artist"]) ?: MenzenDictionary(album[@"artist"]);
	NSString *artistID = MenzenString(performer[@"id"]);
	NSString *artistName = MenzenString(performer[@"name"]) ?: MenzenString(MenzenDictionary(performer[@"name"])[@"display"]);

	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	NSDictionary *image = MenzenDictionary(album[@"image"]);
	extras[MenzenExtrasCoverKey] = MenzenQobuzImageURL(image[@"large"]) ?: MenzenQobuzImageURL(image[@"small"]);
	extras[MenzenExtrasTitleURLKey] = MenzenLinkURL(@"https://open.qobuz.com/track/%@", trackID);
	extras[MenzenExtrasAlbumURLKey] = MenzenLinkURL(@"https://open.qobuz.com/album/%@", MenzenString(album[@"id"]));
	extras[MenzenExtrasArtistURLKey] = MenzenLinkURL(@"https://open.qobuz.com/artist/%@", artistID);
	extras[MenzenExtrasArtistNameKey] = artistName;

	MenzenQobuzTrack *remembered = [MenzenQobuzTrack new];
	remembered.extras = extras;
	remembered.artistID = artistID;
	// The app shows versions in titles: "Song (Remix)", "Album (Deluxe)".
	NSMutableArray *titles = [NSMutableArray arrayWithObject:title];
	NSString *version = MenzenString(track[@"version"]);
	if (version) [titles addObject:[NSString stringWithFormat:@"%@ (%@)", title, version]];
	NSMutableArray *albumTitles = [NSMutableArray arrayWithObject:albumTitle];
	NSString *albumVersion = MenzenString(album[@"version"]);
	if (albumVersion) [albumTitles addObject:[NSString stringWithFormat:@"%@ (%@)", albumTitle, albumVersion]];
	NSMutableArray *keys = [NSMutableArray array];
	for (NSString *t in titles) {
		for (NSString *a in albumTitles) [keys addObject:MenzenPairKey(t, a)];
	}

	@synchronized(tracks) {
		if (tracks.count > 1000) [tracks removeAllObjects];
		for (NSString *key in keys) {
			// Never lose an artist to a listing that doesn't say it.
			if (!artistID && tracks[key].artistID) continue;
			tracks[key] = remembered;
		}
	}
}

static void MenzenRemember(id object, NSUInteger depth) {
	if (depth > 10) return;
	if ([object isKindOfClass:NSArray.class]) {
		for (id item in object) MenzenRemember(item, depth + 1);
		return;
	}

	NSDictionary *dictionary = MenzenDictionary(object);
	if (!dictionary) return;
	// An artist, wherever it appears. Artist pages name them as
	// name.display.
	NSString *ID = MenzenString(dictionary[@"id"]);
	BOOL named = MenzenString(dictionary[@"name"]) || MenzenString(MenzenDictionary(dictionary[@"name"])[@"display"]);
	NSString *picture = ID && named ? MenzenPicture(dictionary) : nil;
	if (picture) {
		@synchronized(tracks) {
			if (pictures.count > 1000) [pictures removeAllObjects];
			pictures[ID] = picture;
		}
	}

	// A track: it has an album.
	if ([dictionary[@"id"] isKindOfClass:NSNumber.class] && MenzenDictionary(dictionary[@"album"])) MenzenRememberTrack(dictionary);
	// An album with its tracks, which don't repeat it.
	NSArray *items = MenzenDictionary(dictionary[@"tracks"])[@"items"];
	if ([items isKindOfClass:NSArray.class] && MenzenString(dictionary[@"title"]) && MenzenDictionary(dictionary[@"image"])) {
		NSMutableDictionary *album = [dictionary mutableCopy];
		[album removeObjectForKey:@"tracks"];
		for (id item in items) {
			NSDictionary *track = MenzenDictionary(item);
			if (!track || track[@"album"]) continue;
			NSMutableDictionary *withAlbum = [track mutableCopy];
			withAlbum[@"album"] = album;
			MenzenRememberTrack(withAlbum);
		}
	}

	for (id value in dictionary.allValues) {
		if ([value isKindOfClass:NSArray.class] || [value isKindOfClass:NSDictionary.class]) MenzenRemember(value, depth + 1);
	}
}

static NSDictionary *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	if (withExtras[MPNowPlayingInfoPropertyAssetURL]) return nil;
	NSString *key = MenzenPairKey(MenzenString(info[MPMediaItemPropertyTitle]), MenzenString(info[MPMediaItemPropertyAlbumTitle]));
	@synchronized(tracks) {
		MenzenQobuzTrack *track = key ? tracks[key] : nil;
		if (!track) return nil;
		NSMutableDictionary *extras = [track.extras mutableCopy];
		extras[MenzenExtrasArtistImageKey] = track.artistID ? pictures[track.artistID] : nil;
		return extras;
	}
}

%ctor {
	tracks = [NSMutableDictionary dictionary];
	pictures = [NSMutableDictionary dictionary];
	MenzenProviderCheck(@[@"NSURLSession -_dataTaskWithRequest:delegate:completionHandler:"], @[]);
	MenzenAddExtras(MenzenExtras);
	MenzenObserveResponses(^BOOL(NSURL *url) {
		return MenzenIsCatalog(url);
	}, ^(NSURL *url, NSData *body) {
		id object = MenzenJSON(body);
		if (object) MenzenRemember(object, 0);
	});
}
