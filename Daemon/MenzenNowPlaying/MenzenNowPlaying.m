#import <dlfcn.h>

#import "../../Shared/MenzenMediaRemote.h"
#import "../../Shared/MenzenTrackExtras.h"
#import "MenzenNowPlaying.h"

// The key constants' values are their own names, so plain strings work and
// save a dlsym per key.
static NSString *const MenzenInfoTitle = @"kMRMediaRemoteNowPlayingInfoTitle";
static NSString *const MenzenInfoArtist = @"kMRMediaRemoteNowPlayingInfoArtist";
static NSString *const MenzenInfoAlbum = @"kMRMediaRemoteNowPlayingInfoAlbum";
static NSString *const MenzenInfoArtworkIdentifier = @"kMRMediaRemoteNowPlayingInfoArtworkIdentifier";
static NSString *const MenzenInfoContentItemIdentifier = @"kMRMediaRemoteNowPlayingInfoContentItemIdentifier";
static NSString *const MenzenInfoAssetURL = @"kMRMediaRemoteNowPlayingInfoAssetURL";
static NSString *const MenzenInfoStoreIdentifier = @"kMRMediaRemoteNowPlayingInfoiTunesStoreIdentifier";
static NSString *const MenzenInfoAlbumStoreIdentifier = @"kMRMediaRemoteNowPlayingInfoAlbumiTunesStoreAdamIdentifier";
static NSString *const MenzenInfoArtistStoreIdentifier = @"kMRMediaRemoteNowPlayingInfoArtistiTunesStoreAdamIdentifier";
static NSString *const MenzenInfoDuration = @"kMRMediaRemoteNowPlayingInfoDuration";
static NSString *const MenzenInfoElapsedTime = @"kMRMediaRemoteNowPlayingInfoElapsedTime";
static NSString *const MenzenInfoTimestamp = @"kMRMediaRemoteNowPlayingInfoTimestamp";
static NSString *const MenzenInfoPlaybackRate = @"kMRMediaRemoteNowPlayingInfoPlaybackRate";
static NSString *const MenzenInfoMediaType = @"kMRMediaRemoteNowPlayingInfoMediaType";

