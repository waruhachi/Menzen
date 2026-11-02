#import <objc/runtime.h>

#import "../../Shared/MZProvider/MZProvider.h"

// The cover and links come from the player's track metadata; the artist's
// picture from Spotify's internal API, through the app's own signed-in data
// loader.

@interface SPTPlayerTrack : NSObject
@property (nonatomic, readonly) id URI;
// Cover fields hold "spotify:image:<id>" or an https URL; also artist_uri,
// artist_name and album_uri.
@property (nonatomic, readonly) NSDictionary<NSString *, id> *metadata;
@end

@interface SPTPlayerState : NSObject
@property (nonatomic, readonly) SPTPlayerTrack *track;
@end

@interface SPTEsperantoPlayer : NSObject
@property (nonatomic, readonly) SPTPlayerState *state;
@end

// Adds the app's own sign-in to requests for its internal API.
@interface SPTDataLoaderFactory : NSObject
- (id)createDataLoader;
@end

@interface SPTDataLoaderRequest : NSObject
+ (instancetype)requestWithURL:(NSURL *)URL sourceIdentifier:(NSString *)sourceIdentifier;
- (void)addValue:(NSString *)value forHeader:(NSString *)header;
@end

@interface SPTDataLoaderResponse : NSObject
@property (nonatomic, readonly) NSData *body;
@property (nonatomic, readonly) NSInteger statusCode;
@end

@interface SPTDataLoaderBlockWrapper : NSObject
- (instancetype)initWithDataLoader:(id)dataLoader;
- (id)performRequest:(SPTDataLoaderRequest *)request completion:(void (^)(SPTDataLoaderResponse *response, NSError *error))completion;
@end

static __weak SPTEsperantoPlayer *player;
// The app makes several factories; not all of them sign their requests.
static NSHashTable *loaderFactories;
static __weak id signedLoaderFactory;
// NSNull for an artist without a picture.
static NSMutableDictionary<NSString *, id> *artistPictures;
static NSMutableSet<NSString *> *artistPicturesLoading;

static NSString *MZURIString(id uri) {
	if ([uri isKindOfClass:NSString.class]) return uri;
	if ([uri respondsToSelector:@selector(absoluteString)]) return [uri absoluteString];
	return [uri description];
}

static NSString *MZMetadataString(SPTPlayerTrack *track, NSString *key) {
	NSDictionary *metadata = [track respondsToSelector:@selector(metadata)] ? track.metadata : nil;
	id value = [metadata isKindOfClass:NSDictionary.class] ? metadata[key] : nil;
	return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

static NSString *MZSpotifyImageURL(NSString *value) {
	if ([value hasPrefix:@"spotify:image:"]) return [@"https://i.scdn.co/image/" stringByAppendingString:[value substringFromIndex:@"spotify:image:".length]];
	return value && [[NSURL URLWithString:value].scheme isEqualToString:@"https"] ? value : nil;
}

static NSString *MZCoverURL(SPTPlayerTrack *track) {
	for (NSString *field in @[@"image_xlarge_url", @"image_large_url", @"image_url"]) {
		NSString *url = MZSpotifyImageURL(MZMetadataString(track, field));
		if (url) return url;
	}

	return nil;
}

static NSString *const MZBase62 = @"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

// The base62 ID in "spotify:<type>:<id>".
static NSString *MZEntityID(NSString *uri, NSString *type) {
	NSString *prefix = [NSString stringWithFormat:@"spotify:%@:", type];
	if (![uri hasPrefix:prefix]) return nil;
	NSString *identifier = [uri substringFromIndex:prefix.length];
	NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:MZBase62].invertedSet;
	return identifier.length == 22 && [identifier rangeOfCharacterFromSet:invalid].location == NSNotFound ? identifier : nil;
}

static NSString *MZWebURL(NSString *uri, NSString *type) {
	NSString *identifier = MZEntityID(uri, type);
	return identifier ? [NSString stringWithFormat:@"https://open.spotify.com/%@/%@", type, identifier] : nil;
}

