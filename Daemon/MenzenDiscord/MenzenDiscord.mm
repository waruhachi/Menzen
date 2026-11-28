#import "MenzenDiscord.h"

#define DISCORDPP_IMPLEMENTATION
#import <Security/Security.h>

#import "../../Shared/MenzenLocalization/MenzenLocalization.h"
#import "../../Shared/MenzenService.h"
#import "MenzenDeviceSignIn.h"
#import "MenzenKeychain.h"
#include "discordpp.h"

// identify: badges, banner and Nitro for the settings pane (/users/@me).
static NSString *const MenzenScopes = @"openid identify sdk.social_layer_presence";
// The settings pane asks for status when opened; refetch a profile this old.
static NSTimeInterval const MenzenProfileMaxAge = 5 * 60;
// The gateway's close code for a token it doesn't accept.
static int32_t const MenzenAuthenticationFailedCloseCode = 4004;
static NSTimeInterval const MenzenSignInTimeout = 10 * 60;
// Before the first unlock the Keychain item can't be read yet.
static NSTimeInterval const MenzenKeychainLockedRetry = 30;

// Access tokens last 7 days; refresh once less than a day is left.
static NSTimeInterval const MenzenRefreshMargin = 24 * 60 * 60;
// A refresh that fails for a reason other than Discord refusing it (no
// network, a server error) is tried again, waiting longer each time.
static NSTimeInterval const MenzenRefreshRetryFirst = 60;
static NSTimeInterval const MenzenRefreshRetryMax = 30 * 60;
// A new track is published almost at once. Other changes (seeks, artwork
// arriving a moment later) wait a little longer so a burst becomes one update.
static NSTimeInterval const MenzenNewTrackPublishDelay = 0.25;
static NSTimeInterval const MenzenPublishDelay = 1;
// Discord allows 5 activity updates per 20 seconds; stay one under so a
// burst (skipping through songs, pulling to refresh) waits instead of being
// rejected. Waiting updates collapse into the latest one.
static NSUInteger const MenzenPublishLimit = 4;
static NSTimeInterval const MenzenPublishWindow = 20;
// Pulling to refresh more often than this reuses the profile just fetched.
static NSTimeInterval const MenzenProfileMinAge = 10;
// How often callbacks run while an answer is expected, for how long after
// asking, and otherwise. Each run wakes the CPU.
static NSTimeInterval const MenzenFastCallbackInterval = 0.05;
static NSTimeInterval const MenzenBusyCallbackTime = 10;
static NSTimeInterval const MenzenIdleCallbackInterval = 1;
// The status from before Menzen changed it, and what Menzen set, kept so it
// can be put back after a restart.
static CFStringRef const MenzenStatusBeforeKey = CFSTR("statusBefore");
static CFStringRef const MenzenStatusSetKey = CFSTR("statusSet");
static CFStringRef const MenzenProfileKey = CFSTR("profile");
// After the last activity ends. Covers the gap between songs, and lets a
// status being put back reach Discord before the connection closes.
static NSTimeInterval const MenzenIdleDisconnectDelay = 5;

static std::string MenzenStdString(NSString *string) {
	return string.UTF8String ?: "";
}

// Discord rejects details/state/text outside 2...128 characters.
static NSString *MenzenActivityText(NSString *text) {
	if (!text.length) return nil;

	if (text.length > 128) {
		NSRange range = [text rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, 127)];
		if (NSMaxRange(range) > 127) range = [text rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, range.location)];
		text = [[text substringWithRange:range] stringByAppendingString:@"…"];
	}

	// Braille blank: Discord trims ordinary whitespace before checking length.
	if (text.length < 2) text = [text stringByAppendingString:@"⠀"];

	return text;
}

static BOOL MenzenSameString(NSString *a, NSString *b) {
	return a == b || [a isEqualToString:b];
}

static BOOL MenzenSameDate(NSDate *a, NSDate *b) {
	if (!a || !b) return a == b;

	return fabs([a timeIntervalSinceDate:b]) < 2;
}

// 0 for a time that isn't a real one (NaN, before 1970, after 2100), which
// can't be converted.
static uint64_t MenzenMilliseconds(NSDate *date) {
	NSTimeInterval seconds = date.timeIntervalSince1970;
	if (!isfinite(seconds) || seconds <= 0 || seconds > 4102444800) return 0;

	return (uint64_t)(seconds * 1000);
}

// Discord turning the refresh token down, as opposed to not being reached.
static BOOL MenzenRefreshRefused(discordpp::ClientResult const &result) {
	if (result.Type() != discordpp::ErrorType::HTTPError || result.Retryable()) return NO;

	int status = static_cast<int>(result.Status());

	return status >= 400 && status < 500 && status != 429;
}

static NSString *MenzenRandomString(void) {
	uint8_t bytes[32];
	if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) return nil;

	NSString *string = [[NSData dataWithBytes:bytes length:sizeof(bytes)] base64EncodedStringWithOptions:0];
	string = [string stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
	string = [string stringByReplacingOccurrencesOfString:@"/" withString:@"_"];

	return [string stringByReplacingOccurrencesOfString:@"=" withString:@""];
}

static NSString *MenzenDaemonString(CFStringRef key) {
	id value = CFBridgingRelease(CFPreferencesCopyAppValue(key, MenzenDaemonDomain));
	return [value isKindOfClass:NSString.class] ? value : nil;
}

static void MenzenSetDaemonString(CFStringRef key, NSString *value) {
	CFPreferencesSetAppValue(key, (__bridge CFStringRef)value, MenzenDaemonDomain);
	CFPreferencesAppSynchronize(MenzenDaemonDomain);
}

static BOOL MenzenArrayOf(id value, Class elementClass) {
	if (![value isKindOfClass:NSArray.class]) return NO;

	for (id element in value) {
		if (![element isKindOfClass:elementClass]) return NO;
	}

	return YES;
}

