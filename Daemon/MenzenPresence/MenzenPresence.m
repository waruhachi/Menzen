#import "../../Shared/MenzenApelin.h"
#import "../../Shared/MenzenCustomActivity.h"
#import "../../Shared/MenzenProviders.h"
#import "../../Shared/MenzenSettings.h"
#import "../MenzenApelin/MenzenApelin.h"
#import "../MenzenApps/MenzenAppCatalog.h"
#import "../MenzenApps/MenzenAppInfo.h"
#import "../MenzenDiscord/MenzenDiscord.h"
#import "MenzenPresence.h"
#import "MenzenTrackActivity.h"

// Pausing briefly, skipping around, a look at the app switcher or a quick
// reply in another app shouldn't flicker the status.
static NSTimeInterval const MenzenDefaultStopGrace = 10;
// Apelin's agent moves on while the app stays on screen. Discord takes five
// updates in 20 s.
static NSTimeInterval const MenzenApelinRefresh = 5;

static NSTimeInterval MenzenStopGrace(void) {
	return MenzenSettingDouble(MenzenSettingPauseGrace, MenzenDefaultStopGrace);
}

static BOOL MenzenSourceEnabled(NSString *bundleIdentifier) {
	if (!bundleIdentifier.length || !MenzenSettingBool(MenzenSettingEnabled, YES)) return NO;
	if (!MenzenProviderForBundleIdentifier(bundleIdentifier)) return MenzenSettingBool(MenzenSettingOtherApps, NO) && !MenzenIsChatApp(bundleIdentifier) && !MenzenIsBrowserApp(bundleIdentifier);
	return MenzenSettingBool([MenzenSettingSourcePrefix stringByAppendingString:bundleIdentifier], YES);
}

static BOOL MenzenGameEnabled(NSString *bundleIdentifier) {
	if (!MenzenSettingBool(MenzenSettingEnabled, YES)) return NO;
	return MenzenSettingBool([MenzenSettingGamePrefix stringByAppendingString:bundleIdentifier], YES);
}

@implementation MenzenPresence {
	MenzenDiscord *_discord;
	MenzenAppCatalog *_appCatalog;
	// Each source's activity; publish shows the first in MenzenPriority().
	MenzenActivity *_media;
	MenzenActivity *_connected;
	NSArray<NSString *> *_visibleApps;
	// The game, since it came on screen. Once it's left (_gameLeft) it ends
	// when the grace period runs out or something starts playing.
	NSString *_game;
	NSDate *_gameStart;
	BOOL _gameLeft;
	NSUInteger _gameEndGeneration;
	NSTimer *_gameRefresh;
	MenzenTrack *_lastTrack;
	// Kept after playback stops, for the preview.
	MenzenTrack *_lastPlayed;
	NSDate *_lastPlayedStopped;
	BOOL _clearPending;
	NSUInteger _clearGeneration;
}

- (instancetype)initWithDiscord:(MenzenDiscord *)discord appCatalog:(MenzenAppCatalog *)appCatalog {
	if ((self = [super init])) {
		_discord = discord;
		_appCatalog = appCatalog;
		if ([self customActivity]) [self publish];
	}

	return self;
}

