#import "../../Shared/MZProvider/MZProvider.h"
#import "../../Shared/MZProvider/MZResponses.h"

// The app publishes no IDs. Tracks and artist pictures come from the API,
// which the app calls through Swift's async URLSession API, matched by title
// and album.

@interface MZQobuzTrack : NSObject
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *extras;
@property (nonatomic, copy) NSString *artistID;
@end

@implementation MZQobuzTrack
@end

// By title and album.
static NSMutableDictionary<NSString *, MZQobuzTrack *> *tracks;
static NSMutableDictionary<NSString *, NSString *> *pictures;

// Only what the API answers about the catalog; never stream URLs (file/) or
// the account (user/).
static BOOL MZIsCatalog(NSURL *url) {
	if (![url.scheme isEqualToString:@"https"] || ![url.host.lowercaseString isEqualToString:@"www.qobuz.com"]) return NO;
	NSString *path = url.path;
	if (![path hasPrefix:@"/api.json/0.2/"]) return NO;
	NSString *method = [path substringFromIndex:@"/api.json/0.2/".length];
	for (NSString *prefix in @[@"track/get", @"album/", @"artist/", @"playlist/", @"favorite/", @"catalog/", @"dynamic/", @"discover/"]) {
		if ([method hasPrefix:prefix]) return YES;
	}

	return NO;
}

static NSString *MZQobuzImageURL(id value) {
	return MZImageURL(value, @[@"static.qobuz.com"]);
}

static NSString *MZArtistImageURL(id value) {
	NSString *url = MZQobuzImageURL(value);
	return [url hasPrefix:@"https://static.qobuz.com/images/artists/"] ? url : nil;
}

// An artist's picture: image (sized URLs), picture (a URL), or
// images.portrait (a hash). Playlists and labels have IDs, names and images
// too, but not in images/artists/.
static NSString *MZPicture(NSDictionary *artist) {
	NSDictionary *image = MZDictionary(artist[@"image"]);
	for (NSString *size in @[@"extralarge", @"large", @"mega", @"medium"]) {
		NSString *url = MZArtistImageURL(image[size]);
		if (url) return url;
	}

	NSString *picture = MZArtistImageURL(artist[@"picture"]);
	if (picture) return picture;
	NSDictionary *portrait = MZDictionary(MZDictionary(artist[@"images"])[@"portrait"]);
	NSString *hash = MZString(portrait[@"hash"]);
	NSString *format = MZString(portrait[@"format"]) ?: @"jpg";
	NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefghijklmnopqrstuvwxyz"].invertedSet;
	if (hash.length && hash.length <= 64 && [hash rangeOfCharacterFromSet:invalid].location == NSNotFound && [format rangeOfCharacterFromSet:invalid].location == NSNotFound) {
		return [NSString stringWithFormat:@"https://static.qobuz.com/images/artists/covers/large/%@.%@", hash, format];
	}

	return nil;
}