// Other processes running as mobile can write the daemon's preferences too,
// so the saved profile is only used if every field is what menzend saves.
static NSDictionary *MenzenDaemonProfile(void) {
	id value = CFBridgingRelease(CFPreferencesCopyAppValue(MenzenProfileKey, MenzenDaemonDomain));
	if (![value isKindOfClass:NSDictionary.class]) return nil;

	NSString *userId = value[MenzenProfileIdKey];
	if (![userId isKindOfClass:NSString.class] || !userId.length || [userId rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound) return nil;

	NSSet *strings = [NSSet setWithObjects:MenzenProfileIdKey, MenzenProfileUsernameKey, MenzenProfileGlobalNameKey, MenzenProfileAvatarURLKey, MenzenProfileBannerURLKey, MenzenProfileGuildTagKey, MenzenProfileGuildTagBadgeURLKey, MenzenProfileAvatarDecorationURLKey, MenzenProfileNameplateURLKey, MenzenProfileStatusKey, nil];
	NSSet *numbers = [NSSet setWithObjects:MenzenProfileAccentColorKey, MenzenProfilePremiumTypeKey, MenzenProfileLimitedKey, nil];
	__block BOOL valid = YES;

	[value enumerateKeysAndObjectsUsingBlock:^(id key, id field, BOOL *stop) {
		if ([strings containsObject:key]) valid = [field isKindOfClass:NSString.class];
		else if ([numbers containsObject:key]) valid = [field isKindOfClass:NSNumber.class];
		else if ([key isEqual:MenzenProfileBadgesKey]) valid = MenzenArrayOf(field, NSString.class);
		else if ([key isEqual:MenzenProfileNameColorsKey]) valid = MenzenArrayOf(field, NSNumber.class);
		else valid = NO;

		if (!valid) *stop = YES;
	}];

	return valid ? value : nil;
}

static void MenzenSetDaemonProfile(NSDictionary *profile) {
	CFPreferencesSetAppValue(MenzenProfileKey, (__bridge CFDictionaryRef)profile, MenzenDaemonDomain);
	CFPreferencesAppSynchronize(MenzenDaemonDomain);
}

static discordpp::StatusType MenzenStatusType(NSString *name) {
	if ([name isEqualToString:@"idle"]) return discordpp::StatusType::Idle;
	if ([name isEqualToString:@"dnd"]) return discordpp::StatusType::Dnd;
	if ([name isEqualToString:@"invisible"]) return discordpp::StatusType::Invisible;

	return discordpp::StatusType::Online;
}

static NSString *MenzenQueryValue(NSURLComponents *components, NSString *name) {
	for (NSURLQueryItem *item in components.queryItems) {
		if ([item.name isEqualToString:name]) return item.value;
	}

	return nil;
}

// Discord takes two at most, with labels of 1...32 characters and links up to
// 512.
static NSArray<NSArray<NSString *> *> *MenzenActivityButtons(NSArray<NSArray<NSString *> *> *buttons) {
	NSMutableArray *valid = [NSMutableArray array];

	for (NSArray<NSString *> *button in buttons) {
		if (valid.count == 2) break;

		NSString *label = button[0];
		if (label.length > 32) label = [label substringWithRange:[label rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, 31)]];
		if (label.length && button[1].length <= 512) [valid addObject:@[label, button[1]]];
	}

	return valid;
}

static NSDictionary *MenzenActivityInfo(MenzenActivity *activity) {
	NSMutableDictionary *info = [NSMutableDictionary dictionary];

	switch (activity.kind) {
		case MenzenActivityKindWatching: info[MenzenActivityKindKey] = @"watching"; break;
		case MenzenActivityKindPlaying: info[MenzenActivityKindKey] = @"playing"; break;
		default: info[MenzenActivityKindKey] = @"listening"; break;
	}

	switch (activity.statusDisplay) {
		case MenzenStatusDisplayState: info[MenzenActivityStatusDisplayKey] = @"state"; break;
		case MenzenStatusDisplayName: info[MenzenActivityStatusDisplayKey] = @"name"; break;
		default: info[MenzenActivityStatusDisplayKey] = @"details"; break;
	}

	info[MenzenActivityNameKey] = activity.name;
	info[MenzenActivityDetailsKey] = MenzenActivityText(activity.details);
	info[MenzenActivityStateKey] = MenzenActivityText(activity.state);

	if (activity.largeImageURL) {
		info[MenzenActivityImageURLKey] = activity.largeImageURL;
		info[MenzenActivityLargeTextKey] = MenzenActivityText(activity.largeText);
	}

	if (activity.smallImageURL) {
		info[MenzenActivitySmallImageURLKey] = activity.smallImageURL;
		info[MenzenActivitySmallTextKey] = MenzenActivityText(activity.smallText);
	}

	info[MenzenActivityDetailsURLKey] = activity.detailsURL;
	info[MenzenActivityStateURLKey] = activity.stateURL;
	info[MenzenActivityLargeURLKey] = activity.largeURL;

	if (activity.partySize > 0) {
		info[MenzenActivityPartySizeKey] = @(activity.partySize);
		info[MenzenActivityPartyMaxKey] = @(activity.partyMax);
	}

	if (activity.buttons.count) info[MenzenActivityButtonsKey] = MenzenActivityButtons(activity.buttons);
	if (activity.startDate) info[MenzenActivityStartKey] = @(activity.startDate.timeIntervalSince1970);
	if (activity.endDate) info[MenzenActivityEndKey] = @(activity.endDate.timeIntervalSince1970);

	return info;
}

@implementation MenzenActivity

- (id)copyWithZone:(NSZone *)zone {
	MenzenActivity *copy = [MenzenActivity new];
	copy.kind = self.kind;
	copy.statusDisplay = self.statusDisplay;
	copy.name = self.name;
	copy.details = self.details;
	copy.state = self.state;
	copy.largeImageURL = self.largeImageURL;
	copy.largeText = self.largeText;
	copy.smallImageURL = self.smallImageURL;
	copy.smallText = self.smallText;
	copy.detailsURL = self.detailsURL;
	copy.stateURL = self.stateURL;
	copy.largeURL = self.largeURL;
	copy.smallURL = self.smallURL;
	copy.buttons = self.buttons;
	copy.partySize = self.partySize;
	copy.partyMax = self.partyMax;
	copy.startDate = self.startDate;
	copy.endDate = self.endDate;

	return copy;
}

- (BOOL)isEquivalentToActivity:(MenzenActivity *)activity {
	if (!activity || self.kind != activity.kind || self.statusDisplay != activity.statusDisplay) return NO;
	if (!MenzenSameString(self.name, activity.name) || !MenzenSameString(self.details, activity.details) || !MenzenSameString(self.state, activity.state)) return NO;
	if (!MenzenSameString(self.largeImageURL, activity.largeImageURL) || !MenzenSameString(self.largeText, activity.largeText)) return NO;
	if (!MenzenSameString(self.smallImageURL, activity.smallImageURL) || !MenzenSameString(self.smallText, activity.smallText)) return NO;
	if (!MenzenSameString(self.detailsURL, activity.detailsURL) || !MenzenSameString(self.stateURL, activity.stateURL)) return NO;
	if (!MenzenSameString(self.largeURL, activity.largeURL) || !MenzenSameString(self.smallURL, activity.smallURL)) return NO;
	if (self.partySize != activity.partySize || self.partyMax != activity.partyMax) return NO;
	if (!(self.buttons.count == 0 && activity.buttons.count == 0) && ![self.buttons isEqualToArray:activity.buttons]) return NO;

	return MenzenSameDate(self.startDate, activity.startDate) && MenzenSameDate(self.endDate, activity.endDate);
}

