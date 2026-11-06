#import <Foundation/Foundation.h>

// How the settings pane talks to menzend. The pane only ever asks for status,
// passes the sign-in redirect along and asks for app checks; tokens and the
// PKCE verifier never leave the daemon.

NS_ASSUME_NONNULL_BEGIN

static uint64_t const MenzenApplicationId = 1564329461036617748ULL;

#define MenzenServiceName @"moe.waru.menzend"
// Posted by menzend whenever what -statusWithReply: returns changes.
#define MenzenStatusChangedNotification "moe.waru.menzen.status"

// -statusWithReply: keys.
#define MenzenStatusSignedInKey @"signedIn"
#define MenzenStatusUsernameKey @"username"
#define MenzenStatusConnectedKey @"connected"
// Signed in but not connected: since when, in seconds since 1970.
#define MenzenStatusConnectingSinceKey @"connectingSince"
#define MenzenStatusErrorKey @"error"
#define MenzenStatusProfileKey @"profile"
// What Discord currently shows, when anything.
#define MenzenStatusActivityKey @"activity"
// The last song played as it would show with the current settings, for the
// settings' previews; not there until something has played.
#define MenzenStatusPreviewKey @"preview"

// Activity keys.
// listening, watching or playing.
#define MenzenActivityKindKey @"kind"
// The app playing; Discord shows "Listening to <name>".
#define MenzenActivityNameKey @"name"
#define MenzenActivityDetailsKey @"details"
#define MenzenActivityStateKey @"state"
#define MenzenActivityLargeTextKey @"largeText"
// Image URLs, or the key of an art asset on the Discord application
// (Apelin's logo).
#define MenzenActivityImageURLKey @"imageURL"
// The artist's picture and name, only with an image.
#define MenzenActivitySmallImageURLKey @"smallImageURL"
#define MenzenActivitySmallTextKey @"smallText"
// Links on the title, artist and cover.
#define MenzenActivityDetailsURLKey @"detailsURL"
#define MenzenActivityStateURLKey @"stateURL"
#define MenzenActivityLargeURLKey @"largeURL"
// Seconds since 1970; only while playing.
#define MenzenActivityStartKey @"start"
#define MenzenActivityEndKey @"end"
// Previews only: when the song was paused, so the progress bar stands still.
#define MenzenActivityPausedKey @"paused"
// details, state or name: the line next to the name in member lists.
#define MenzenActivityStatusDisplayKey @"statusDisplay"

// Profile keys. Only id, username and avatar are certain to be there.
#define MenzenProfileIdKey @"id"
#define MenzenProfileUsernameKey @"username"
#define MenzenProfileGlobalNameKey @"globalName"
#define MenzenProfileAvatarURLKey @"avatarURL"
#define MenzenProfileBannerURLKey @"bannerURL"
// 0xRRGGBB.
#define MenzenProfileAccentColorKey @"accentColor"
// 1 Nitro Classic, 2 Nitro, 3 Nitro Basic.
#define MenzenProfilePremiumTypeKey @"premiumType"
// Names such as "earlySupporter" and "hypesquadBalance", in display order.
#define MenzenProfileBadgesKey @"badges"
// The server tag and its badge image, when the user shows one.
#define MenzenProfileGuildTagKey @"guildTag"
#define MenzenProfileGuildTagBadgeURLKey @"guildTagBadgeURL"
// Drawn over the avatar at 1.2 times its size.
#define MenzenProfileAvatarDecorationURLKey @"avatarDecorationURL"
// Drawn behind the name in member lists.
#define MenzenProfileNameplateURLKey @"nameplateURL"
// online, idle, dnd, streaming, invisible or offline.
#define MenzenProfileStatusKey @"status"
// The display name's style colors (0xRRGGBB), two or more for a gradient.
#define MenzenProfileNameColorsKey @"nameColors"
// Set when the sign-in predates the identify scope, so there are no badges,
// banner or Nitro until the next sign-in.
#define MenzenProfileLimitedKey @"limited"

// -gamesWithReply: keys.
#define MenzenGameBundleIdentifierKey @"bundleIdentifier"
#define MenzenGameNameKey @"name"
// BOOL: Menzen's app list has the game, so Discord shows its icon.
#define MenzenGameListedKey @"listed"
// The icon's URL, when it's listed.
#define MenzenGameIconURLKey @"iconURL"

@protocol MenzenService
- (void)statusWithReply:(void (^)(NSDictionary<NSString *, id> *status))reply;
// Fetches the profile and reads what's playing again, then sends the activity
// to Discord even if it hasn't changed; replies once the profile is in the
// status.
- (void)refreshWithReply:(void (^)(void))reply;
// The Discord authorize URL to open. The redirect then goes to finishSignIn.
- (void)beginSignInWithReply:(void (^)(NSURL *_Nullable authorizeURL))reply;
// error is a message for the user, nil once signed in.
- (void)finishSignInWithCallbackURL:(NSURL *)callbackURL reply:(void (^)(NSString *_Nullable error))reply;
// Sign-in approved on another phone or computer: the activate page with the
// code filled in, for a QR code, and the code to type at
// discord.com/activate. menzend keeps polling Discord until the code is used
// or expires; a new begin replaces the code.
- (void)beginSignInOnOtherDeviceWithReply:(void (^)(NSURL *_Nullable verificationURL, NSString *_Nullable userCode, NSString *_Nullable error))reply;
// Replies once that code is used or expires. error is a message for the
// user; neither signedIn nor an error means the code expired.
- (void)waitForSignInOnOtherDeviceWithReply:(void (^)(BOOL signedIn, NSString *_Nullable error))reply;
- (void)cancelSignInOnOtherDevice;
- (void)signOutWithReply:(void (^)(void))reply;
// Opens the app, one with a provider, so the provider checks it, then brings
// back the app that asked once the check is saved.
- (void)checkAppWithBundleIdentifier:(NSString *)bundleIdentifier;
// The installed games (MenzenGame*Key), sorted by name.
- (void)gamesWithReply:(void (^)(NSArray<NSDictionary<NSString *, id> *> *games))reply;
// Each supported app's App Store icon URL, installed or not, by bundle ID.
- (void)appIconsWithReply:(void (^)(NSDictionary<NSString *, NSString *> *icons))reply;
@end

static inline NSString *MenzenCallbackScheme(void) {
	return [NSString stringWithFormat:@"discord-%llu", MenzenApplicationId];
}

static inline NSXPCInterface *MenzenServiceInterface(void) {
	NSXPCInterface *interface = [NSXPCInterface interfaceWithProtocol:@protocol(MenzenService)];
	NSSet *statusClasses = [NSSet setWithObjects:NSDictionary.class, NSArray.class, NSString.class, NSNumber.class, nil];
	[interface setClasses:statusClasses forSelector:@selector(statusWithReply:) argumentIndex:0 ofReply:YES];
	[interface setClasses:statusClasses forSelector:@selector(gamesWithReply:) argumentIndex:0 ofReply:YES];
	[interface setClasses:[NSSet setWithObjects:NSDictionary.class, NSString.class, nil] forSelector:@selector(appIconsWithReply:) argumentIndex:0 ofReply:YES];
	return interface;
}

// Declared for macOS only, but present on iOS.
@interface NSXPCConnection (MenzenMachService)
- (instancetype)initWithMachServiceName:(NSString *)name options:(NSXPCConnectionOptions)options;
@end

@interface NSXPCListener (MenzenMachService)
- (instancetype)initWithMachServiceName:(NSString *)name;
@end

NS_ASSUME_NONNULL_END
