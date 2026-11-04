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

// Pausing briefly (or skipping around) shouldn't flicker the status.
static NSTimeInterval const MenzenDefaultPauseGrace = 10;
// Nor should a look at the app switcher or a quick reply in another app
// while playing a game.
static NSTimeInterval const MenzenGameGrace = 10;
// Apelin's agent moves on while the app stays on screen. Discord takes five
// updates in 20 s.
static NSTimeInterval const MenzenApelinRefresh = 5;

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
	MenzenActivity *_shown;
	NSArray<NSString *> *_visibleApps;
	// The game showing, since it came on screen; it shows over any track.
	NSString *_game;
	NSDate *_gameStart;
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

- (void)publish {
	[_discord setActivity:[self customActivity] ?: _shown];
}

- (void)show:(MenzenActivity *)activity {
	_shown = activity;
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
	if (_game) return;

	// Stopped, closed, or a source that's switched off took over: clear now.
	if (!track || !MenzenSourceEnabled(track.bundleIdentifier)) {
		[self cancelClear];
		if (_shown) [self show:nil];
		return;
	}

	MenzenActivity *activity = MenzenActivityForTrack(track, [_appCatalog iconURLForApp:track.bundleIdentifier]);
	// A live stream has no duration or position: its clock counts from when
	// it first showed, not from each update.
	if (track.duration <= 0 && activity.startDate && !activity.endDate && _shown.startDate && !_shown.endDate && [_shown.details isEqualToString:activity.details]) activity.startDate = _shown.startDate;
	if (track.playing && activity) {
		[self cancelClear];
		[self show:activity];
		return;
	}

	if (_shown) [self showPaused:activity];
}

// Paused (or a Spotify ad): stop the progress bar, then clear if playback
// doesn't resume within the grace period.
- (void)showPaused:(MenzenActivity *)activity {
	NSTimeInterval grace = MenzenSettingDouble(MenzenSettingPauseGrace, MenzenDefaultPauseGrace);
	if (grace == 0) {
		[self cancelClear];
		[self show:nil];
		return;
	}

	if (activity) {
		[self show:activity];
	} else if (_shown.startDate) {
		MenzenActivity *paused = [_shown copy];
		paused.startDate = nil;
		paused.endDate = nil;
		[self show:paused];
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
		[strongSelf show:nil];
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
		if (![game isEqualToString:_game]) {
			_game = game;
			_gameStart = NSDate.date;
		}
		// A track's pause countdown would clear the game.
		[self cancelClear];
		[self show:[self activityForGame:game]];
		[self updateGameRefresh];
		return;
	}

	if (!_game) return;
	// Switched off: at once.
	if (!MenzenGameEnabled(_game)) {
		[self endGame];
		return;
	}

	NSUInteger generation = ++_gameEndGeneration;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MenzenGameGrace * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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
		if (strongSelf && strongSelf->_game) [strongSelf show:[strongSelf activityForGame:strongSelf->_game]];
	}];
}

- (void)endGame {
	_game = nil;
	_gameStart = nil;
	_gameEndGeneration++;
	[self updateGameRefresh];
	MenzenActivity *shown = _shown;
	// A paused track only shows while it's already showing.
	_shown = nil;
	[self handleTrack:_lastTrack];
	if (shown && !_shown) [self publish];
}

- (void)settingsChanged {
	[self cancelClear];
	[self updateGame];
	[self handleTrack:_lastTrack];
	// A preset switched on or off, or edited, with nothing else changing.
	[self publish];
}

@end