@end

@implementation MenzenDiscord {
	uint64_t _applicationId;
	NSDictionary *_previewInfo;
	std::shared_ptr<discordpp::Client> _client;
	dispatch_source_t _callbackTimer;
	CFAbsoluteTime _busyUntil;
	BOOL _callbacksFast;
	BOOL _ready;
	// Set once the refresh token has been tried after Discord rejected the
	// access token, so a rejection can't loop.
	BOOL _rejectedTokenRefreshed;
	MenzenActivity *_desiredActivity;
	MenzenActivity *_publishedActivity;
	BOOL _publishedKnown;
	BOOL _publishPending;
	CFAbsoluteTime _publishFireTime;
	NSMutableArray<NSNumber *> *_publishTimes;
	// Image keys Discord couldn't find (a logo not uploaded yet), left out
	// until the next connect.
	NSMutableSet<NSString *> *_missingAssets;
	NSUInteger _refreshGeneration;
	NSTimeInterval _refreshRetryDelay;
	// Tokens Discord sent that couldn't be saved to the Keychain yet: the
	// refresh token in it may be the only one that still works.
	NSDictionary *_unsavedTokens;
	// Bumped on sign in and out, so a refresh still in flight from the
	// previous account can't save its tokens.
	NSUInteger _accountGeneration;
	BOOL _signedIn;
	NSString *_username;
	NSString *_accountError;
	NSDate *_connectingSince;
	// In memory only, for the /users/@me request.
	NSString *_accessToken;
	NSDictionary<NSString *, id> *_profile;
	NSDate *_profileFetchedAt;
	NSString *_pendingVerifier;
	NSString *_pendingState;
	MenzenDeviceSignIn *_deviceSignIn;
	NSDate *_pendingExpiry;
	NSString *_statusOverride;
	// The connection counts as a Discord session and keeps the account
	// online, so it's only open while there's something to show.
	BOOL _connectionWanted;
	NSUInteger _connectionGeneration;
	BOOL _tokenSet;
}

- (instancetype)initWithApplicationId:(uint64_t)applicationId {
	if ((self = [super init])) _applicationId = applicationId;
	return self;
}

- (void)start {
	_client = std::make_shared<discordpp::Client>();
	_client->SetApplicationId(_applicationId);

	__weak typeof(self) weakSelf = self;
	_client->SetStatusChangedCallback([weakSelf](discordpp::Client::Status status, discordpp::Client::Error error, int32_t errorDetail) {
		[weakSelf statusChanged:status error:error errorDetail:errorDetail];
	});

	_client->SetUserUpdatedCallback([weakSelf](uint64_t userId) {
		typeof(self) strongSelf = weakSelf;
		NSString *profileId = strongSelf ? strongSelf->_profile[MenzenProfileIdKey] : nil;
		if ([profileId isKindOfClass:NSString.class] && userId == strtoull(profileId.UTF8String, NULL, 10)) [strongSelf updateProfileFromClient];
	});

	// The SDK only delivers callbacks from RunCallbacks, so everything above
	// and below runs on the main thread. Often while waiting for an answer,
	// rarely otherwise (only status and profile changes come unasked).
	_callbackTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());

	dispatch_source_set_event_handler(_callbackTimer, ^{
		discordpp::RunCallbacks();
		typeof(self) strongSelf = weakSelf;
		if (strongSelf && strongSelf->_callbacksFast && CFAbsoluteTimeGetCurrent() > strongSelf->_busyUntil) [strongSelf setCallbacksFast:NO];
	});

	[self setCallbacksFast:NO];
	dispatch_resume(_callbackTimer);

	[self loadTokens];
}

- (void)expectCallbacks {
	_busyUntil = CFAbsoluteTimeGetCurrent() + MenzenBusyCallbackTime;
	if (!_callbacksFast) [self setCallbacksFast:YES];
}

- (void)setCallbacksFast:(BOOL)fast {
	_callbacksFast = fast;
	NSTimeInterval interval = fast ? MenzenFastCallbackInterval : MenzenIdleCallbackInterval;
	dispatch_source_set_timer(_callbackTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), (uint64_t)(interval * NSEC_PER_SEC), (uint64_t)(interval * NSEC_PER_SEC / 2));
}

- (NSDictionary<NSString *, id> *)accountStatus {
	NSMutableDictionary *status = [NSMutableDictionary dictionary];
	status[MenzenStatusSignedInKey] = @(_signedIn);
	// Disconnected on purpose, so there's nothing to wait for.
	status[MenzenStatusConnectedKey] = @(_ready || !_connectionWanted);
	if (_signedIn && !_ready && _connectionWanted && _connectingSince) status[MenzenStatusConnectingSinceKey] = @(_connectingSince.timeIntervalSince1970);
	status[MenzenStatusUsernameKey] = _username ?: _profile[MenzenProfileUsernameKey];
	status[MenzenStatusErrorKey] = _accountError;
	// While disconnected, the status saved with it: the one picked in
	// Discord, which stays on the account.
	status[MenzenStatusProfileKey] = _profile;
	if (_ready && _publishedKnown && _publishedActivity) status[MenzenStatusActivityKey] = MenzenActivityInfo(_publishedActivity);
	status[MenzenStatusPreviewKey] = _previewInfo;

	return status;
}

- (void)setPreviewActivity:(MenzenActivity *)activity pausedDate:(NSDate *)pausedDate {
	NSMutableDictionary *info = activity ? [MenzenActivityInfo(activity) mutableCopy] : nil;
	if (pausedDate) info[MenzenActivityPausedKey] = @(pausedDate.timeIntervalSince1970);
	if ([_previewInfo isEqualToDictionary:info] || (!_previewInfo && !info)) return;

	_previewInfo = info;
	[self accountStatusChanged];
}

- (void)accountStatusChanged {
	if (self.accountStatusChangedHandler) self.accountStatusChangedHandler();
}

- (void)setProfile:(NSDictionary *)profile {
	_profile = profile;
	MenzenSetDaemonProfile(profile);
	[self accountStatusChanged];
	[self updateConnection];
}

// Connected while there's an activity to show, or until the profile is
// known after signing in.
- (void)updateConnection {
	BOOL wanted = _signedIn && (_desiredActivity || !_profile);
	BOOL changed = wanted != _connectionWanted;
	_connectionWanted = wanted;
	[self applyStatus];
	if (!changed) return;

	NSUInteger generation = ++_connectionGeneration;
	[self accountStatusChanged];

	if (wanted) {
		if (!_ready && !_connectingSince) _connectingSince = NSDate.date;
		[self connectIfWanted];
		return;
	}

	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MenzenIdleDisconnectDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf->_connectionGeneration) return;

		strongSelf->_connectingSince = nil;
		[strongSelf expectCallbacks];
		strongSelf->_client->Disconnect();
	});
}

