#import <dlfcn.h>

#import "../../Shared/MZMediaRemote.h"
#import "../../Shared/MZTrackExtras.h"
#import "../MZLog/MZLog.h"
#import "MZNowPlaying.h"

// The key constants' values are their own names, so plain strings work and
// save a dlsym per key.
static NSString *const MZInfoTitle = @"kMRMediaRemoteNowPlayingInfoTitle";
static NSString *const MZInfoArtist = @"kMRMediaRemoteNowPlayingInfoArtist";
static NSString *const MZInfoAlbum = @"kMRMediaRemoteNowPlayingInfoAlbum";
static NSString *const MZInfoArtworkIdentifier = @"kMRMediaRemoteNowPlayingInfoArtworkIdentifier";
static NSString *const MZInfoContentItemIdentifier = @"kMRMediaRemoteNowPlayingInfoContentItemIdentifier";
static NSString *const MZInfoAssetURL = @"kMRMediaRemoteNowPlayingInfoAssetURL";
static NSString *const MZInfoStoreIdentifier = @"kMRMediaRemoteNowPlayingInfoiTunesStoreIdentifier";
static NSString *const MZInfoAlbumStoreIdentifier = @"kMRMediaRemoteNowPlayingInfoAlbumiTunesStoreAdamIdentifier";
static NSString *const MZInfoArtistStoreIdentifier = @"kMRMediaRemoteNowPlayingInfoArtistiTunesStoreAdamIdentifier";
static NSString *const MZInfoDuration = @"kMRMediaRemoteNowPlayingInfoDuration";
static NSString *const MZInfoElapsedTime = @"kMRMediaRemoteNowPlayingInfoElapsedTime";
static NSString *const MZInfoTimestamp = @"kMRMediaRemoteNowPlayingInfoTimestamp";
static NSString *const MZInfoPlaybackRate = @"kMRMediaRemoteNowPlayingInfoPlaybackRate";
static NSString *const MZInfoMediaType = @"kMRMediaRemoteNowPlayingInfoMediaType";