// Spotify's API names entities by the ID's 128 bit value in hex.
static NSString *MZHexID(NSString *base62) {
	unsigned __int128 value = 0;
	for (NSUInteger i = 0; i < base62.length; i++) {
		value = value * 62 + [MZBase62 rangeOfString:[base62 substringWithRange:NSMakeRange(i, 1)]].location;
	}

	return [NSString stringWithFormat:@"%016llx%016llx", (unsigned long long)(value >> 64), (unsigned long long)value];
}

static NSString *MZPortraitURL(NSDictionary *artist) {
	NSDictionary *group = artist[@"portrait_group"];
	NSArray *images = [group isKindOfClass:NSDictionary.class] ? group[@"image"] : nil;
	if (![images isKindOfClass:NSArray.class]) return nil;
	NSCharacterSet *notHex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"].invertedSet;
	NSString *best;
	for (NSDictionary *image in images) {
		if (![image isKindOfClass:NSDictionary.class] || ![image[@"file_id"] isKindOfClass:NSString.class]) continue;
		NSString *fileID = image[@"file_id"];
		if (!fileID.length || [fileID rangeOfCharacterFromSet:notHex].location != NSNotFound) continue;
		NSString *url = [@"https://i.scdn.co/image/" stringByAppendingString:fileID];
		// 640 px, then 320 px.
		if ([image[@"size"] isEqual:@"LARGE"]) return url;
		if (!best || [image[@"size"] isEqual:@"DEFAULT"]) best = url;
	}

	return best;
}

// Tries each factory until one is signed in; done(nil) when none is.
static void MZLoadArtist(NSString *hexID, NSArray *factories, void (^done)(NSDictionary *artist)) {
	if (!factories.count) {
		done(nil);
		return;
	}

	id factory = factories.firstObject;
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://spclient.wg.spotify.com/metadata/4/artist/%@?market=from_token", hexID]];
	// A request can't be shared between loaders.
	SPTDataLoaderRequest *request = [%c(SPTDataLoaderRequest) requestWithURL:url sourceIdentifier:@"menzen"];
	[request addValue:@"application/json" forHeader:@"Accept"];
	__block SPTDataLoaderBlockWrapper *wrapper = [[%c(SPTDataLoaderBlockWrapper) alloc] initWithDataLoader:[factory createDataLoader]];
	[wrapper performRequest:request completion:^(SPTDataLoaderResponse *response, NSError *error) {
		// The block keeps the loader alive until it answers.
		wrapper = nil;
		id artist = response.statusCode == 200 && response.body ? [NSJSONSerialization JSONObjectWithData:response.body options:0 error:NULL] : nil;
		dispatch_async(dispatch_get_main_queue(), ^{
			if (![artist isKindOfClass:NSDictionary.class]) {
				MZLoadArtist(hexID, [factories subarrayWithRange:NSMakeRange(1, factories.count - 1)], done);
				return;
			}
			signedLoaderFactory = factory;
			done(artist);
		});
	}];
}

// The artist's picture if it's known; otherwise starts loading it and
// publishes the info again once it's in.
static NSString *MZArtistPicture(NSString *artistURI) {
	NSString *identifier = MZEntityID(artistURI, @"artist");
	if (!identifier) return nil;
	id known = artistPictures[artistURI];
	if (known) return [known isKindOfClass:NSString.class] ? known : nil;
	if ([artistPicturesLoading containsObject:artistURI] || !%c(SPTDataLoaderRequest) || !%c(SPTDataLoaderBlockWrapper)) return nil;

	NSMutableArray *factories = [loaderFactories.allObjects mutableCopy];
	id signedFactory = signedLoaderFactory;
	if (signedFactory && [factories containsObject:signedFactory]) {
		[factories removeObject:signedFactory];
		[factories insertObject:signedFactory atIndex:0];
	}

	if (!factories.count) return nil;

	if (!artistPictures) artistPictures = [NSMutableDictionary dictionary];
	if (!artistPicturesLoading) artistPicturesLoading = [NSMutableSet set];
	[artistPicturesLoading addObject:artistURI];
	MZLoadArtist(MZHexID(identifier), factories, ^(NSDictionary *artist) {
		[artistPicturesLoading removeObject:artistURI];
		// No signed factory yet: a later track tries again.
		if (!artist) return;
		artistPictures[artistURI] = MZPortraitURL(artist) ?: (id)NSNull.null;
		MZRepublish();
	});
	return nil;
}