- (void)connectIfWanted {
	if (!_connectionWanted || !_tokenSet || _client->GetStatus() != discordpp::Client::Status::Disconnected) return;

	[self expectCallbacks];
	_client->Connect();
}

- (NSString *)redirectURI {
	return [NSString stringWithFormat:@"%@:/authorize/callback", MenzenCallbackScheme()];
}

- (NSURL *)beginSignIn {
	discordpp::AuthorizationCodeVerifier verifier = _client->CreateAuthorizationCodeVerifier();
	NSString *state = MenzenRandomString();
	if (!state) return nil;

	_pendingVerifier = @(verifier.Verifier().c_str());
	_pendingState = state;
	_pendingExpiry = [NSDate dateWithTimeIntervalSinceNow:MenzenSignInTimeout];

	NSURLComponents *components = [NSURLComponents componentsWithString:@"https://discord.com/oauth2/authorize"];
	components.queryItems = @[
		[NSURLQueryItem queryItemWithName:@"response_type" value:@"code"],
		[NSURLQueryItem queryItemWithName:@"client_id" value:[NSString stringWithFormat:@"%llu", _applicationId]],
		[NSURLQueryItem queryItemWithName:@"redirect_uri" value:self.redirectURI],
		[NSURLQueryItem queryItemWithName:@"scope" value:MenzenScopes],
		[NSURLQueryItem queryItemWithName:@"state" value:state],
		[NSURLQueryItem queryItemWithName:@"code_challenge" value:@(verifier.Challenge().Challenge().c_str())],
		[NSURLQueryItem queryItemWithName:@"code_challenge_method" value:@"S256"],
	];

	[self expectCallbacks];

	return components.URL;
}

- (void)finishSignInWithCallbackURL:(NSURL *)callbackURL completion:(void (^)(NSString *))completion {
	// Each authorize URL is good for one redirect.
	NSString *verifier = _pendingVerifier;
	NSString *expectedState = _pendingState;
	NSDate *expiry = _pendingExpiry;
	_pendingVerifier = nil;
	_pendingState = nil;
	_pendingExpiry = nil;

	NSURLComponents *components = [NSURLComponents componentsWithURL:callbackURL resolvingAgainstBaseURL:NO];

	if (![components.scheme isEqualToString:MenzenCallbackScheme()]) {
		completion(MenzenLocalizedString(@"signin.error.discord_sent_back_an_unexpected_address", @"Discord sent back an unexpected address. Try again."));
		return;
	}

	if (!verifier || expiry.timeIntervalSinceNow < 0) {
		completion(MenzenLocalizedString(@"signin.error.the_sign_in_took_too_long", @"The sign-in took too long. Try again."));
		return;
	}

	if (![MenzenQueryValue(components, @"state") isEqualToString:expectedState]) {
		completion(MenzenLocalizedString(@"signin.error.the_sign_in_didn_t_match", @"The sign-in didn't match the one Menzen started. Try again."));
		return;
	}

	NSString *error = MenzenQueryValue(components, @"error");

	if (error) {
		completion([error isEqualToString:@"access_denied"] ? nil : MenzenLocalizedString(@"signin.error.discord_couldn_t_complete_the_sign", @"Discord couldn't complete the sign-in. Try again."));
		return;
	}

	NSString *code = MenzenQueryValue(components, @"code");

	if (!code.length) {
		completion(MenzenLocalizedString(@"signin.error.discord_didn_t_send_a_sign", @"Discord didn't send a sign-in code. Try again."));
		return;
	}

	NSUInteger generation = ++_accountGeneration;
	__weak typeof(self) weakSelf = self;
	[self expectCallbacks];

	_client->GetToken(_applicationId, MenzenStdString(code), MenzenStdString(verifier), MenzenStdString(self.redirectURI), [weakSelf, generation, completion](discordpp::ClientResult result, std::string accessToken, std::string refreshToken, discordpp::AuthorizationTokenType tokenType, int32_t expiresIn, std::string scopes) {
		typeof(self) strongSelf = weakSelf;

		// Signed out, or another sign-in took over, in the meantime.
		if (!strongSelf || generation != strongSelf->_accountGeneration) {
			completion(nil);
			return;
		}

		if (!result.Successful()) {
			completion(MenzenLocalizedString(@"signin.error.discord_didn_t_accept_the_sign", @"Discord didn't accept the sign-in. Try again."));
			return;
		}

		completion([strongSelf signInWithAccessToken:@(accessToken.c_str()) refreshToken:@(refreshToken.c_str()) expiresIn:expiresIn]);
	});
}

- (void)beginDeviceSignInWithCodeHandler:(void (^)(NSURL *, NSString *, NSString *))codeHandler completion:(void (^)(BOOL, NSString *))completion {
	if (!_deviceSignIn) _deviceSignIn = [[MenzenDeviceSignIn alloc] initWithApplicationId:_applicationId scopes:MenzenScopes];
	NSUInteger generation = _accountGeneration;
	__weak typeof(self) weakSelf = self;
	[_deviceSignIn startWithCodeHandler:codeHandler completion:^(NSString *accessToken, NSString *refreshToken, NSTimeInterval expiresIn, NSString *error) {
		typeof(self) strongSelf = weakSelf;

		// Signed out, or another sign-in took over, in the meantime.
		if (!strongSelf || generation != strongSelf->_accountGeneration) {
			completion(NO, nil);
			return;
		}

		if (!accessToken) {
			completion(NO, error);
			return;
		}

		NSString *saveError = [strongSelf signInWithAccessToken:accessToken refreshToken:refreshToken expiresIn:expiresIn];
		completion(!saveError, saveError);
	}];
}

- (void)cancelDeviceSignIn {
	[_deviceSignIn cancel];
}

- (NSString *)signInWithAccessToken:(NSString *)accessToken refreshToken:(NSString *)refreshToken expiresIn:(NSTimeInterval)expiresIn {
	if (![self saveAccessToken:accessToken refreshToken:refreshToken expiresIn:expiresIn]) {
		// Not kept for later: the user is told it didn't work.
		_unsavedTokens = nil;
		return MenzenLocalizedString(@"signin.error.couldn_t_save_the_sign_in", @"Couldn't save the sign-in to the Keychain.");
	}

	// Anything still under way for the account before is out of date.
	_accountGeneration++;
	_signedIn = YES;
	_accountError = nil;
	[self connectWithAccessToken:accessToken];
	[self scheduleRefreshAt:[NSDate dateWithTimeIntervalSinceNow:expiresIn]];
	[self accountStatusChanged];

	return nil;
}

