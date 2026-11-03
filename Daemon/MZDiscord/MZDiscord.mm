#import "MZDiscord.h"

#define DISCORDPP_IMPLEMENTATION
#import <Security/Security.h>

#import "../../Shared/MZService.h"
#import "MZDeviceSignIn.h"
#import "MZKeychain.h"
#include "discordpp.h"

// identify: badges, banner and Nitro for the settings pane (/users/@me).
static NSString *const MZScopes = @"openid identify sdk.social_layer_presence";
// The settings pane asks for status when opened; refetch a profile this old.
static NSTimeInterval const MZProfileMaxAge = 5 * 60;
// The gateway's close code for a token it doesn't accept.
static int32_t const MZAuthenticationFailedCloseCode = 4004;
// How long an authorize URL stays usable.
static NSTimeInterval const MZSignInTimeout = 10 * 60;
// Before the first unlock the Keychain item can't be read yet.
static NSTimeInterval const MZKeychainLockedRetry = 30;

// Access tokens last 7 days; refresh once less than a day is left.
static NSTimeInterval const MZRefreshMargin = 24 * 60 * 60;
// A new track is published almost at once. Other changes (seeks, artwork
// arriving a moment later) wait a little longer so a burst becomes one update.
static NSTimeInterval const MZNewTrackPublishDelay = 0.25;
static NSTimeInterval const MZPublishDelay = 1;
// Discord allows 5 activity updates per 20 seconds; stay one under so a
// burst (skipping through songs, pulling to refresh) waits instead of being
// rejected. Waiting updates collapse into the latest one.
static NSUInteger const MZPublishLimit = 4;
static NSTimeInterval const MZPublishWindow = 20;
// Pulling to refresh more often than this reuses the profile just fetched.
static NSTimeInterval const MZProfileMinAge = 10;
// How often callbacks run while an answer is expected, for how long after
// asking, and otherwise. Each run wakes the CPU.
static NSTimeInterval const MZFastCallbackInterval = 0.05;
static NSTimeInterval const MZBusyCallbackTime = 10;
static NSTimeInterval const MZIdleCallbackInterval = 1;

static std::string MZStdString(NSString *string) {
	return string.UTF8String ?: "";
}

