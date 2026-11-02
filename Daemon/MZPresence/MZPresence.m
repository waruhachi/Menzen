#import "../../Shared/MZApelin.h"
#import "../../Shared/MZCustomActivity.h"
#import "../../Shared/MZProviders.h"
#import "../../Shared/MZSettings.h"
#import "../MZApelin/MZApelin.h"
#import "../MZApps/MZAppCatalog.h"
#import "../MZApps/MZAppInfo.h"
#import "../MZDiscord/MZDiscord.h"
#import "../MZLog/MZLog.h"
#import "MZPresence.h"
#import "MZTrackActivity.h"

// Pausing briefly (or skipping around) shouldn't flicker the status.
static NSTimeInterval const MZDefaultPauseGrace = 10;
// Nor should a look at the app switcher or a quick reply in another app
// while playing a game.
static NSTimeInterval const MZGameGrace = 10;
// Apelin's agent moves on while the app stays on screen. Discord takes five
// updates in 20 s.
static NSTimeInterval const MZApelinRefresh = 5;

static BOOL MZSourceEnabled(NSString *bundleIdentifier) {
	if (!bundleIdentifier.length || !MZSettingBool(MZSettingEnabled, YES)) return NO;
	if (!MZProviderForBundleIdentifier(bundleIdentifier)) return MZSettingBool(MZSettingOtherApps, NO) && !MZIsChatApp(bundleIdentifier) && !MZIsBrowserApp(bundleIdentifier);
	return MZSettingBool([MZSettingSourcePrefix stringByAppendingString:bundleIdentifier], YES);
}

static BOOL MZGameEnabled(NSString *bundleIdentifier) {
	if (!MZSettingBool(MZSettingEnabled, YES)) return NO;
	return MZSettingBool([MZSettingGamePrefix stringByAppendingString:bundleIdentifier], YES);
}

@implementation MZPresence {
	MZDiscord *_discord;
	MZAppCatalog *_appCatalog;
	MZActivity *_shown;
	NSArray<NSString *> *_visibleApps;
	// The game showing, since it came on screen; it shows over any track.
	NSString *_game;
	NSDate *_gameStart;
	NSUInteger _gameEndGeneration;
	NSTimer *_gameRefresh;
	MZTrack *_lastTrack;
	// Kept after playback stops, for the preview.
	MZTrack *_lastPlayed;
	NSDate *_lastPlayedStopped;
	BOOL _clearPending;
	NSUInteger _clearGeneration;
}

- (instancetype)initWithDiscord:(MZDiscord *)discord appCatalog:(MZAppCatalog *)appCatalog {
	if ((self = [super init])) {
		_discord = discord;
		_appCatalog = appCatalog;
		if ([self customActivity]) [self publish];
	}

	return self;
}

- (MZActivity *)customActivity {
	if (!MZSettingBool(MZSettingEnabled, YES) || !MZSettingBool(MZSettingCustom, NO)) return nil;
	NSDictionary *preset = MZCustomPreset(MZSettingString(MZSettingCustomPreset, nil));
	if (!preset) return nil;
	MZActivity *activity = [MZActivity new];
	NSString *kind = MZPresetString(preset, MZPresetKindKey);
	activity.kind = [kind isEqualToString:@"listening"] ? MZActivityKindListening : [kind isEqualToString:@"watching"] ? MZActivityKindWatching
																													   : MZActivityKindPlaying;
	activity.statusDisplay = MZStatusDisplayName;
	// Without a name, Discord uses the application's: "Menzen".
	activity.name = MZPresetString(preset, MZPresetNameKey);
	NSString *largeImage = MZPresetString(preset, MZPresetLargeImageKey);
	if (MZCustomImageURLIsAllowed(largeImage)) activity.largeImageURL = largeImage;
	if (MZSettingBool(MZSettingPrivacy, NO)) return activity;

	activity.details = MZPresetString(preset, MZPresetDetailsKey);
	activity.state = MZPresetString(preset, MZPresetStateKey);
	// Discord only shows the texts and the small picture with a big one.
	if (activity.largeImageURL) {
		activity.largeText = MZPresetString(preset, MZPresetLargeTextKey);
		NSString *smallImage = MZPresetString(preset, MZPresetSmallImageKey);
		if (MZCustomImageURLIsAllowed(smallImage)) {
			activity.smallImageURL = smallImage;
			activity.smallText = MZPresetString(preset, MZPresetSmallTextKey);
		}
	}

	id timer = preset[MZPresetTimerKey];
	NSDate *start = MZSettingValue(MZSettingCustomStart);
	if ((![timer respondsToSelector:@selector(boolValue)] || [timer boolValue]) && [start isKindOfClass:NSDate.class]) activity.startDate = start;
	return activity;
}

- (void)publish {
	[_discord setActivity:[self customActivity] ?: _shown];
}