- (void)signOut {
	NSDictionary *tokens = MenzenKeychainLoadTokens(NULL);
	MenzenKeychainDeleteTokens();

	[_deviceSignIn cancel];
	_pendingVerifier = nil;
	_pendingState = nil;
	_pendingExpiry = nil;

	_accountGeneration++;
	_refreshGeneration++;
	_refreshRetryDelay = 0;
	_unsavedTokens = nil;
	_signedIn = NO;
	_username = nil;
	_accountError = nil;
	_accessToken = nil;
	_profile = nil;
	MenzenSetDaemonProfile(nil);
	_profileFetchedAt = nil;
	_ready = NO;
	_connectingSince = nil;
	_publishedKnown = NO;
	_connectionWanted = NO;
	_connectionGeneration++;
	_tokenSet = NO;

	MenzenSetDaemonString(MenzenStatusBeforeKey, nil);
	MenzenSetDaemonString(MenzenStatusSetKey, nil);

	[self expectCallbacks];
	_client->Disconnect();

	// Revoking the refresh token ends the whole grant, so Discord forgets
	// the access token too.
	NSString *token = tokens[MenzenTokensRefreshTokenKey] ?: tokens[MenzenTokensAccessTokenKey];

	if ([token isKindOfClass:NSString.class] && token.length) {
		_client->RevokeToken(_applicationId, MenzenStdString(token), [](discordpp::ClientResult) {});
	}

	[self accountStatusChanged];
}

- (BOOL)saveAccessToken:(NSString *)accessToken refreshToken:(NSString *)refreshToken expiresIn:(NSTimeInterval)expiresIn {
	NSDictionary *tokens = @{
		MenzenTokensAccessTokenKey: accessToken,
		MenzenTokensRefreshTokenKey: refreshToken,
		MenzenTokensExpiresAtKey: [NSDate dateWithTimeIntervalSinceNow:expiresIn],
	};

	if (MenzenKeychainSaveTokens(tokens) == errSecSuccess) {
		_unsavedTokens = nil;
		return YES;
	}

	_unsavedTokens = tokens;
	[self saveTokensLater];

	return NO;
}

- (void)saveTokensLater {
	NSUInteger generation = _accountGeneration;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MenzenKeychainLockedRetry * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf->_accountGeneration || !strongSelf->_unsavedTokens) return;

		if (MenzenKeychainSaveTokens(strongSelf->_unsavedTokens) == errSecSuccess) {
			strongSelf->_unsavedTokens = nil;
		} else {
			[strongSelf saveTokensLater];
		}
	});
}

- (NSDictionary *)currentTokens {
	return _unsavedTokens ?: MenzenKeychainLoadTokens(NULL);
}

- (void)loadTokens {
	OSStatus status;
	NSDictionary *tokens = MenzenKeychainLoadTokens(&status);

	if (status == errSecInteractionNotAllowed) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MenzenKeychainLockedRetry * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			[self loadTokens];
		});

		return;
	}

	NSString *accessToken = tokens[MenzenTokensAccessTokenKey];
	NSString *refreshToken = tokens[MenzenTokensRefreshTokenKey];
	NSDate *expiresAt = tokens[MenzenTokensExpiresAtKey];

	_signedIn = accessToken.length || refreshToken.length;
	// Shown until Discord connects, and while idle.
	if (_signedIn && !_profile) _profile = MenzenDaemonProfile();
	[self accountStatusChanged];
	if (!_signedIn) return;

	if (refreshToken.length && (!accessToken.length || ![expiresAt isKindOfClass:NSDate.class] || expiresAt.timeIntervalSinceNow < MenzenRefreshMargin)) {
		[self refreshWithToken:refreshToken fallbackAccessToken:accessToken expiresAt:expiresAt];
		return;
	}

	[self connectWithAccessToken:accessToken];
	[self scheduleRefreshAt:expiresAt];
}

- (void)refreshWithToken:(NSString *)refreshToken fallbackAccessToken:(NSString *)fallbackAccessToken expiresAt:(NSDate *)expiresAt {
	NSUInteger generation = _accountGeneration;
	__weak typeof(self) weakSelf = self;
	[self expectCallbacks];

	_client->RefreshToken(_applicationId, MenzenStdString(refreshToken), [weakSelf, generation, fallbackAccessToken, expiresAt](discordpp::ClientResult result, std::string accessToken, std::string newRefreshToken, discordpp::AuthorizationTokenType tokenType, int32_t expiresIn, std::string scopes) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf->_accountGeneration) return;

		if (!result.Successful()) {
			BOOL refused = MenzenRefreshRefused(result);

			if (!refused) {
				strongSelf->_refreshRetryDelay = MIN(MenzenRefreshRetryMax, MAX(MenzenRefreshRetryFirst, strongSelf->_refreshRetryDelay * 2));
				[strongSelf scheduleRefreshAfter:strongSelf->_refreshRetryDelay];
			}

			if (fallbackAccessToken.length && [expiresAt isKindOfClass:NSDate.class] && expiresAt.timeIntervalSinceNow > 0) {
				[strongSelf connectWithAccessToken:fallbackAccessToken];
			} else if (refused) {
				strongSelf->_accountError = MenzenLocalizedString(@"signin.error.discord_ended_the_sign_in_sign", @"Discord ended the sign-in. Sign in again.");
				[strongSelf accountStatusChanged];
			}

			return;
		}

		strongSelf->_refreshRetryDelay = 0;
		[strongSelf saveAccessToken:@(accessToken.c_str()) refreshToken:@(newRefreshToken.c_str()) expiresIn:expiresIn];
		[strongSelf connectWithAccessToken:@(accessToken.c_str())];
		[strongSelf scheduleRefreshAt:[NSDate dateWithTimeIntervalSinceNow:expiresIn]];
	});
}

- (void)scheduleRefreshAt:(NSDate *)expiresAt {
	if (![expiresAt isKindOfClass:NSDate.class]) return;

	[self scheduleRefreshAfter:MAX(60, expiresAt.timeIntervalSinceNow - MenzenRefreshMargin)];
}

- (void)scheduleRefreshAfter:(NSTimeInterval)delay {
	NSUInteger generation = ++_refreshGeneration;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf->_refreshGeneration) return;

		NSDictionary *tokens = [strongSelf currentTokens];
		NSString *refreshToken = tokens[MenzenTokensRefreshTokenKey];
		if (refreshToken.length) [strongSelf refreshWithToken:refreshToken fallbackAccessToken:tokens[MenzenTokensAccessTokenKey] expiresAt:tokens[MenzenTokensExpiresAtKey]];
	});
}