// Discord rejects details/state/text outside 2...128 characters.
static NSString *MZActivityText(NSString *text) {
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

static BOOL MZSameString(NSString *a, NSString *b) {
	return a == b || [a isEqualToString:b];
}

static BOOL MZSameDate(NSDate *a, NSDate *b) {
	if (!a || !b) return a == b;
	return fabs([a timeIntervalSinceDate:b]) < 2;
}

static uint64_t MZMilliseconds(NSDate *date) {
	return (uint64_t)(date.timeIntervalSince1970 * 1000);
}

// For the OAuth state parameter: base64url, 32 random bytes.
static NSString *MZRandomString(void) {
	uint8_t bytes[32];
	if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) return nil;
	NSString *string = [[NSData dataWithBytes:bytes length:sizeof(bytes)] base64EncodedStringWithOptions:0];
	string = [string stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
	string = [string stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
	return [string stringByReplacingOccurrencesOfString:@"=" withString:@""];
}

static NSString *MZQueryValue(NSURLComponents *components, NSString *name) {
	for (NSURLQueryItem *item in components.queryItems) {
		if ([item.name isEqualToString:name]) return item.value;
	}

	return nil;
}

// As sent to Discord, for the settings pane.
static NSDictionary *MZActivityInfo(MZActivity *activity) {
	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	switch (activity.kind) {
		case MZActivityKindWatching: info[MZActivityKindKey] = @"watching"; break;
		case MZActivityKindPlaying: info[MZActivityKindKey] = @"playing"; break;
		default: info[MZActivityKindKey] = @"listening"; break;
	}

	switch (activity.statusDisplay) {
		case MZStatusDisplayState: info[MZActivityStatusDisplayKey] = @"state"; break;
		case MZStatusDisplayName: info[MZActivityStatusDisplayKey] = @"name"; break;
		default: info[MZActivityStatusDisplayKey] = @"details"; break;
	}

	info[MZActivityNameKey] = activity.name;
	info[MZActivityDetailsKey] = MZActivityText(activity.details);
	info[MZActivityStateKey] = MZActivityText(activity.state);
	if (activity.largeImageURL) {
		info[MZActivityImageURLKey] = activity.largeImageURL;
		info[MZActivityLargeTextKey] = MZActivityText(activity.largeText);
	}

	if (activity.smallImageURL) {
		info[MZActivitySmallImageURLKey] = activity.smallImageURL;
		info[MZActivitySmallTextKey] = MZActivityText(activity.smallText);
	}

	info[MZActivityDetailsURLKey] = activity.detailsURL;
	info[MZActivityStateURLKey] = activity.stateURL;
	info[MZActivityLargeURLKey] = activity.largeURL;
	if (activity.startDate) info[MZActivityStartKey] = @(activity.startDate.timeIntervalSince1970);
	if (activity.endDate) info[MZActivityEndKey] = @(activity.endDate.timeIntervalSince1970);
	return info;
}

@implementation MZActivity

- (id)copyWithZone:(NSZone *)zone {
	MZActivity *copy = [MZActivity new];
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
	copy.startDate = self.startDate;
	copy.endDate = self.endDate;
	return copy;
}

- (BOOL)isEquivalentToActivity:(MZActivity *)activity {
	if (!activity || self.kind != activity.kind || self.statusDisplay != activity.statusDisplay) return NO;
	if (!MZSameString(self.name, activity.name) || !MZSameString(self.details, activity.details) || !MZSameString(self.state, activity.state)) return NO;
	if (!MZSameString(self.largeImageURL, activity.largeImageURL) || !MZSameString(self.largeText, activity.largeText)) return NO;
	if (!MZSameString(self.smallImageURL, activity.smallImageURL) || !MZSameString(self.smallText, activity.smallText)) return NO;
	if (!MZSameString(self.detailsURL, activity.detailsURL) || !MZSameString(self.stateURL, activity.stateURL)) return NO;
	if (!MZSameString(self.largeURL, activity.largeURL) || !MZSameString(self.smallURL, activity.smallURL)) return NO;
	return MZSameDate(self.startDate, activity.startDate) && MZSameDate(self.endDate, activity.endDate);
}

@end

@implementation MZDiscord {
	uint64_t _applicationId;
	NSDictionary *_previewInfo;
	std::shared_ptr<discordpp::Client> _client;
	dispatch_source_t _callbackTimer;
	// Until when callbacks run often: something asked Discord for an answer.
	CFAbsoluteTime _busyUntil;
	BOOL _callbacksFast;
	BOOL _ready;
	// Set once the refresh token has been tried after Discord rejected the
	// access token, so a rejection can't loop.
	BOOL _rejectedTokenRefreshed;
	MZActivity *_desiredActivity;
	MZActivity *_publishedActivity;
	// Whether _publishedActivity is what Discord has; unknown after a connect.
	BOOL _publishedKnown;
	BOOL _publishPending;
	CFAbsoluteTime _publishFireTime;
	// When recent updates went out, oldest first, for MZPublishLimit.
	NSMutableArray<NSNumber *> *_publishTimes;
	// Image keys Discord couldn't find (a logo not uploaded yet), left out
	// until the next connect.
	NSMutableSet<NSString *> *_missingAssets;
	NSUInteger _refreshGeneration;
	// Bumped on sign in and out, so a refresh still in flight from the
	// previous account can't save its tokens.
	NSUInteger _accountGeneration;
	BOOL _signedIn;
	NSString *_username;
	NSString *_accountError;
	// In memory only, for the /users/@me request.
	NSString *_accessToken;
	NSDictionary<NSString *, id> *_profile;
	NSDate *_profileFetchedAt;
	NSString *_pendingVerifier;
	NSString *_pendingState;
	MZDeviceSignIn *_deviceSignIn;
	NSDate *_pendingExpiry;
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
	// Online status and name changes.
	_client->SetUserUpdatedCallback([weakSelf](uint64_t userId) {
		typeof(self) strongSelf = weakSelf;
		if (strongSelf && strongSelf->_profile && userId == strtoull([strongSelf->_profile[MZProfileIdKey] UTF8String], NULL, 10)) [strongSelf updateProfileFromClient];
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
	_busyUntil = CFAbsoluteTimeGetCurrent() + MZBusyCallbackTime;
	if (!_callbacksFast) [self setCallbacksFast:YES];
}

- (void)setCallbacksFast:(BOOL)fast {
	_callbacksFast = fast;
	NSTimeInterval interval = fast ? MZFastCallbackInterval : MZIdleCallbackInterval;
	dispatch_source_set_timer(_callbackTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), (uint64_t)(interval * NSEC_PER_SEC), (uint64_t)(interval * NSEC_PER_SEC / 2));
}

- (NSDictionary<NSString *, id> *)accountStatus {
	NSMutableDictionary *status = [NSMutableDictionary dictionary];
	status[MZStatusSignedInKey] = @(_signedIn);
	status[MZStatusConnectedKey] = @(_ready);
	status[MZStatusUsernameKey] = _username;
	status[MZStatusErrorKey] = _accountError;
	status[MZStatusProfileKey] = _profile;
	if (_ready && _publishedKnown && _publishedActivity) status[MZStatusActivityKey] = MZActivityInfo(_publishedActivity);
	status[MZStatusPreviewKey] = _previewInfo;
	return status;
}

- (void)setPreviewActivity:(MZActivity *)activity pausedDate:(NSDate *)pausedDate {
	NSMutableDictionary *info = activity ? [MZActivityInfo(activity) mutableCopy] : nil;
	if (pausedDate) info[MZActivityPausedKey] = @(pausedDate.timeIntervalSince1970);
	if ([_previewInfo isEqualToDictionary:info] || (!_previewInfo && !info)) return;
	_previewInfo = info;
	[self accountStatusChanged];
}

- (void)accountStatusChanged {
	if (self.accountStatusChangedHandler) self.accountStatusChangedHandler();
}

- (NSString *)redirectURI {
	return [NSString stringWithFormat:@"%@:/authorize/callback", MZCallbackScheme()];
}

- (NSURL *)beginSignIn {
	discordpp::AuthorizationCodeVerifier verifier = _client->CreateAuthorizationCodeVerifier();
	NSString *state = MZRandomString();
	if (!state) return nil;
	_pendingVerifier = @(verifier.Verifier().c_str());
	_pendingState = state;
	_pendingExpiry = [NSDate dateWithTimeIntervalSinceNow:MZSignInTimeout];

	NSURLComponents *components = [NSURLComponents componentsWithString:@"https://discord.com/oauth2/authorize"];
	components.queryItems = @[
		[NSURLQueryItem queryItemWithName:@"response_type" value:@"code"],
		[NSURLQueryItem queryItemWithName:@"client_id" value:[NSString stringWithFormat:@"%llu", _applicationId]],
		[NSURLQueryItem queryItemWithName:@"redirect_uri" value:self.redirectURI],
		[NSURLQueryItem queryItemWithName:@"scope" value:MZScopes],
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
	if (![components.scheme isEqualToString:MZCallbackScheme()]) {
		completion(@"Discord sent back an unexpected address. Try again.");
		return;
	}

	if (!verifier || expiry.timeIntervalSinceNow < 0) {
		completion(@"The sign-in took too long. Try again.");
		return;
	}

	if (![MZQueryValue(components, @"state") isEqualToString:expectedState]) {
		completion(@"The sign-in didn't match the one Menzen started. Try again.");
		return;
	}

	NSString *error = MZQueryValue(components, @"error");
	if (error) {
		completion([error isEqualToString:@"access_denied"] ? nil : @"Discord couldn't complete the sign-in. Try again.");
		return;
	}

	NSString *code = MZQueryValue(components, @"code");
	if (!code.length) {
		completion(@"Discord didn't send a sign-in code. Try again.");
		return;
	}

	NSUInteger generation = ++_accountGeneration;
	__weak typeof(self) weakSelf = self;
	[self expectCallbacks];
	_client->GetToken(_applicationId, MZStdString(code), MZStdString(verifier), MZStdString(self.redirectURI), [weakSelf, generation, completion](discordpp::ClientResult result, std::string accessToken, std::string refreshToken, discordpp::AuthorizationTokenType tokenType, int32_t expiresIn, std::string scopes) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf->_accountGeneration) return;

		if (!result.Successful()) {
			completion(@"Discord didn't accept the sign-in. Try again.");
			return;
		}
		completion([strongSelf signInWithAccessToken:@(accessToken.c_str()) refreshToken:@(refreshToken.c_str()) expiresIn:expiresIn]);
	});
}

- (void)beginDeviceSignInWithCodeHandler:(void (^)(NSURL *, NSString *, NSString *))codeHandler completion:(void (^)(BOOL, NSString *))completion {
	if (!_deviceSignIn) _deviceSignIn = [[MZDeviceSignIn alloc] initWithApplicationId:_applicationId scopes:MZScopes];
	__weak typeof(self) weakSelf = self;
	[_deviceSignIn startWithCodeHandler:codeHandler completion:^(NSString *accessToken, NSString *refreshToken, NSTimeInterval expiresIn, NSString *error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
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

// A message for the user when the tokens couldn't be kept.
- (NSString *)signInWithAccessToken:(NSString *)accessToken refreshToken:(NSString *)refreshToken expiresIn:(NSTimeInterval)expiresIn {
	if (![self saveAccessToken:accessToken refreshToken:refreshToken expiresIn:expiresIn]) return @"Couldn't save the sign-in to the Keychain.";
	_signedIn = YES;
	_accountError = nil;
	[self connectWithAccessToken:accessToken];
	[self scheduleRefreshAt:[NSDate dateWithTimeIntervalSinceNow:expiresIn]];
	[self accountStatusChanged];
	return nil;
}

- (void)signOut {
	NSDictionary *tokens = MZKeychainLoadTokens(NULL);
	MZKeychainDeleteTokens();

	_accountGeneration++;
	_refreshGeneration++;
	_signedIn = NO;
	_username = nil;
	_accountError = nil;
	_accessToken = nil;
	_profile = nil;
	_profileFetchedAt = nil;
	_ready = NO;
	_publishedKnown = NO;
	[self expectCallbacks];
	_client->Disconnect();

	// Revoking the refresh token ends the whole grant, so Discord forgets
	// the access token too.
	NSString *token = tokens[MZTokensRefreshTokenKey] ?: tokens[MZTokensAccessTokenKey];
	if ([token isKindOfClass:NSString.class] && token.length) {
		_client->RevokeToken(_applicationId, MZStdString(token), [](discordpp::ClientResult) {});
	}

	[self accountStatusChanged];
}

- (BOOL)saveAccessToken:(NSString *)accessToken refreshToken:(NSString *)refreshToken expiresIn:(NSTimeInterval)expiresIn {
	NSDictionary *tokens = @{
		MZTokensAccessTokenKey: accessToken,
		MZTokensRefreshTokenKey: refreshToken,
		MZTokensExpiresAtKey: [NSDate dateWithTimeIntervalSinceNow:expiresIn],
	};
	return MZKeychainSaveTokens(tokens) == errSecSuccess;
}

- (void)loadTokens {
	OSStatus status;
	NSDictionary *tokens = MZKeychainLoadTokens(&status);
	if (status == errSecInteractionNotAllowed) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MZKeychainLockedRetry * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			[self loadTokens];
		});
		return;
	}

	NSString *accessToken = tokens[MZTokensAccessTokenKey];
	NSString *refreshToken = tokens[MZTokensRefreshTokenKey];
	NSDate *expiresAt = tokens[MZTokensExpiresAtKey];

	_signedIn = accessToken.length || refreshToken.length;
	[self accountStatusChanged];
	if (!_signedIn) return;

	if (refreshToken.length && (!accessToken.length || ![expiresAt isKindOfClass:NSDate.class] || expiresAt.timeIntervalSinceNow < MZRefreshMargin)) {
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
	_client->RefreshToken(_applicationId, MZStdString(refreshToken), [weakSelf, generation, fallbackAccessToken, expiresAt](discordpp::ClientResult result, std::string accessToken, std::string newRefreshToken, discordpp::AuthorizationTokenType tokenType, int32_t expiresIn, std::string scopes) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf->_accountGeneration) return;

		if (!result.Successful()) {
			if (fallbackAccessToken.length && [expiresAt isKindOfClass:NSDate.class] && expiresAt.timeIntervalSinceNow > 0) {
				[strongSelf connectWithAccessToken:fallbackAccessToken];
			} else {
				strongSelf->_accountError = @"Discord ended the sign-in. Sign in again.";
				[strongSelf accountStatusChanged];
			}
			return;
		}

		[strongSelf saveAccessToken:@(accessToken.c_str()) refreshToken:@(newRefreshToken.c_str()) expiresIn:expiresIn];
		[strongSelf connectWithAccessToken:@(accessToken.c_str())];
		[strongSelf scheduleRefreshAt:[NSDate dateWithTimeIntervalSinceNow:expiresIn]];
	});
}

- (void)scheduleRefreshAt:(NSDate *)expiresAt {
	if (![expiresAt isKindOfClass:NSDate.class]) return;
	NSTimeInterval delay = MAX(60, expiresAt.timeIntervalSinceNow - MZRefreshMargin);
	NSUInteger generation = ++_refreshGeneration;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf->_refreshGeneration) return;
		NSDictionary *tokens = MZKeychainLoadTokens(NULL);
		NSString *refreshToken = tokens[MZTokensRefreshTokenKey];
		if (refreshToken.length) [strongSelf refreshWithToken:refreshToken fallbackAccessToken:tokens[MZTokensAccessTokenKey] expiresAt:tokens[MZTokensExpiresAtKey]];
	});
}