- (MenzenActivity *)customActivity {
	if (!MenzenSettingBool(MenzenSettingEnabled, YES) || !MenzenSettingBool(MenzenSettingCustom, NO)) return nil;
	NSDictionary *preset = MenzenCustomPreset(MenzenSettingString(MenzenSettingCustomPreset, nil));
	if (!preset) return nil;
	MenzenActivity *activity = [MenzenActivity new];
	NSString *kind = MenzenPresetString(preset, MenzenPresetKindKey);
	activity.kind = [kind isEqualToString:@"listening"] ? MenzenActivityKindListening : [kind isEqualToString:@"watching"] ? MenzenActivityKindWatching
																														   : MenzenActivityKindPlaying;
	activity.statusDisplay = MenzenStatusDisplayName;
	// Without a name, Discord uses the application's: "Menzen".
	activity.name = MenzenPresetString(preset, MenzenPresetNameKey);
	NSString *largeImage = MenzenPresetString(preset, MenzenPresetLargeImageKey);
	if (MenzenCustomImageURLIsAllowed(largeImage)) activity.largeImageURL = largeImage;
	if (MenzenSettingBool(MenzenSettingPrivacy, NO)) return activity;

	activity.details = MenzenPresetString(preset, MenzenPresetDetailsKey);
	activity.state = MenzenPresetString(preset, MenzenPresetStateKey);
	// Discord only shows the texts and the small picture with a big one.
	if (activity.largeImageURL) {
		activity.largeText = MenzenPresetString(preset, MenzenPresetLargeTextKey);
		NSString *smallImage = MenzenPresetString(preset, MenzenPresetSmallImageKey);
		if (MenzenCustomImageURLIsAllowed(smallImage)) {
			activity.smallImageURL = smallImage;
			activity.smallText = MenzenPresetString(preset, MenzenPresetSmallTextKey);
		}
	}

	id timer = preset[MenzenPresetTimerKey];
	NSDate *start = MenzenSettingValue(MenzenSettingCustomStart);
	if ((![timer respondsToSelector:@selector(boolValue)] || [timer boolValue]) && [start isKindOfClass:NSDate.class]) activity.startDate = start;
	return activity;
}

- (MenzenActivity *)activityForSource:(NSString *)source {
	if ([source isEqualToString:MenzenSourceCustom]) return [self customActivity];
	if ([source isEqualToString:MenzenSourceConnected]) return MenzenSettingBool(MenzenSettingEnabled, YES) ? _connected : nil;
	if ([source isEqualToString:MenzenSourceGames]) return _game ? [self activityForGame:_game] : nil;
	return _media;
}

- (void)publish {
	MenzenActivity *activity;
	for (NSString *source in MenzenPriority()) {
		activity = [self activityForSource:source];
		if (activity) break;
	}

	[_discord setActivity:activity];
}

- (void)showMedia:(MenzenActivity *)activity {
	_media = activity;
	[self publish];
}

- (void)setConnectedActivity:(MenzenActivity *)activity {
	_connected = activity;
	[self publish];
}

- (void)cancelClear {
	_clearGeneration++;
	_clearPending = NO;
}

- (void)updatePreviewWithTrack:(MenzenTrack *)track {
	if (MenzenTrackIsShowable(track)) {
		_lastPlayed = track;
		_lastPlayedStopped = nil;
	} else if (!track && !_lastPlayedStopped) {
		_lastPlayedStopped = NSDate.date;
	}

	NSDate *pausedDate;
	MenzenActivity *preview = _lastPlayed ? MenzenPreviewForTrack(_lastPlayed, [_appCatalog iconURLForApp:_lastPlayed.bundleIdentifier], _lastPlayedStopped, &pausedDate) : nil;
	[_discord setPreviewActivity:preview pausedDate:pausedDate];
}

- (void)handleTrack:(MenzenTrack *)track {
	_lastTrack = track;
	[self updatePreviewWithTrack:track];

	// Stopped, closed, or a source that's switched off took over: clear now.
	if (!track || !MenzenSourceEnabled(track.bundleIdentifier)) {
		[self cancelClear];
		if (_media) [self showMedia:nil];
		return;
	}

	MenzenActivity *activity = MenzenActivityForTrack(track, [_appCatalog iconURLForApp:track.bundleIdentifier]);
	// A live stream has no duration or position: its clock counts from when
	// it first showed, not from each update.
	if (track.duration <= 0 && activity.startDate && !activity.endDate && _media.startDate && !_media.endDate && [_media.details isEqualToString:activity.details]) activity.startDate = _media.startDate;
	if (track.playing && activity) {
		[self cancelClear];
		// Playing something after leaving a game takes over from it.
		if (_gameLeft) [self endGame];
		[self showMedia:activity];
		return;
	}

	if (_media) [self showPaused:activity];
}

// Paused (or a Spotify ad): stop the progress bar, then clear if playback
// doesn't resume within the grace period.
- (void)showPaused:(MenzenActivity *)activity {
	NSTimeInterval grace = MenzenStopGrace();
	if (grace == 0) {
		[self cancelClear];
		[self showMedia:nil];
		return;
	}

	if (activity) {
		[self showMedia:activity];
	} else if (_media.startDate) {
		MenzenActivity *paused = [_media copy];
		paused.startDate = nil;
		paused.endDate = nil;
		[self showMedia:paused];
	}

	// Negative: keep showing until playback stops.
	if (_clearPending || grace < 0) return;
	_clearPending = YES;
	NSUInteger generation = ++_clearGeneration;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(grace * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf->_clearGeneration) return;
		strongSelf->_clearPending = NO;
		[strongSelf showMedia:nil];
	});
}