- (void)connectWithAccessToken:(NSString *)accessToken {
	_accessToken = accessToken;
	[self expectCallbacks];

	__weak typeof(self) weakSelf = self;
	_client->UpdateToken(discordpp::AuthorizationTokenType::Bearer, MenzenStdString(accessToken), [weakSelf](discordpp::ClientResult result) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || !result.Successful()) return;

		strongSelf->_tokenSet = YES;
		// Already connected: UpdateToken reconnects by itself if it needs to.
		[strongSelf connectIfWanted];
	});

	[self updateConnection];
}

- (void)statusChanged:(discordpp::Client::Status)status error:(discordpp::Client::Error)error errorDetail:(int32_t)errorDetail {
	BOOL wasReady = _ready;
	if (status != discordpp::Client::Status::Ready && status != discordpp::Client::Status::Disconnected) [self expectCallbacks];
	_ready = status == discordpp::Client::Status::Ready;

	if (_ready) {
		_connectingSince = nil;
	} else if (wasReady && _connectionWanted) {
		_connectingSince = NSDate.date;
	}

	if (status == discordpp::Client::Status::Disconnected && errorDetail == MenzenAuthenticationFailedCloseCode) [self accessTokenRejected];

	if (_ready) {
		_rejectedTokenRefreshed = NO;
		_publishedKnown = NO;
		[_missingAssets removeAllObjects];

		[self schedulePublishAfter:MenzenNewTrackPublishDelay];
		[self updateProfile];
		[self applyStatus];
	}

	if (_ready != wasReady) [self accountStatusChanged];
}

- (void)accessTokenRejected {
	NSString *refreshToken = [self currentTokens][MenzenTokensRefreshTokenKey];

	if (!_rejectedTokenRefreshed && refreshToken.length) {
		_rejectedTokenRefreshed = YES;
		[self refreshWithToken:refreshToken fallbackAccessToken:nil expiresAt:nil];

		return;
	}

	_accountError = MenzenLocalizedString(@"signin.error.discord_ended_the_sign_in_sign", @"Discord ended the sign-in. Sign in again.");
	[self accountStatusChanged];
}

- (void)refreshProfileIfStale {
	if (_ready && (!_profileFetchedAt || -_profileFetchedAt.timeIntervalSinceNow > MenzenProfileMaxAge)) [self updateProfile];
}

- (void)refreshProfileWithCompletion:(void (^)(void))completion {
	if (_profileFetchedAt && -_profileFetchedAt.timeIntervalSinceNow < MenzenProfileMinAge) {
		completion();
		return;
	}

	// Disconnected while idle: the saved profile's details still refresh.
	if (_ready ? ![self updateProfileFromClient] : !_profile) {
		completion();
		return;
	}

	_profileFetchedAt = NSDate.date;
	[self fetchProfileDetailsWithCompletion:completion];
}

- (void)updateProfile {
	if (![self updateProfileFromClient]) return;

	_profileFetchedAt = NSDate.date;
	[self fetchProfileDetailsWithCompletion:nil];
}

static NSString *MenzenStatusName(discordpp::StatusType status) {
	switch (status) {
		case discordpp::StatusType::Online: return @"online";
		case discordpp::StatusType::Idle: return @"idle";
		case discordpp::StatusType::Dnd: return @"dnd";
		case discordpp::StatusType::Streaming: return @"streaming";
		case discordpp::StatusType::Invisible: return @"invisible";
		case discordpp::StatusType::Offline: return @"offline";
		default: return nil;
	}
}

- (void)setStatusOverride:(NSString *)status {
	if (MenzenSameString(_statusOverride, status)) return;

	_statusOverride = [status copy];
	[self applyStatus];
}

- (void)applyStatus {
	if (!_ready) return;

	std::optional<discordpp::UserHandle> user = _client->GetCurrentUserV2();
	if (!user) return;

	NSString *current = MenzenStatusName(user->Status());
	if (![@[@"online", @"idle", @"dnd", @"invisible"] containsObject:current]) current = nil;
	NSString *before = MenzenDaemonString(MenzenStatusBeforeKey);
	// Put back before disconnecting: the status outlasts the connection.
	NSString *override = _connectionWanted ? _statusOverride : nil;
	NSString *target;

	if (override) {
		if (!before) MenzenSetDaemonString(MenzenStatusBeforeKey, current ?: @"online");
		MenzenSetDaemonString(MenzenStatusSetKey, override);
		target = override;
	} else {
		if (!before) return;

		NSString *set = MenzenDaemonString(MenzenStatusSetKey);
		MenzenSetDaemonString(MenzenStatusBeforeKey, nil);
		MenzenSetDaemonString(MenzenStatusSetKey, nil);
		// Changed by hand since: that one stays.
		if (set && current && ![current isEqualToString:set]) return;

		target = before;
	}

	if ([current isEqualToString:target]) return;

	[self expectCallbacks];
	_client->SetOnlineStatus(MenzenStatusType(target), [](discordpp::ClientResult) {});
}

- (BOOL)updateProfileFromClient {
	std::optional<discordpp::UserHandle> user = _client->GetCurrentUserV2();
	if (!user) return NO;

	_username = @(user->DisplayName().c_str());

	NSMutableDictionary *profile = [_profile mutableCopy] ?: [NSMutableDictionary dictionary];
	profile[MenzenProfileIdKey] = [NSString stringWithFormat:@"%llu", user->Id()];
	profile[MenzenProfileUsernameKey] = @(user->Username().c_str());
	std::optional<std::string> globalName = user->GlobalName();
	profile[MenzenProfileGlobalNameKey] = globalName ? @(globalName->c_str()) : nil;
	profile[MenzenProfileAvatarURLKey] = @(user->AvatarUrl(discordpp::UserHandle::AvatarType::Png, discordpp::UserHandle::AvatarType::Png).c_str());
	profile[MenzenProfileStatusKey] = MenzenStatusName(user->Status());

	if (![profile isEqualToDictionary:_profile]) [self setProfile:profile];

	return YES;
}

static NSArray<NSString *> *MenzenBadges(uint64_t flags) {
	static const struct {
		uint64_t flag;
		NSString *badge;
	} badges[] = {
		{1 << 0, @"staff"},
		{1 << 1, @"partner"},
		{1 << 18, @"moderatorAlumni"},
		{1 << 2, @"hypesquad"},
		{1 << 6, @"hypesquadBravery"},
		{1 << 7, @"hypesquadBrilliance"},
		{1 << 8, @"hypesquadBalance"},
		{1 << 3, @"bugHunter"},
		{1 << 14, @"bugHunterGold"},
		{1 << 22, @"activeDeveloper"},
		{1 << 17, @"earlyVerifiedBotDeveloper"},
		{1 << 9, @"earlySupporter"},
	};

	NSMutableArray *result = [NSMutableArray array];

	for (size_t i = 0; i < sizeof(badges) / sizeof(*badges); i++) {
		if (flags & badges[i].flag) [result addObject:badges[i].badge];
	}

	return result;
}