- (void)connectWithAccessToken:(NSString *)accessToken {
	_accessToken = accessToken;
	std::shared_ptr<discordpp::Client> client = _client;
	[self expectCallbacks];
	_client->UpdateToken(discordpp::AuthorizationTokenType::Bearer, MZStdString(accessToken), [client](discordpp::ClientResult result) {
		if (!result.Successful()) return;
		// Already connected: UpdateToken reconnects by itself if it needs to.
		if (client->GetStatus() == discordpp::Client::Status::Disconnected) client->Connect();
	});
}

- (void)statusChanged:(discordpp::Client::Status)status error:(discordpp::Client::Error)error errorDetail:(int32_t)errorDetail {
	BOOL wasReady = _ready;
	// Connecting: more is on its way.
	if (status != discordpp::Client::Status::Ready && status != discordpp::Client::Status::Disconnected) [self expectCallbacks];
	_ready = status == discordpp::Client::Status::Ready;
	if (status == discordpp::Client::Status::Disconnected && errorDetail == MZAuthenticationFailedCloseCode) [self accessTokenRejected];
	if (_ready) {
		_rejectedTokenRefreshed = NO;
		_publishedKnown = NO;
		[_missingAssets removeAllObjects];
		[self schedulePublishAfter:MZNewTrackPublishDelay];
		[self updateProfile];
	}

	if (_ready != wasReady) [self accountStatusChanged];
}