static void MZRememberTrack(NSDictionary *track) {
	NSString *title = MZString(track[@"title"]);
	NSDictionary *album = MZDictionary(track[@"album"]);
	NSString *albumTitle = MZString(album[@"title"]);
	NSString *trackID = MZString(track[@"id"]);
	if (!title || !albumTitle || !trackID) return;
	// Artist pages give tracks an artist, named as name.display, in place of
	// a performer.
	NSDictionary *performer = MZDictionary(track[@"performer"]) ?: MZDictionary(track[@"artist"]) ?: MZDictionary(album[@"artist"]);
	NSString *artistID = MZString(performer[@"id"]);
	NSString *artistName = MZString(performer[@"name"]) ?: MZString(MZDictionary(performer[@"name"])[@"display"]);

	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	NSDictionary *image = MZDictionary(album[@"image"]);
	extras[MZExtrasCoverKey] = MZQobuzImageURL(image[@"large"]) ?: MZQobuzImageURL(image[@"small"]);
	extras[MZExtrasTitleURLKey] = MZLinkURL(@"https://open.qobuz.com/track/%@", trackID);
	extras[MZExtrasAlbumURLKey] = MZLinkURL(@"https://open.qobuz.com/album/%@", MZString(album[@"id"]));
	extras[MZExtrasArtistURLKey] = MZLinkURL(@"https://open.qobuz.com/artist/%@", artistID);
	extras[MZExtrasArtistNameKey] = artistName;

	MZQobuzTrack *remembered = [MZQobuzTrack new];
	remembered.extras = extras;
	remembered.artistID = artistID;
	// The app shows versions in titles: "Song (Remix)", "Album (Deluxe)".
	NSMutableArray *titles = [NSMutableArray arrayWithObject:title];
	NSString *version = MZString(track[@"version"]);
	if (version) [titles addObject:[NSString stringWithFormat:@"%@ (%@)", title, version]];
	NSMutableArray *albumTitles = [NSMutableArray arrayWithObject:albumTitle];
	NSString *albumVersion = MZString(album[@"version"]);
	if (albumVersion) [albumTitles addObject:[NSString stringWithFormat:@"%@ (%@)", albumTitle, albumVersion]];
	NSMutableArray *keys = [NSMutableArray array];
	for (NSString *t in titles) {
		for (NSString *a in albumTitles) [keys addObject:MZPairKey(t, a)];
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

static void MZRemember(id object, NSUInteger depth) {
	if (depth > 10) return;
	if ([object isKindOfClass:NSArray.class]) {
		for (id item in object) MZRemember(item, depth + 1);
		return;
	}

	NSDictionary *dictionary = MZDictionary(object);
	if (!dictionary) return;
	// An artist, wherever it appears. Artist pages name them as
	// name.display.
	NSString *ID = MZString(dictionary[@"id"]);
	BOOL named = MZString(dictionary[@"name"]) || MZString(MZDictionary(dictionary[@"name"])[@"display"]);
	NSString *picture = ID && named ? MZPicture(dictionary) : nil;
	if (picture) {
		@synchronized(tracks) {
			if (pictures.count > 1000) [pictures removeAllObjects];
			pictures[ID] = picture;
		}
	}

	// A track: it has an album.
	if ([dictionary[@"id"] isKindOfClass:NSNumber.class] && MZDictionary(dictionary[@"album"])) MZRememberTrack(dictionary);
	// An album with its tracks, which don't repeat it.
	NSArray *items = MZDictionary(dictionary[@"tracks"])[@"items"];
	if ([items isKindOfClass:NSArray.class] && MZString(dictionary[@"title"]) && MZDictionary(dictionary[@"image"])) {
		NSMutableDictionary *album = [dictionary mutableCopy];
		[album removeObjectForKey:@"tracks"];
		for (id item in items) {
			NSDictionary *track = MZDictionary(item);
			if (!track || track[@"album"]) continue;
			NSMutableDictionary *withAlbum = [track mutableCopy];
			withAlbum[@"album"] = album;
			MZRememberTrack(withAlbum);
		}
	}

	for (id value in dictionary.allValues) {
		if ([value isKindOfClass:NSArray.class] || [value isKindOfClass:NSDictionary.class]) MZRemember(value, depth + 1);
	}
}

static NSDictionary *MZExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	if (withExtras[MPNowPlayingInfoPropertyAssetURL]) return nil;
	NSString *key = MZPairKey(MZString(info[MPMediaItemPropertyTitle]), MZString(info[MPMediaItemPropertyAlbumTitle]));
	@synchronized(tracks) {
		MZQobuzTrack *track = key ? tracks[key] : nil;
		if (!track) return nil;
		NSMutableDictionary *extras = [track.extras mutableCopy];
		extras[MZExtrasArtistImageKey] = track.artistID ? pictures[track.artistID] : nil;
		return extras;
	}
}

%ctor {
	tracks = [NSMutableDictionary dictionary];
	pictures = [NSMutableDictionary dictionary];
	MZProviderCheck(@[@"NSURLSession -_dataTaskWithRequest:delegate:completionHandler:"], @[]);
	MZAddExtras(MZExtras);
	MZObserveResponses(^BOOL(NSURL *url) {
		return MZIsCatalog(url);
	}, ^(NSURL *url, NSData *body) {
		id object = MZJSON(body);
		if (object) MZRemember(object, 0);
	});
}
