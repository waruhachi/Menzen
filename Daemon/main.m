#import <Foundation/Foundation.h>
#import <pwd.h>
#import <unistd.h>

#import "../Shared/MenzenService.h"
#import "../Shared/MenzenSettings.h"
#import "../Shared/MenzenThrottle.h"
#import "../Shared/MenzenTrackExtras.h"
#import "MenzenApps/MenzenAppCatalog.h"
#import "MenzenApps/MenzenAppChecker.h"
#import "MenzenDiscord/MenzenDiscord.h"
#import "MenzenForegroundApps/MenzenForegroundApps.h"
#import "MenzenNowPlaying/MenzenNowPlaying.h"
#import "MenzenPresence/MenzenPresence.h"
#import "MenzenServiceListener/MenzenServiceListener.h"

static NSTimeInterval const MenzenSettingsInterval = 1;

// Darwin notifications carry no data and arrive on any thread; hand them to
// the main queue's observer.
static void MenzenForwardSettingsChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	static MenzenThrottle throttle;
	dispatch_async(dispatch_get_main_queue(), ^{
		MenzenThrottleRun(&throttle, MenzenSettingsInterval, ^{
			[NSNotificationCenter.defaultCenter postNotificationName:@MenzenSettingsChangedNotification object:nil];
		});
	});
}

static void MenzenPostDarwinNotification(CFStringRef name) {
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), name, NULL, NULL, true);
}

// How long removing the package waits for Discord to revoke the tokens.
static NSTimeInterval const MenzenSignOutTimeout = 10;

// prerm runs this as root; the tokens are the mobile user's, as when the
// daemon runs.
static int MenzenSignOutForRemoval(void) {
	struct passwd *mobile = getpwnam("mobile");
	if (getuid() == 0 && mobile) {
		if (setgid(mobile->pw_gid) != 0 || setuid(mobile->pw_uid) != 0) return 1;
		setenv("HOME", mobile->pw_dir, 1);
	}

	BOOL signedOut = MenzenSignOutStoredAccount(MenzenApplicationId, MenzenSignOutTimeout);
	return signedOut ? 0 : 1;
}

int main(int argc, char *argv[]) {
	@autoreleasepool {
		if (argc == 2 && strcmp(argv[1], "--sign-out") == 0) return MenzenSignOutForRemoval();

		MenzenDiscord *discord = [[MenzenDiscord alloc] initWithApplicationId:MenzenApplicationId];
		discord.accountStatusChangedHandler = ^{
			MenzenPostDarwinNotification(CFSTR(MenzenStatusChangedNotification));
		};
		[discord start];

		MenzenAppChecker *appChecker = [MenzenAppChecker new];
		[appChecker start];

		MenzenAppCatalog *appCatalog = [MenzenAppCatalog new];

		MenzenServiceListener *service = [[MenzenServiceListener alloc] initWithDiscord:discord];
		service.appChecker = appChecker;
		service.appCatalog = appCatalog;
		[service start];

		MenzenPresence *presence = [[MenzenPresence alloc] initWithDiscord:discord appCatalog:appCatalog];
		MenzenNowPlaying *nowPlaying = [[MenzenNowPlaying alloc] initWithHandler:^(MenzenTrack *track) {
			[presence handleTrack:track];
		}];
		MenzenForegroundApps *foregroundApps = [[MenzenForegroundApps alloc] initWithHandler:^(NSArray<NSString *> *visible) {
			[presence handleVisibleApps:visible];
		}];
		appCatalog.changedHandler = ^{
			[presence appCatalogChanged];
		};
		[appCatalog start];

		// Pull to refresh in the pane: hooks look up their extras again, and
		// what's playing is read and sent even if nothing changed.
		service.refreshHandler = ^{
			MenzenPostDarwinNotification(CFSTR(MenzenRefetchNotification));
			[nowPlaying refresh];
			[discord republish];
		};

		[NSNotificationCenter.defaultCenter addObserverForName:@MenzenSettingsChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
			CFPreferencesAppSynchronize((__bridge CFStringRef)MenzenSettingsDomain);
			[presence settingsChanged];
		}];
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, MenzenForwardSettingsChanged, CFSTR(MenzenSettingsChangedNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

		[nowPlaying start];
		[foregroundApps start];
		[NSRunLoop.mainRunLoop run];
	}

	return 0;
}
