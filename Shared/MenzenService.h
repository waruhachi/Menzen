#import <Foundation/Foundation.h>

// Tokens and the PKCE verifier never leave menzend.

static uint64_t const MenzenApplicationId = 1564329461036617748ULL;

#define MenzenServiceName @"moe.waru.menzend"
#define MenzenDaemonDomain CFSTR("moe.waru.menzend")
#define MenzenStatusChangedNotification "moe.waru.menzen.status"

#define MenzenStatusSignedInKey @"signedIn"
#define MenzenStatusUsernameKey @"username"
#define MenzenStatusConnectedKey @"connected"
#define MenzenStatusConnectingSinceKey @"connectingSince"
#define MenzenStatusErrorKey @"error"
#define MenzenStatusProfileKey @"profile"
#define MenzenStatusActivityKey @"activity"
#define MenzenStatusPreviewKey @"preview"

#define MenzenActivityKindKey @"kind"
#define MenzenActivityNameKey @"name"
#define MenzenActivityDetailsKey @"details"
#define MenzenActivityStateKey @"state"
#define MenzenActivityLargeTextKey @"largeText"
#define MenzenActivityImageURLKey @"imageURL"
#define MenzenActivitySmallImageURLKey @"smallImageURL"
#define MenzenActivitySmallTextKey @"smallText"
#define MenzenActivityDetailsURLKey @"detailsURL"
#define MenzenActivityStateURLKey @"stateURL"
#define MenzenActivityLargeURLKey @"largeURL"
#define MenzenActivityStartKey @"start"
#define MenzenActivityEndKey @"end"
#define MenzenActivityPausedKey @"paused"
// details, state or name: the line next to the name in member lists.
#define MenzenActivityStatusDisplayKey @"statusDisplay"

#define MenzenProfileIdKey @"id"
#define MenzenProfileUsernameKey @"username"
#define MenzenProfileGlobalNameKey @"globalName"
#define MenzenProfileAvatarURLKey @"avatarURL"
#define MenzenProfileBannerURLKey @"bannerURL"
#define MenzenProfileAccentColorKey @"accentColor"
// 1 Nitro Classic, 2 Nitro, 3 Nitro Basic.
#define MenzenProfilePremiumTypeKey @"premiumType"
#define MenzenProfileBadgesKey @"badges"
#define MenzenProfileGuildTagKey @"guildTag"
#define MenzenProfileGuildTagBadgeURLKey @"guildTagBadgeURL"
// Drawn over the avatar at 1.2 times its size.
#define MenzenProfileAvatarDecorationURLKey @"avatarDecorationURL"
#define MenzenProfileNameplateURLKey @"nameplateURL"
#define MenzenProfileStatusKey @"status"
#define MenzenProfileNameColorsKey @"nameColors"
#define MenzenProfileLimitedKey @"limited"

#define MenzenGameBundleIdentifierKey @"bundleIdentifier"
#define MenzenGameNameKey @"name"
#define MenzenGameListedKey @"listed"
#define MenzenGameIconURLKey @"iconURL"

@protocol MenzenService
- (void)statusWithReply:(void (^)(NSDictionary<NSString *, id> *status))reply;
- (void)refreshWithReply:(void (^)(void))reply;
- (void)beginSignInWithReply:(void (^)(NSURL *authorizeURL))reply;
- (void)finishSignInWithCallbackURL:(NSURL *)callbackURL reply:(void (^)(NSString *error))reply;
- (void)beginSignInOnOtherDeviceWithReply:(void (^)(NSURL *verificationURL, NSString *userCode, NSString *error))reply;
- (void)waitForSignInOnOtherDeviceWithReply:(void (^)(BOOL signedIn, NSString *error))reply;
- (void)cancelSignInOnOtherDevice;
- (void)signOutWithReply:(void (^)(void))reply;
- (void)checkAppWithBundleIdentifier:(NSString *)bundleIdentifier;
- (void)gamesWithReply:(void (^)(NSArray<NSDictionary<NSString *, id> *> *games))reply;
- (void)appIconsWithReply:(void (^)(NSDictionary<NSString *, NSString *> *icons))reply;
- (void)removeConnectedApp:(NSString *)identifier reply:(void (^)(void))reply;
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