// The token was revoked or replaced before it expired.
- (void)accessTokenRejected {
	NSString *refreshToken = MZKeychainLoadTokens(NULL)[MZTokensRefreshTokenKey];
	if (!_rejectedTokenRefreshed && refreshToken.length) {
		_rejectedTokenRefreshed = YES;
		[self refreshWithToken:refreshToken fallbackAccessToken:nil expiresAt:nil];
		return;
	}

	_accountError = @"Discord ended the sign-in. Sign in again.";
	[self accountStatusChanged];
}

- (void)refreshProfileIfStale {
	if (_ready && (!_profileFetchedAt || -_profileFetchedAt.timeIntervalSinceNow > MZProfileMaxAge)) [self updateProfile];
}

- (void)refreshProfileWithCompletion:(void (^)(void))completion {
	if (_profileFetchedAt && -_profileFetchedAt.timeIntervalSinceNow < MZProfileMinAge) {
		completion();
		return;
	}

	if (!_ready || ![self updateProfileFromClient]) {
		completion();
		return;
	}

	_profileFetchedAt = NSDate.date;
	[self fetchProfileDetailsWithCompletion:completion];
}

// What the SDK knows, then the rest from /users/@me.
- (void)updateProfile {
	if (![self updateProfileFromClient]) return;
	_profileFetchedAt = NSDate.date;
	[self fetchProfileDetailsWithCompletion:nil];
}

