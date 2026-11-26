#import <Security/Security.h>
#import <roothide.h>
#import <stdlib.h>
#import <sys/param.h>

#import "../../Shared/MenzenConnectedApps.h"
#import "../../Shared/MenzenService.h"
#import "../MenzenApps/MenzenAppCatalog.h"
#import "../MenzenApps/MenzenAppChecker.h"
#import "../MenzenApps/MenzenAppInfo.h"
#import "../MenzenCodeSigning/MenzenCodeSigning.h"
#import "../MenzenDiscord/MenzenDiscord.h"
#import "MenzenServiceListener.h"

// Weak, as it's newer than proc_pidpath.
extern int proc_pidpath_audittoken(audit_token_t *token, void *buffer, uint32_t size) __attribute__((weak_import));

#define MenzenCodeSignValid 0x00000001
#define MenzenCodeSignPlatformBinary 0x04000000

// TweakSettings's signing identifier is made up when it's signed
// ("TweakSettings.<hash>.unsigned"), so it's known by its application
// identifier instead.
static NSString *const MenzenTweakSettingsIdentifier = @"com.creaturecoding.tweaksettings";
// R3v4mp's own app for tweak settings. Its signing identifier is made up when
// it's signed, like TweakSettings's, and it has no application identifier,
// so it's known by where it's installed, which only root can write to.
static NSString *const MenzenR3v4mpIdentifier = @"com.samuel.r3v4mp.app";

static BOOL MenzenIsR3v4mp(audit_token_t token) {
	static NSString *executable;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		char *path = realpath(jbroot("/Applications/R3v4mpApp.app/R3v4mpApp"), NULL);
		if (path) executable = @(path);
		free(path);
	});
	char path[MAXPATHLEN] = {};
	return executable && proc_pidpath_audittoken && proc_pidpath_audittoken(&token, path, sizeof(path)) > 0 && [executable isEqualToString:@(path)];
}

// The bundle ID of the app the pane is in, nil for any other process. The
// audit token identifies the process that sent the connection, unlike its
// pid, which can be reused. Only platform binaries and R3v4mp: App Store
// apps never are, whatever they're signed as.
static NSString *MenzenSettingsApp(NSXPCConnection *connection) {
	audit_token_t token = connection.auditToken;
	if (MenzenIsR3v4mp(token)) return MenzenR3v4mpIdentifier;
	SecTaskRef task = SecTaskCreateWithAuditToken(kCFAllocatorDefault, token);
	if (!task) return nil;
	NSString *identifier = CFBridgingRelease(SecTaskCopySigningIdentifier(task, NULL));
	id application = CFBridgingRelease(SecTaskCopyValueForEntitlement(task, CFSTR("application-identifier"), NULL));
	uint32_t flags = SecTaskGetCodeSignStatus(task);
	CFRelease(task);
	if (!(flags & MenzenCodeSignValid) || !(flags & MenzenCodeSignPlatformBinary)) return nil;

	if ([identifier isEqualToString:@"com.apple.Preferences"]) return identifier;
	if ([application isKindOfClass:NSString.class] && [application isEqualToString:MenzenTweakSettingsIdentifier]) return MenzenTweakSettingsIdentifier;
	return nil;
}

@interface MenzenServiceListener () <NSXPCListenerDelegate, MenzenService>
@end

@implementation MenzenServiceListener {
	MenzenDiscord *_discord;
	NSXPCListener *_listener;
	// The pane's wait for the code it was shown, or the result when that
	// comes first.
	void (^_deviceSignInWaiter)(BOOL signedIn, NSString *error);
	BOOL _deviceSignInFinished;
	BOOL _deviceSignInSignedIn;
	NSString *_deviceSignInError;
}

- (instancetype)initWithDiscord:(MenzenDiscord *)discord {
	if ((self = [super init])) _discord = discord;
	return self;
}

- (void)start {
	_listener = [[NSXPCListener alloc] initWithMachServiceName:MenzenServiceName];
	_listener.delegate = self;
	[_listener resume];
}

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
	if (!MenzenSettingsApp(connection)) return NO;
	connection.exportedInterface = MenzenServiceInterface();
	connection.exportedObject = self;
	[connection resume];
	return YES;
}

// Calls arrive on the connection's queue; MenzenDiscord lives on the main queue.

