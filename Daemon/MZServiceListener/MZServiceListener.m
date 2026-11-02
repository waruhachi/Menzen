#import <Security/Security.h>

#import "../../Shared/MZService.h"
#import "../MZApps/MZAppCatalog.h"
#import "../MZApps/MZAppChecker.h"
#import "../MZApps/MZAppInfo.h"
#import "../MZDiscord/MZDiscord.h"
#import "../MZLog/MZLog.h"
#import "MZServiceListener.h"

// Private, but present on iOS.
@interface NSXPCConnection (MZAuditToken)
@property (nonatomic, readonly) audit_token_t auditToken;
@end

typedef struct __SecTask *SecTaskRef;
extern SecTaskRef SecTaskCreateWithAuditToken(CFAllocatorRef allocator, audit_token_t token);
extern CFStringRef SecTaskCopySigningIdentifier(SecTaskRef task, CFErrorRef *error);
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error);
extern uint32_t SecTaskGetCodeSignStatus(SecTaskRef task);

#define MZCodeSignValid 0x00000001
#define MZCodeSignPlatformBinary 0x04000000

// TweakSettings's signing identifier is made up when it's signed
// ("TweakSettings.<hash>.unsigned"), so it's known by its application
// identifier instead.
static NSString *const MZTweakSettingsIdentifier = @"com.creaturecoding.tweaksettings";

// The bundle ID of the app the pane is in, nil for any other process. The
// audit token identifies the process that sent the connection, unlike its
// pid, which can be reused. Only platform binaries: App Store apps never are,
// whatever they're signed as.
static NSString *MZSettingsApp(NSXPCConnection *connection) {
	SecTaskRef task = SecTaskCreateWithAuditToken(kCFAllocatorDefault, connection.auditToken);
	if (!task) return nil;
	NSString *identifier = CFBridgingRelease(SecTaskCopySigningIdentifier(task, NULL));
	id application = CFBridgingRelease(SecTaskCopyValueForEntitlement(task, CFSTR("application-identifier"), NULL));
	uint32_t flags = SecTaskGetCodeSignStatus(task);
	CFRelease(task);
	if (!(flags & MZCodeSignValid) || !(flags & MZCodeSignPlatformBinary)) {
		MZLog(@"refused pid %d, %@ (%@): not a valid platform binary, flags 0x%x", connection.processIdentifier, identifier, application, flags);
		return nil;
	}

	if ([identifier isEqualToString:@"com.apple.Preferences"]) return identifier;
	if ([application isKindOfClass:NSString.class] && [application isEqualToString:MZTweakSettingsIdentifier]) return MZTweakSettingsIdentifier;
	MZLog(@"refused pid %d, %@ (%@)", connection.processIdentifier, identifier, application);
	return nil;
}

@interface MZServiceListener () <NSXPCListenerDelegate, MZService>
@end

@implementation MZServiceListener {
	MZDiscord *_discord;
	NSXPCListener *_listener;
	// The pane's wait for the code it was shown, or the result when that
	// comes first.
	void (^_deviceSignInWaiter)(BOOL signedIn, NSString *error);
	BOOL _deviceSignInFinished;
	BOOL _deviceSignInSignedIn;
	NSString *_deviceSignInError;
}

- (instancetype)initWithDiscord:(MZDiscord *)discord {
	if ((self = [super init])) _discord = discord;
	return self;
}

- (void)start {
	_listener = [[NSXPCListener alloc] initWithMachServiceName:MZServiceName];
	_listener.delegate = self;
	[_listener resume];
}

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
	if (!MZSettingsApp(connection)) return NO;
	connection.exportedInterface = MZServiceInterface();
	connection.exportedObject = self;
	[connection resume];
	return YES;
}

// Calls arrive on the connection's queue; MZDiscord lives on the main queue.

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
	NSString *returnTo = MZSettingsApp(NSXPCConnection.currentConnection);
	if (![bundleIdentifier isKindOfClass:NSString.class] || !returnTo) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.appChecker openAppToCheck:bundleIdentifier returningTo:returnTo];
	});
}

- (void)gamesWithReply:(void (^)(NSArray<NSDictionary<NSString *, id> *> *))reply {
	dispatch_async(dispatch_get_main_queue(), ^{
		NSMutableArray *games = [NSMutableArray array];
		for (NSString *bundleIdentifier in self.appCatalog.installedGames) {
			[games addObject:@{
				MZGameBundleIdentifierKey: bundleIdentifier,
				MZGameNameKey: MZAppName(bundleIdentifier),
				MZGameListedKey: @([self.appCatalog iconURLForApp:bundleIdentifier] != nil),
			}];
		}
		[games sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
			return [a[MZGameNameKey] localizedStandardCompare:b[MZGameNameKey]];
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

- (void)signOutWithReply:(void (^)(void))reply {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self->_discord signOut];
		reply();
	});
}

@end