static NSString *MZStatusName(discordpp::StatusType status) {
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

// What the SDK knows, which it keeps current by itself.
- (BOOL)updateProfileFromClient {
	std::optional<discordpp::UserHandle> user = _client->GetCurrentUserV2();
	if (!user) return NO;
	_username = @(user->DisplayName().c_str());

	NSMutableDictionary *profile = [_profile mutableCopy] ?: [NSMutableDictionary dictionary];
	profile[MZProfileIdKey] = [NSString stringWithFormat:@"%llu", user->Id()];
	profile[MZProfileUsernameKey] = @(user->Username().c_str());
	std::optional<std::string> globalName = user->GlobalName();
	profile[MZProfileGlobalNameKey] = globalName ? @(globalName->c_str()) : nil;
	profile[MZProfileAvatarURLKey] = @(user->AvatarUrl(discordpp::UserHandle::AvatarType::Png, discordpp::UserHandle::AvatarType::Png).c_str());
	profile[MZProfileStatusKey] = MZStatusName(user->Status());
	if (![profile isEqualToDictionary:_profile]) {
		_profile = profile;
		[self accountStatusChanged];
	}

	return YES;
}

static NSArray<NSString *> *MZBadges(uint64_t flags) {
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

static NSDictionary *MZDictionary(id value) {
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

// What goes into a CDN URL must stay a single path component.
static NSString *MZAssetName(id value) {
	if ([value isKindOfClass:NSNumber.class]) value = [value stringValue];
	if (![value isKindOfClass:NSString.class] || ![value length]) return nil;
	if ([value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/?#%\\"]].location != NSNotFound || [value containsString:@".."]) return nil;
	return value;
}

// A CDN folder like "nameplates/<set>/<name>/": single components, each
// ending in a slash.
static NSString *MZAssetPath(id value) {
	if (![value isKindOfClass:NSString.class] || ![value hasSuffix:@"/"]) return nil;
	NSArray<NSString *> *components = [[value substringToIndex:[value length] - 1] componentsSeparatedByString:@"/"];
	for (NSString *component in components) {
		if (!MZAssetName(component)) return nil;
	}

	return value;
}

// completion runs on the main queue once the profile has been updated.
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
		if (statusCode == 401 || statusCode == 403) profile[MZProfileLimitedKey] = @YES;
		_profile = profile;
		[self accountStatusChanged];
		return;
	}

	[profile removeObjectForKey:MZProfileLimitedKey];

	NSString *userId = profile[MZProfileIdKey];
	id banner = user[@"banner"];
	profile[MZProfileBannerURLKey] = [banner isKindOfClass:NSString.class] ? [NSString stringWithFormat:@"https://cdn.discordapp.com/banners/%@/%@.png?size=600", userId, banner] : nil;
	id accentColor = user[@"accent_color"];
	profile[MZProfileAccentColorKey] = [accentColor isKindOfClass:NSNumber.class] ? accentColor : nil;
	id premiumType = user[@"premium_type"];
	profile[MZProfilePremiumTypeKey] = [premiumType isKindOfClass:NSNumber.class] ? premiumType : nil;
	id flags = user[@"public_flags"];
	profile[MZProfileBadgesKey] = MZBadges([flags isKindOfClass:NSNumber.class] ? [flags unsignedLongLongValue] : 0);

	// The server tag shown next to the name, when the user displays one.
	NSDictionary *guild = MZDictionary(user[@"primary_guild"]);
	NSString *tag = [guild[@"tag"] isKindOfClass:NSString.class] ? guild[@"tag"] : nil;
	NSString *guildId = MZAssetName(guild[@"identity_guild_id"]);
	NSString *tagBadge = MZAssetName(guild[@"badge"]);
	BOOL showsTag = [guild[@"identity_enabled"] isKindOfClass:NSNumber.class] && [guild[@"identity_enabled"] boolValue] && tag.length;
	profile[MZProfileGuildTagKey] = showsTag ? tag : nil;
	profile[MZProfileGuildTagBadgeURLKey] = showsTag && guildId && tagBadge ? [NSString stringWithFormat:@"https://cdn.discordapp.com/guild-tag-badges/%@/%@.png?size=64", guildId, tagBadge] : nil;

	// Static frames; the animated ones are APNG and WebM.
	NSString *decoration = MZAssetName(MZDictionary(user[@"avatar_decoration_data"])[@"asset"]);
	profile[MZProfileAvatarDecorationURLKey] = decoration ? [NSString stringWithFormat:@"https://cdn.discordapp.com/avatar-decoration-presets/%@.png?size=240&passthrough=false", decoration] : nil;
	NSString *nameplate = MZAssetPath(MZDictionary(MZDictionary(user[@"collectibles"])[@"nameplate"])[@"asset"]);
	profile[MZProfileNameplateURLKey] = nameplate ? [NSString stringWithFormat:@"https://cdn.discordapp.com/assets/collectibles/%@static.png", nameplate] : nil;

	NSMutableArray *nameColors = [NSMutableArray array];
	id colors = MZDictionary(user[@"display_name_styles"])[@"colors"];
	for (id color in [colors isKindOfClass:NSArray.class] ? colors : nil) {
		if ([color isKindOfClass:NSNumber.class]) [nameColors addObject:color];
	}

	profile[MZProfileNameColorsKey] = nameColors.count ? nameColors : nil;
	_profile = profile;
	[self accountStatusChanged];
}

- (void)setActivity:(MZActivity *)activity {
	_desiredActivity = activity;
	BOOL newTrack = !_publishedKnown || !activity != !_publishedActivity || !MZSameString(activity.details, _publishedActivity.details) || !MZSameString(activity.state, _publishedActivity.state);
	[self schedulePublishAfter:newTrack ? MZNewTrackPublishDelay : MZPublishDelay];
}

- (void)republish {
	_publishedKnown = NO;
	[self schedulePublishAfter:MZPublishDelay];
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
		// Superseded by an earlier publish.
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
	if (retryAfter > 0 || result.Retryable()) [self schedulePublishAfter:MAX(retryAfter, MZPublishDelay)];
}

- (void)publish {
	if (!_ready) return;
	MZActivity *activity = _desiredActivity;
	if (_publishedKnown && (activity ? [activity isEquivalentToActivity:_publishedActivity] : !_publishedActivity)) return;

	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
	if (!_publishTimes) _publishTimes = [NSMutableArray array];
	while (_publishTimes.count && now - _publishTimes.firstObject.doubleValue >= MZPublishWindow) [_publishTimes removeObjectAtIndex:0];
	if (_publishTimes.count >= MZPublishLimit) {
		NSTimeInterval wait = _publishTimes.firstObject.doubleValue + MZPublishWindow - now;
		[self schedulePublishAfter:wait];
		return;
	}

	[_publishTimes addObject:@(now)];

	_publishedActivity = activity;
	_publishedKnown = YES;
	// The settings pane previews what Discord shows.
	[self accountStatusChanged];
	[self expectCallbacks];

	if (!activity) {
		_client->ClearRichPresence();
		return;
	}

	discordpp::Activity richPresence;
	switch (activity.kind) {
		case MZActivityKindListening: richPresence.SetType(discordpp::ActivityTypes::Listening); break;
		case MZActivityKindWatching: richPresence.SetType(discordpp::ActivityTypes::Watching); break;
		case MZActivityKindPlaying: richPresence.SetType(discordpp::ActivityTypes::Playing); break;
	}

	switch (activity.statusDisplay) {
		case MZStatusDisplayDetails: richPresence.SetStatusDisplayType(discordpp::StatusDisplayTypes::Details); break;
		case MZStatusDisplayState: richPresence.SetStatusDisplayType(discordpp::StatusDisplayTypes::State); break;
		case MZStatusDisplayName: richPresence.SetStatusDisplayType(discordpp::StatusDisplayTypes::Name); break;
	}

	if (activity.name.length) richPresence.SetName(MZStdString(activity.name));
	if (NSString *details = MZActivityText(activity.details)) {
		richPresence.SetDetails(MZStdString(details));
		if (activity.detailsURL) richPresence.SetDetailsUrl(MZStdString(activity.detailsURL));
	}

	if (NSString *state = MZActivityText(activity.state)) {
		richPresence.SetState(MZStdString(state));
		if (activity.stateURL) richPresence.SetStateUrl(MZStdString(activity.stateURL));
	}

	if (activity.largeImageURL && ![_missingAssets containsObject:activity.largeImageURL]) {
		discordpp::ActivityAssets assets;
		assets.SetLargeImage(MZStdString(activity.largeImageURL));
		if (NSString *largeText = MZActivityText(activity.largeText)) assets.SetLargeText(MZStdString(largeText));
		if (activity.largeURL) assets.SetLargeUrl(MZStdString(activity.largeURL));
		if (activity.smallImageURL && ![_missingAssets containsObject:activity.smallImageURL]) {
			assets.SetSmallImage(MZStdString(activity.smallImageURL));
			if (NSString *smallText = MZActivityText(activity.smallText)) assets.SetSmallText(MZStdString(smallText));
			if (activity.smallURL) assets.SetSmallUrl(MZStdString(activity.smallURL));
		}
		richPresence.SetAssets(assets);
	}

	if (activity.startDate) {
		discordpp::ActivityTimestamps timestamps;
		timestamps.SetStart(MZMilliseconds(activity.startDate));
		if (activity.endDate) timestamps.SetEnd(MZMilliseconds(activity.endDate));
		richPresence.SetTimestamps(timestamps);
	}

	__weak typeof(self) weakSelf = self;
	_client->UpdateRichPresence(std::move(richPresence), [weakSelf](discordpp::ClientResult result) {
		if (!result.Successful()) [weakSelf publishFailed:result];
	});
}

@end

BOOL MZSignOutStoredAccount(uint64_t applicationId, NSTimeInterval timeout) {
	OSStatus status;
	NSDictionary *tokens = MZKeychainLoadTokens(&status);
	if (!tokens) return status == errSecItemNotFound;
	status = MZKeychainDeleteTokens();
	if (status != errSecSuccess && status != errSecItemNotFound) return NO;

	NSString *token = tokens[MZTokensRefreshTokenKey] ?: tokens[MZTokensAccessTokenKey];
	if (![token isKindOfClass:NSString.class] || !token.length) return YES;

	// The tokens are gone either way; if Discord can't be reached, the
	// grant stays under Authorized Apps until the user removes it.
	bool done = false;
	auto client = std::make_shared<discordpp::Client>();
	client->SetApplicationId(applicationId);
	client->RevokeToken(applicationId, MZStdString(token), [&done](discordpp::ClientResult result) {
		done = true;
	});
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while (!done && deadline.timeIntervalSinceNow > 0) {
		discordpp::RunCallbacks();
		[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:MZFastCallbackInterval]];
	}

	return YES;
}