static NSDictionary *MenzenDictionary(id value) {
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

// What goes into a CDN URL must stay a single path component.
static NSString *MenzenAssetName(id value) {
	if ([value isKindOfClass:NSNumber.class]) value = [value stringValue];
	if (![value isKindOfClass:NSString.class] || ![value length]) return nil;
	if ([value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/?#%\\"]].location != NSNotFound || [value containsString:@".."]) return nil;

	return value;
}

static NSString *MenzenAssetPath(id value) {
	if (![value isKindOfClass:NSString.class] || ![value hasSuffix:@"/"]) return nil;

	NSArray<NSString *> *components = [[value substringToIndex:[value length] - 1] componentsSeparatedByString:@"/"];

	for (NSString *component in components) {
		if (!MenzenAssetName(component)) return nil;
	}

	return value;
}

- (void)fetchProfileDetailsWithCompletion:(void (^)(void))completion {
	if (!_accessToken.length) {
		if (completion) completion();
		return;
	}

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://discord.com/api/v10/users/@me"]];
	[request setValue:[@"Bearer " stringByAppendingString:_accessToken] forHTTPHeaderField:@"Authorization"];

	static NSURLSession *session;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
	});

	NSUInteger generation = _accountGeneration;
	__weak typeof(self) weakSelf = self;
	[[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		NSInteger statusCode = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
		NSDictionary *user = statusCode == 200 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (strongSelf && generation == strongSelf->_accountGeneration && strongSelf->_profile) [strongSelf applyProfileDetails:[user isKindOfClass:NSDictionary.class] ? user : nil statusCode:statusCode];
			if (completion) completion();
		});
	}] resume];
}

- (void)applyProfileDetails:(NSDictionary *)user statusCode:(NSInteger)statusCode {
	NSMutableDictionary *profile = [_profile mutableCopy];

	if (!user) {
		// Signed in before the identify scope was asked for.
		if (statusCode == 401 || statusCode == 403) profile[MenzenProfileLimitedKey] = @YES;
		[self setProfile:profile];

		return;
	}

	[profile removeObjectForKey:MenzenProfileLimitedKey];

	NSString *userId = profile[MenzenProfileIdKey];

	id banner = user[@"banner"];
	profile[MenzenProfileBannerURLKey] = [banner isKindOfClass:NSString.class] ? [NSString stringWithFormat:@"https://cdn.discordapp.com/banners/%@/%@.png?size=600", userId, banner] : nil;

	id accentColor = user[@"accent_color"];
	profile[MenzenProfileAccentColorKey] = [accentColor isKindOfClass:NSNumber.class] ? accentColor : nil;

	id premiumType = user[@"premium_type"];
	profile[MenzenProfilePremiumTypeKey] = [premiumType isKindOfClass:NSNumber.class] ? premiumType : nil;

	id flags = user[@"public_flags"];
	profile[MenzenProfileBadgesKey] = MenzenBadges([flags isKindOfClass:NSNumber.class] ? [flags unsignedLongLongValue] : 0);

	NSDictionary *guild = MenzenDictionary(user[@"primary_guild"]);
	NSString *tag = [guild[@"tag"] isKindOfClass:NSString.class] ? guild[@"tag"] : nil;

	NSString *guildId = MenzenAssetName(guild[@"identity_guild_id"]);
	NSString *tagBadge = MenzenAssetName(guild[@"badge"]);

	BOOL showsTag = [guild[@"identity_enabled"] isKindOfClass:NSNumber.class] && [guild[@"identity_enabled"] boolValue] && tag.length;
	profile[MenzenProfileGuildTagKey] = showsTag ? tag : nil;
	profile[MenzenProfileGuildTagBadgeURLKey] = showsTag && guildId && tagBadge ? [NSString stringWithFormat:@"https://cdn.discordapp.com/guild-tag-badges/%@/%@.png?size=64", guildId, tagBadge] : nil;

	// Static frames; the animated ones are APNG and WebM.
	NSString *decoration = MenzenAssetName(MenzenDictionary(user[@"avatar_decoration_data"])[@"asset"]);
	profile[MenzenProfileAvatarDecorationURLKey] = decoration ? [NSString stringWithFormat:@"https://cdn.discordapp.com/avatar-decoration-presets/%@.png?size=240&passthrough=false", decoration] : nil;
	NSString *nameplate = MenzenAssetPath(MenzenDictionary(MenzenDictionary(user[@"collectibles"])[@"nameplate"])[@"asset"]);
	profile[MenzenProfileNameplateURLKey] = nameplate ? [NSString stringWithFormat:@"https://cdn.discordapp.com/assets/collectibles/%@static.png", nameplate] : nil;

	NSMutableArray *nameColors = [NSMutableArray array];
	id colors = MenzenDictionary(user[@"display_name_styles"])[@"colors"];

	for (id color in [colors isKindOfClass:NSArray.class] ? colors : nil) {
		if ([color isKindOfClass:NSNumber.class]) [nameColors addObject:color];
	}

	profile[MenzenProfileNameColorsKey] = nameColors.count ? nameColors : nil;
	[self setProfile:profile];
}

- (void)setActivity:(MenzenActivity *)activity {
	_desiredActivity = activity;
	[self updateConnection];
	BOOL newTrack = !_publishedKnown || !activity != !_publishedActivity || !MenzenSameString(activity.details, _publishedActivity.details) || !MenzenSameString(activity.state, _publishedActivity.state);
	[self schedulePublishAfter:newTrack ? MenzenNewTrackPublishDelay : MenzenPublishDelay];
}

- (void)republish {
	_publishedKnown = NO;
	[self schedulePublishAfter:MenzenPublishDelay];
}

// Publishes the latest activity `delay` after the first change. Not restarted
// by later changes: some apps (SoundCloud) update every 0.5 s while playing,
// which would otherwise keep pushing the publish back forever. A change that
// needs a shorter delay moves a pending publish earlier.
- (void)schedulePublishAfter:(NSTimeInterval)delay {
	CFAbsoluteTime fireTime = CFAbsoluteTimeGetCurrent() + delay;
	if (_publishPending && fireTime >= _publishFireTime) return;

	_publishPending = YES;
	_publishFireTime = fireTime;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || !strongSelf->_publishPending || strongSelf->_publishFireTime != fireTime) return;

		strongSelf->_publishPending = NO;
		[strongSelf publish];
	});
}