static NSString *MenzenString(id value) {
	return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

// A positive number, as a string; 0 means none.
static NSString *MenzenIdentifier(id value) {
	long long identifier = [value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class] ? [value longLongValue] : 0;
	return identifier > 0 ? @(identifier).stringValue : nil;
}

static double MenzenDouble(id value) {
	return [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 0;
}

@implementation MenzenTrack

- (NSTimeInterval)elapsedAtDate:(NSDate *)date {
	NSTimeInterval elapsed = self.elapsed;
	if (self.playing && self.timestamp) elapsed += [date timeIntervalSinceDate:self.timestamp] * (self.playbackRate ?: 1);
	if (self.duration > 0) elapsed = MIN(elapsed, self.duration);
	return MAX(elapsed, 0);
}

@end

static MenzenTrack *MenzenTrackFromInfo(NSDictionary *info, NSString *bundleIdentifier, BOOL playing) {
	MenzenTrack *track = [MenzenTrack new];
	track.bundleIdentifier = bundleIdentifier;
	track.title = MenzenString(info[MenzenInfoTitle]);
	track.artist = MenzenString(info[MenzenInfoArtist]);
	// Some apps fill the artist with a placeholder ("Tubi - Now Playing").
	if ([track.artist hasSuffix:@" - Now Playing"]) track.artist = nil;
	track.album = MenzenString(info[MenzenInfoAlbum]);
	track.artworkIdentifier = MenzenString(info[MenzenInfoArtworkIdentifier]);
	track.contentIdentifier = MenzenString(info[MenzenInfoContentItemIdentifier]);
	id assetURL = info[MenzenInfoAssetURL];
	track.assetURL = [assetURL isKindOfClass:NSURL.class] ? [assetURL absoluteString] : MenzenString(assetURL);
	track.storeIdentifier = MenzenIdentifier(info[MenzenInfoStoreIdentifier]);
	track.albumStoreIdentifier = MenzenIdentifier(info[MenzenInfoAlbumStoreIdentifier]);
	track.artistStoreIdentifier = MenzenIdentifier(info[MenzenInfoArtistStoreIdentifier]);
	track.mediaType = MenzenString(info[MenzenInfoMediaType]);
	track.duration = MenzenDouble(info[MenzenInfoDuration]);
	track.elapsed = MenzenDouble(info[MenzenInfoElapsedTime]);
	track.timestamp = [info[MenzenInfoTimestamp] isKindOfClass:NSDate.class] ? info[MenzenInfoTimestamp] : nil;
	track.playbackRate = MenzenDouble(info[MenzenInfoPlaybackRate]);
	track.playing = playing;

	// A live stream's time comes from its listing's slot.
	NSDictionary *extras = MenzenExtrasFromURL(track.assetURL);
	double start = [extras[MenzenExtrasStartKey] doubleValue], end = [extras[MenzenExtrasEndKey] doubleValue];
	if (track.duration <= 0 && start > 0 && end > start) {
		track.duration = end - start;
		track.elapsed = 0;
		track.timestamp = [NSDate dateWithTimeIntervalSince1970:start];
		track.playbackRate = 1;
	}

	return track;
}

@implementation MenzenNowPlaying {
	void (^_handler)(MenzenTrack *);
	BOOL _updatePending;
	MRMediaRemoteGetNowPlayingInfoFn _getNowPlayingInfo;
	MRMediaRemoteGetNowPlayingApplicationIsPlayingFn _getIsPlaying;
	MRMediaRemoteGetNowPlayingClientFn _getClient;
	MRNowPlayingClientGetStringFn _clientGetBundleIdentifier;
	MRNowPlayingClientGetStringFn _clientGetParentAppBundleIdentifier;
}

- (instancetype)initWithHandler:(void (^)(MenzenTrack *))handler {
	if ((self = [super init])) _handler = [handler copy];
	return self;
}

static void *MenzenSymbol(void *handle, const char *name) {
	void *symbol = dlsym(handle, name);
	return symbol;
}

- (BOOL)start {
	void *handle = dlopen(MenzenMediaRemotePath, RTLD_LAZY);
	if (!handle) return NO;

	MRMediaRemoteRegisterForNowPlayingNotificationsFn registerForNotifications = MenzenSymbol(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
	_getNowPlayingInfo = MenzenSymbol(handle, "MRMediaRemoteGetNowPlayingInfo");
	_getIsPlaying = MenzenSymbol(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
	_getClient = MenzenSymbol(handle, "MRMediaRemoteGetNowPlayingClient");
	_clientGetBundleIdentifier = MenzenSymbol(handle, "MRNowPlayingClientGetBundleIdentifier");
	_clientGetParentAppBundleIdentifier = MenzenSymbol(handle, "MRNowPlayingClientGetParentAppBundleIdentifier");
	if (!registerForNotifications || !_getNowPlayingInfo || !_getIsPlaying || !_getClient || !_clientGetBundleIdentifier) return NO;

	const char *notificationSymbols[] = {
		"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
		"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
		"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
	};
	__weak typeof(self) weakSelf = self;
	for (size_t i = 0; i < sizeof(notificationSymbols) / sizeof(*notificationSymbols); i++) {
		CFStringRef *namePointer = MenzenSymbol(handle, notificationSymbols[i]);
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
		MenzenTrack *track = info.count && bundleIdentifier ? MenzenTrackFromInfo(info, bundleIdentifier, playing) : nil;
		// Apple Music's animated artwork shows up as its own content item, and
		// the next song as a "Loading…" placeholder for a moment.
		if ([track.contentIdentifier hasPrefix:@"animatedArtwork_"] || [track.contentIdentifier hasPrefix:@"\u267B"]) return;
		strongSelf->_handler(track);
	});
}

@end