// The info's external content identifier is "<track uri>#<uuid>".
static NSString *MZTrackURIInInfo(NSDictionary *info) {
	NSString *identifier = info[MPNowPlayingInfoPropertyExternalContentIdentifier];
	if (![identifier isKindOfClass:NSString.class]) return nil;
	return [identifier componentsSeparatedByString:@"#"].firstObject;
}

static NSDictionary *MZExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	// Only when the player is on the same track as the info, so a stale or
	// early state never pairs a cover with the wrong song.
	SPTPlayerState *state = [player respondsToSelector:@selector(state)] ? player.state : nil;
	SPTPlayerTrack *track = [state respondsToSelector:@selector(track)] ? state.track : nil;
	NSString *trackURI = MZTrackURIInInfo(info);
	if (!trackURI || ![track respondsToSelector:@selector(URI)] || ![trackURI isEqualToString:MZURIString(track.URI)]) return nil;

	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	extras[MZExtrasCoverKey] = MZCoverURL(track);
	extras[MZExtrasTitleURLKey] = MZWebURL(trackURI, @"track") ?: MZWebURL(trackURI, @"episode");
	NSString *artistURI = MZMetadataString(track, @"artist_uri");
	extras[MZExtrasArtistURLKey] = MZWebURL(artistURI, @"artist");
	extras[MZExtrasAlbumURLKey] = MZWebURL(MZMetadataString(track, @"album_uri"), @"album");
	NSString *picture = MZArtistPicture(artistURI);
	if (picture) {
		extras[MZExtrasArtistImageKey] = picture;
		extras[MZExtrasArtistNameKey] = MZMetadataString(track, @"artist_name");
	}

	return extras;
}

%hook SPTEsperantoPlayer

- (void)addPlayerObserver:(id)observer {
	%orig;
	player = self;
}

%end

%group LoaderFactory

%hook MZLoaderFactory

- (id)createDataLoader {
	if (!loaderFactories) loaderFactories = [NSHashTable weakObjectsHashTable];
	[loaderFactories addObject:self];
	return %orig;
}

%end

%end

%ctor {
	MZProviderCheck(@[
		@"SPTEsperantoPlayer -addPlayerObserver:",
		@"SPTEsperantoPlayer -state",
		@"SPTPlayerState -track",
		@"SPTPlayerTrack -URI",
		@"SPTPlayerTrack -metadata",
	], @[
		@"SPTDataLoaderRequest +requestWithURL:sourceIdentifier:",
		@"SPTDataLoaderBlockWrapper -initWithDataLoader:",
		@"SPTDataLoaderBlockWrapper -performRequest:completion:",
		@"Connectivity_HttpClientKit.DataLoaderFactoryHttpClientImpl -createDataLoader | SPTDataLoaderFactory -createDataLoader",
	]);
	MZAddExtras(MZExtras);
	%init;
	// Spotify's Swift subclass of SPTDataLoaderFactory makes the signed ones.
	Class factoryClass = objc_getClass("Connectivity_HttpClientKit.DataLoaderFactoryHttpClientImpl") ?: %c(SPTDataLoaderFactory);
	if (factoryClass) %init(LoaderFactory, MZLoaderFactory = factoryClass);
}