- (void)publishFailed:(discordpp::ClientResult &)result {
	// An image key Discord doesn't know fails the whole update: send it again
	// without that image.
	NSString *error = @(result.Error().c_str());
	NSRange keyRange = [error rangeOfString:@"image asset: "];

	if ([error hasPrefix:@"Unable to resolve"] && keyRange.location != NSNotFound) {
		NSString *key = [[error substringFromIndex:NSMaxRange(keyRange)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

		if (key.length && ![_missingAssets containsObject:key]) {
			if (!_missingAssets) _missingAssets = [NSMutableSet set];
			[_missingAssets addObject:key];
			_publishedKnown = NO;
			[self schedulePublishAfter:0];

			return;
		}
	}

	// Discord no longer has what we think it has; send the latest again,
	// after the wait Discord asked for when rate limited.
	_publishedKnown = NO;
	float retryAfter = result.RetryAfter();
	if (retryAfter > 0 || result.Retryable()) [self schedulePublishAfter:MAX(retryAfter, MenzenPublishDelay)];
}

- (void)publish {
	if (!_ready) return;

	MenzenActivity *activity = _desiredActivity;
	if (_publishedKnown && (activity ? [activity isEquivalentToActivity:_publishedActivity] : !_publishedActivity)) return;

	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
	if (!_publishTimes) _publishTimes = [NSMutableArray array];
	while (_publishTimes.count && now - _publishTimes.firstObject.doubleValue >= MenzenPublishWindow) [_publishTimes removeObjectAtIndex:0];

	if (_publishTimes.count >= MenzenPublishLimit) {
		NSTimeInterval wait = _publishTimes.firstObject.doubleValue + MenzenPublishWindow - now;
		[self schedulePublishAfter:wait];

		return;
	}

	[_publishTimes addObject:@(now)];

	_publishedActivity = activity;
	_publishedKnown = YES;
	[self accountStatusChanged];
	[self expectCallbacks];

	if (!activity) {
		_client->ClearRichPresence();
		return;
	}

	discordpp::Activity richPresence;

	switch (activity.kind) {
		case MenzenActivityKindListening: richPresence.SetType(discordpp::ActivityTypes::Listening); break;
		case MenzenActivityKindWatching: richPresence.SetType(discordpp::ActivityTypes::Watching); break;
		case MenzenActivityKindPlaying: richPresence.SetType(discordpp::ActivityTypes::Playing); break;
	}

	switch (activity.statusDisplay) {
		case MenzenStatusDisplayDetails: richPresence.SetStatusDisplayType(discordpp::StatusDisplayTypes::Details); break;
		case MenzenStatusDisplayState: richPresence.SetStatusDisplayType(discordpp::StatusDisplayTypes::State); break;
		case MenzenStatusDisplayName: richPresence.SetStatusDisplayType(discordpp::StatusDisplayTypes::Name); break;
	}

	if (activity.name.length) richPresence.SetName(MenzenStdString(activity.name));

	if (NSString *details = MenzenActivityText(activity.details)) {
		richPresence.SetDetails(MenzenStdString(details));
		if (activity.detailsURL) richPresence.SetDetailsUrl(MenzenStdString(activity.detailsURL));
	}

	if (NSString *state = MenzenActivityText(activity.state)) {
		richPresence.SetState(MenzenStdString(state));
		if (activity.stateURL) richPresence.SetStateUrl(MenzenStdString(activity.stateURL));
	}

	if (activity.largeImageURL && ![_missingAssets containsObject:activity.largeImageURL]) {
		discordpp::ActivityAssets assets;
		assets.SetLargeImage(MenzenStdString(activity.largeImageURL));
		if (NSString *largeText = MenzenActivityText(activity.largeText)) assets.SetLargeText(MenzenStdString(largeText));
		if (activity.largeURL) assets.SetLargeUrl(MenzenStdString(activity.largeURL));

		if (activity.smallImageURL && ![_missingAssets containsObject:activity.smallImageURL]) {
			assets.SetSmallImage(MenzenStdString(activity.smallImageURL));
			if (NSString *smallText = MenzenActivityText(activity.smallText)) assets.SetSmallText(MenzenStdString(smallText));
			if (activity.smallURL) assets.SetSmallUrl(MenzenStdString(activity.smallURL));
		}

		richPresence.SetAssets(assets);
	}

	if (activity.partySize > 0) {
		discordpp::ActivityParty party;
		// Discord ignores a party without an id.
		party.SetId("menzen");
		party.SetCurrentSize((int32_t)activity.partySize);
		party.SetMaxSize((int32_t)activity.partyMax);
		richPresence.SetParty(party);
	}

	for (NSArray<NSString *> *button in MenzenActivityButtons(activity.buttons)) {
		discordpp::ActivityButton activityButton;
		activityButton.SetLabel(MenzenStdString(button[0]));
		activityButton.SetUrl(MenzenStdString(button[1]));
		richPresence.AddButton(activityButton);
	}

	uint64_t start = MenzenMilliseconds(activity.startDate);

	if (start) {
		discordpp::ActivityTimestamps timestamps;
		timestamps.SetStart(start);
		uint64_t end = MenzenMilliseconds(activity.endDate);
		if (end > start) timestamps.SetEnd(end);
		richPresence.SetTimestamps(timestamps);
	}

	__weak typeof(self) weakSelf = self;
	_client->UpdateRichPresence(std::move(richPresence), [weakSelf](discordpp::ClientResult result) {
		if (!result.Successful()) [weakSelf publishFailed:result];
	});
}

@end

BOOL MenzenSignOutStoredAccount(uint64_t applicationId, NSTimeInterval timeout) {
	OSStatus status;
	NSDictionary *tokens = MenzenKeychainLoadTokens(&status);
	if (!tokens) return status == errSecItemNotFound;

	status = MenzenKeychainDeleteTokens();
	if (status != errSecSuccess && status != errSecItemNotFound) return NO;

	MenzenSetDaemonProfile(nil);

	NSString *token = tokens[MenzenTokensRefreshTokenKey] ?: tokens[MenzenTokensAccessTokenKey];
	if (![token isKindOfClass:NSString.class] || !token.length) return YES;

	// The tokens are gone either way; if Discord can't be reached, the
	// grant stays under Authorized Apps until the user removes it.
	bool done = false;
	auto client = std::make_shared<discordpp::Client>();
	client->SetApplicationId(applicationId);

	client->RevokeToken(applicationId, MenzenStdString(token), [&done](discordpp::ClientResult result) {
		done = true;
	});

	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];

	while (!done && deadline.timeIntervalSinceNow > 0) {
		discordpp::RunCallbacks();
		[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:MenzenFastCallbackInterval]];
	}

	return YES;
}