- (void)show:(MZActivity *)activity {
	_shown = activity;
	[self publish];
}

- (void)cancelClear {
	_clearGeneration++;
	_clearPending = NO;
}

- (void)updatePreviewWithTrack:(MZTrack *)track {
	if (MZTrackIsShowable(track)) {
		_lastPlayed = track;
		_lastPlayedStopped = nil;
	} else if (!track && !_lastPlayedStopped) {
		_lastPlayedStopped = NSDate.date;
	}

	NSDate *pausedDate;
	MZActivity *preview = _lastPlayed ? MZPreviewForTrack(_lastPlayed, [_appCatalog iconURLForApp:_lastPlayed.bundleIdentifier], _lastPlayedStopped, &pausedDate) : nil;
	[_discord setPreviewActivity:preview pausedDate:pausedDate];
}

- (void)handleTrack:(MZTrack *)track {
	_lastTrack = track;
	[self updatePreviewWithTrack:track];
	if (_game) return;

	// Stopped, closed, or a source that's switched off took over: clear now.
	if (!track || !MZSourceEnabled(track.bundleIdentifier)) {
		[self cancelClear];
		if (_shown) [self show:nil];
		return;
	}

	MZActivity *activity = MZActivityForTrack(track, [_appCatalog iconURLForApp:track.bundleIdentifier]);
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
- (void)showPaused:(MZActivity *)activity {
	NSTimeInterval grace = MZSettingDouble(MZSettingPauseGrace, MZDefaultPauseGrace);
	if (grace == 0) {
		[self cancelClear];
		[self show:nil];
		return;
	}

	if (activity) {
		[self show:activity];
	} else if (_shown.startDate) {
		MZActivity *paused = [_shown copy];
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
	MZLog(@"on screen: %@", visibleApps.count ? [visibleApps componentsJoinedByString:@", "] : @"no app");
	[self updateGame];
}

- (void)appCatalogChanged {
	[self updateGame];
}

- (void)updateGame {
	NSString *game;
	for (NSString *bundleIdentifier in _visibleApps) {
		if ([_appCatalog isGame:bundleIdentifier] && MZGameEnabled(bundleIdentifier)) {
			game = bundleIdentifier;
			break;
		}
	}

	if (game) {
		_gameEndGeneration++;
		if (![game isEqualToString:_game]) {
			MZLog(@"playing %@", game);
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
	if (!MZGameEnabled(_game)) {
		[self endGame];
		return;
	}

	NSUInteger generation = ++_gameEndGeneration;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MZGameGrace * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		typeof(self) strongSelf = weakSelf;
		if (strongSelf && generation == strongSelf->_gameEndGeneration) [strongSelf endGame];
	});
}

- (MZActivity *)activityForGame:(NSString *)bundleIdentifier {
	MZActivity *activity = [MZActivity new];
	activity.kind = MZActivityKindPlaying;
	activity.statusDisplay = MZStatusDisplayName;
	activity.name = MZAppName(bundleIdentifier);
	// Without one, Discord shows Menzen's icon.
	activity.largeImageURL = [_appCatalog iconURLForApp:bundleIdentifier];
	if (MZSettingBool(MZSettingPrivacy, NO)) return activity;
	activity.startDate = _gameStart;
	if (activity.largeImageURL) {
		activity.largeText = activity.name;
		if (MZSettingBool(MZSettingLinks, YES)) activity.largeURL = [_appCatalog storeURLForApp:bundleIdentifier];
	}

	if ([bundleIdentifier isEqualToString:MZApelinBundleIdentifier]) {
		MZApelinSession *session = MZReadApelinSession();
		NSString *project = MZSettingBool(MZSettingApelinProject, YES) ? session.project : nil;
		NSString *agent = MZSettingBool(MZSettingApelinAgent, YES) ? session.agent : nil;
		activity.details = project ?: agent;
		activity.state = project ? agent : nil;
	}

	return activity;
}

- (void)updateGameRefresh {
	if (![_game isEqualToString:MZApelinBundleIdentifier]) {
		[_gameRefresh invalidate];
		_gameRefresh = nil;
		return;
	}

	if (_gameRefresh) return;
	__weak typeof(self) weakSelf = self;
	_gameRefresh = [NSTimer scheduledTimerWithTimeInterval:MZApelinRefresh repeats:YES block:^(NSTimer *timer) {
		typeof(self) strongSelf = weakSelf;
		if (strongSelf && strongSelf->_game) [strongSelf show:[strongSelf activityForGame:strongSelf->_game]];
	}];
}

- (void)endGame {
	MZLog(@"stopped playing %@", _game);
	_game = nil;
	_gameStart = nil;
	_gameEndGeneration++;
	[self updateGameRefresh];
	MZActivity *shown = _shown;
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