- (void)statusWithReply:(void (^)(NSDictionary<NSString *, id> *))reply {
	dispatch_async(dispatch_get_main_queue(), ^{
		reply(self->_discord.accountStatus);
		[self->_discord refreshProfileIfStale];
	});
}

- (void)refreshWithReply:(void (^)(void))reply {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self.refreshHandler) self.refreshHandler();
		[self->_discord refreshProfileWithCompletion:reply];
	});
}

- (void)beginSignInWithReply:(void (^)(NSURL *))reply {
	dispatch_async(dispatch_get_main_queue(), ^{
		reply([self->_discord beginSignIn]);
	});
}

- (void)finishSignInWithCallbackURL:(NSURL *)callbackURL reply:(void (^)(NSString *))reply {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self->_discord finishSignInWithCallbackURL:callbackURL completion:reply];
	});
}

- (void)beginSignInOnOtherDeviceWithReply:(void (^)(NSURL *, NSString *, NSString *))reply {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self resetDeviceSignInWait];
		[self->_discord beginDeviceSignInWithCodeHandler:reply completion:^(BOOL signedIn, NSString *error) {
			[self deviceSignInFinished:signedIn error:error];
		}];
	});
}

- (void)waitForSignInOnOtherDeviceWithReply:(void (^)(BOOL, NSString *))reply {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self->_deviceSignInFinished) {
			BOOL signedIn = self->_deviceSignInSignedIn;
			NSString *error = self->_deviceSignInError;
			[self resetDeviceSignInWait];
			reply(signedIn, error);
		} else {
			self->_deviceSignInWaiter = reply;
		}
	});
}

- (void)cancelSignInOnOtherDevice {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self resetDeviceSignInWait];
		[self->_discord cancelDeviceSignIn];
	});
}

- (void)deviceSignInFinished:(BOOL)signedIn error:(NSString *)error {
	void (^waiter)(BOOL, NSString *) = _deviceSignInWaiter;
	[self resetDeviceSignInWait];
	if (waiter) {
		waiter(signedIn, error);
	} else {
		_deviceSignInFinished = YES;
		_deviceSignInSignedIn = signedIn;
		_deviceSignInError = error;
	}
}

- (void)resetDeviceSignInWait {
	_deviceSignInWaiter = nil;
	_deviceSignInFinished = NO;
	_deviceSignInSignedIn = NO;
	_deviceSignInError = nil;
}

- (void)checkAppWithBundleIdentifier:(NSString *)bundleIdentifier {
	NSString *returnTo = MenzenSettingsApp(NSXPCConnection.currentConnection);
	if (![bundleIdentifier isKindOfClass:NSString.class] || !returnTo) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.appChecker openAppToCheck:bundleIdentifier returningTo:returnTo];
	});
}

- (void)gamesWithReply:(void (^)(NSArray<NSDictionary<NSString *, id> *> *))reply {
	dispatch_async(dispatch_get_main_queue(), ^{
		NSMutableArray *games = [NSMutableArray array];
		for (NSString *bundleIdentifier in self.appCatalog.installedGames) {
			NSMutableDictionary *game = [NSMutableDictionary dictionary];
			game[MenzenGameBundleIdentifierKey] = bundleIdentifier;
			game[MenzenGameNameKey] = MenzenAppName(bundleIdentifier);
			NSString *iconURL = [self.appCatalog iconURLForApp:bundleIdentifier];
			game[MenzenGameListedKey] = @(iconURL != nil);
			game[MenzenGameIconURLKey] = iconURL;
			[games addObject:game];
		}
		[games sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
			return [a[MenzenGameNameKey] localizedStandardCompare:b[MenzenGameNameKey]];
		}];
		reply(games);
		[self.appCatalog checkIfStale];
	});
}

- (void)appIconsWithReply:(void (^)(NSDictionary<NSString *, NSString *> *))reply {
	dispatch_async(dispatch_get_main_queue(), ^{
		reply(self.appCatalog.providerIcons ?: @{});
	});
}

- (void)removeConnectedApp:(NSString *)identifier reply:(void (^)(void))reply {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (MenzenConnectedIdentifierIsValid(identifier) && self.removeConnectedAppHandler) self.removeConnectedAppHandler(identifier);
		reply();
	});
}

- (void)signOutWithReply:(void (^)(void))reply {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self->_discord signOut];
		reply();
	});
}

@end