- (void)handleVisibleApps:(NSArray<NSString *> *)visibleApps {
	_visibleApps = visibleApps;
	[self updateGame];
}

- (void)appCatalogChanged {
	[self updateGame];
}

- (void)updateGame {
	NSString *game;
	for (NSString *bundleIdentifier in _visibleApps) {
		if ([_appCatalog isGame:bundleIdentifier] && MenzenGameEnabled(bundleIdentifier)) {
			game = bundleIdentifier;
			break;
		}
	}

	if (game) {
		_gameEndGeneration++;
		_gameLeft = NO;
		if (![game isEqualToString:_game]) {
			_game = game;
			_gameStart = NSDate.date;
		}
		[self publish];
		[self updateGameRefresh];
		return;
	}

	if (!_game) return;
	// Switched off: at once.
	NSTimeInterval grace = MenzenStopGrace();
	if (!MenzenGameEnabled(_game) || grace == 0) {
		[self endGame];
		return;
	}

	// Left: it stays for the grace period, or with a negative one until
	// something else takes over. Other apps coming and going don't restart it.
	if (_gameLeft) return;
	_gameLeft = YES;
	NSUInteger generation = ++_gameEndGeneration;
	if (grace < 0) return;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(grace * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		typeof(self) strongSelf = weakSelf;
		if (strongSelf && generation == strongSelf->_gameEndGeneration) [strongSelf endGame];
	});
}

- (MenzenActivity *)activityForGame:(NSString *)bundleIdentifier {
	MenzenActivity *activity = [MenzenActivity new];
	activity.kind = MenzenActivityKindPlaying;
	activity.statusDisplay = MenzenStatusDisplayName;
	activity.name = MenzenAppName(bundleIdentifier);
	// Without one, Discord shows Menzen's icon.
	activity.largeImageURL = [_appCatalog iconURLForApp:bundleIdentifier];
	if (MenzenSettingBool(MenzenSettingPrivacy, NO)) return activity;
	activity.startDate = _gameStart;
	if (activity.largeImageURL) {
		activity.largeText = activity.name;
		if (MenzenSettingBool(MenzenSettingLinks, YES)) activity.largeURL = [_appCatalog storeURLForApp:bundleIdentifier];
	}

	if ([bundleIdentifier isEqualToString:MenzenApelinBundleIdentifier]) {
		MenzenApelinSession *session = MenzenReadApelinSession();
		NSString *project = MenzenSettingBool(MenzenSettingApelinProject, YES) ? session.project : nil;
		NSString *agent = MenzenSettingBool(MenzenSettingApelinAgent, YES) ? session.agent : nil;
		activity.details = project ?: agent;
		activity.state = project ? agent : nil;
	}

	return activity;
}

- (void)updateGameRefresh {
	if (![_game isEqualToString:MenzenApelinBundleIdentifier]) {
		[_gameRefresh invalidate];
		_gameRefresh = nil;
		return;
	}

	if (_gameRefresh) return;
	__weak typeof(self) weakSelf = self;
	_gameRefresh = [NSTimer scheduledTimerWithTimeInterval:MenzenApelinRefresh repeats:YES block:^(NSTimer *timer) {
		typeof(self) strongSelf = weakSelf;
		if (strongSelf && strongSelf->_game) [strongSelf publish];
	}];
}

- (void)endGame {
	_game = nil;
	_gameStart = nil;
	_gameLeft = NO;
	_gameEndGeneration++;
	[self updateGameRefresh];
	[self publish];
}

- (void)settingsChanged {
	[self cancelClear];
	// Restarts a left game's countdown with the new grace period.
	_gameLeft = NO;
	[self updateGame];
	[self handleTrack:_lastTrack];
	// A preset switched on or off, or edited, with nothing else changing.
	[self publish];
}

@end