static NSString *MZString(id value) {
	return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

// A positive number, as a string; 0 means none.
static NSString *MZIdentifier(id value) {
	long long identifier = [value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class] ? [value longLongValue] : 0;
	return identifier > 0 ? @(identifier).stringValue : nil;
}

static double MZDouble(id value) {
	return [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 0;
}

@implementation MZTrack

- (NSTimeInterval)elapsedAtDate:(NSDate *)date {
	NSTimeInterval elapsed = self.elapsed;
	if (self.playing && self.timestamp) elapsed += [date timeIntervalSinceDate:self.timestamp] * (self.playbackRate ?: 1);
	if (self.duration > 0) elapsed = MIN(elapsed, self.duration);
	return MAX(elapsed, 0);
}

@end

static MZTrack *MZTrackFromInfo(NSDictionary *info, NSString *bundleIdentifier, BOOL playing) {
	MZTrack *track = [MZTrack new];
	track.bundleIdentifier = bundleIdentifier;
	track.title = MZString(info[MZInfoTitle]);
	track.artist = MZString(info[MZInfoArtist]);
	// Some apps fill the artist with a placeholder ("Tubi - Now Playing").
	if ([track.artist hasSuffix:@" - Now Playing"]) track.artist = nil;
	track.album = MZString(info[MZInfoAlbum]);
	track.artworkIdentifier = MZString(info[MZInfoArtworkIdentifier]);
	track.contentIdentifier = MZString(info[MZInfoContentItemIdentifier]);
	id assetURL = info[MZInfoAssetURL];
	track.assetURL = [assetURL isKindOfClass:NSURL.class] ? [assetURL absoluteString] : MZString(assetURL);
	track.storeIdentifier = MZIdentifier(info[MZInfoStoreIdentifier]);
	track.albumStoreIdentifier = MZIdentifier(info[MZInfoAlbumStoreIdentifier]);
	track.artistStoreIdentifier = MZIdentifier(info[MZInfoArtistStoreIdentifier]);
	track.mediaType = MZString(info[MZInfoMediaType]);
	track.duration = MZDouble(info[MZInfoDuration]);
	track.elapsed = MZDouble(info[MZInfoElapsedTime]);
	track.timestamp = [info[MZInfoTimestamp] isKindOfClass:NSDate.class] ? info[MZInfoTimestamp] : nil;
	track.playbackRate = MZDouble(info[MZInfoPlaybackRate]);
	track.playing = playing;

	// A live stream's time comes from its listing's slot.
	NSDictionary *extras = MZExtrasFromURL(track.assetURL);
	double start = [extras[MZExtrasStartKey] doubleValue], end = [extras[MZExtrasEndKey] doubleValue];
	if (track.duration <= 0 && start > 0 && end > start) {
		track.duration = end - start;
		track.elapsed = 0;
		track.timestamp = [NSDate dateWithTimeIntervalSince1970:start];
		track.playbackRate = 1;
	}

	return track;
}

#ifdef DEBUG
static void MZLogTrack(MZTrack *track) {
	if (!track) {
		MZLog(@"now playing: nothing");
		return;
	}

	// An app's own asset URL can carry a streaming token: only its host.
	NSString *asset = MZExtrasFromURL(track.assetURL) ? track.assetURL : [NSURLComponents componentsWithString:track.assetURL ?: @""].host;
	MZLog(@"now playing: %@ playing=%d \"%@\" album=\"%@\" time=%.0f/%.0f type=%@ artwork=%@ asset=%@ content=%@ store=%@/%@/%@", track.bundleIdentifier, track.playing, track.title, track.album, track.elapsed, track.duration, track.mediaType, track.artworkIdentifier, asset, track.contentIdentifier, track.storeIdentifier, track.albumStoreIdentifier, track.artistStoreIdentifier);
}
#endif

@implementation MZNowPlaying {
	void (^_handler)(MZTrack *);
	BOOL _updatePending;
	MRMediaRemoteGetNowPlayingInfoFn _getNowPlayingInfo;
	MRMediaRemoteGetNowPlayingApplicationIsPlayingFn _getIsPlaying;
	MRMediaRemoteGetNowPlayingClientFn _getClient;
	MRNowPlayingClientGetStringFn _clientGetBundleIdentifier;
	MRNowPlayingClientGetStringFn _clientGetParentAppBundleIdentifier;
}

- (instancetype)initWithHandler:(void (^)(MZTrack *))handler {
	if ((self = [super init])) _handler = [handler copy];
	return self;
}

static void *MZSymbol(void *handle, const char *name) {
	void *symbol = dlsym(handle, name);
	if (!symbol) MZLog(@"missing MediaRemote symbol %s", name);
	return symbol;
}

- (BOOL)start {
	void *handle = dlopen(MZMediaRemotePath, RTLD_LAZY);
	if (!handle) {
		MZLog(@"could not open MediaRemote: %s", dlerror());
		return NO;
	}

	MRMediaRemoteRegisterForNowPlayingNotificationsFn registerForNotifications = MZSymbol(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
	_getNowPlayingInfo = MZSymbol(handle, "MRMediaRemoteGetNowPlayingInfo");
	_getIsPlaying = MZSymbol(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
	_getClient = MZSymbol(handle, "MRMediaRemoteGetNowPlayingClient");
	_clientGetBundleIdentifier = MZSymbol(handle, "MRNowPlayingClientGetBundleIdentifier");
	_clientGetParentAppBundleIdentifier = MZSymbol(handle, "MRNowPlayingClientGetParentAppBundleIdentifier");
	if (!registerForNotifications || !_getNowPlayingInfo || !_getIsPlaying || !_getClient || !_clientGetBundleIdentifier) return NO;

	const char *notificationSymbols[] = {
		"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
		"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
		"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
	};
	__weak typeof(self) weakSelf = self;
	for (size_t i = 0; i < sizeof(notificationSymbols) / sizeof(*notificationSymbols); i++) {
		CFStringRef *namePointer = MZSymbol(handle, notificationSymbols[i]);
		if (!namePointer || !*namePointer) continue;
		[NSNotificationCenter.defaultCenter addObserverForName:(__bridge NSString *)*namePointer object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
			[weakSelf scheduleUpdate];
		}];
	}

	registerForNotifications(dispatch_get_main_queue());
	[self scheduleUpdate];
	return YES;
}

// A track change comes as several notifications in quick succession, so read
// everything once, shortly after the first. Not restarted by later
// notifications, or an app that updates constantly would never be read.
- (void)scheduleUpdate {
	if (_updatePending) return;
	_updatePending = YES;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf->_updatePending = NO;
		[strongSelf update];
	});
}

- (void)refresh {
	[self update];
}

- (void)update {
	dispatch_group_t group = dispatch_group_create();
	__block NSDictionary *info;
	__block BOOL playing = NO;
	__block NSString *bundleIdentifier;
	dispatch_queue_t queue = dispatch_get_main_queue();

	dispatch_group_enter(group);
	_getNowPlayingInfo(queue, ^(CFDictionaryRef raw) {
		info = [(__bridge NSDictionary *)raw copy];
		dispatch_group_leave(group);
	});
	dispatch_group_enter(group);
	_getIsPlaying(queue, ^(Boolean isPlaying) {
		playing = isPlaying;
		dispatch_group_leave(group);
	});
	dispatch_group_enter(group);
	MRNowPlayingClientGetStringFn getBundleIdentifier = _clientGetBundleIdentifier;
	MRNowPlayingClientGetStringFn getParentAppBundleIdentifier = _clientGetParentAppBundleIdentifier;
	_getClient(queue, ^(id client) {
		if (client) {
			NSString *parent = getParentAppBundleIdentifier ? (__bridge NSString *)getParentAppBundleIdentifier(client) : nil;
			bundleIdentifier = [(parent.length ? parent : (__bridge NSString *)getBundleIdentifier(client)) copy];
		}
		dispatch_group_leave(group);
	});

	__weak typeof(self) weakSelf = self;
	dispatch_group_notify(group, queue, ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		MZTrack *track = info.count && bundleIdentifier ? MZTrackFromInfo(info, bundleIdentifier, playing) : nil;
		// Apple Music's animated artwork shows up as its own content item, and
		// the next song as a "Loading…" placeholder for a moment.
		if ([track.contentIdentifier hasPrefix:@"animatedArtwork_"] || [track.contentIdentifier hasPrefix:@"\u267B"]) return;
#ifdef DEBUG
		MZLogTrack(track);
#endif
		strongSelf->_handler(track);
	});
}

@end
