#import <Foundation/Foundation.h>
#import <pwd.h>
#import <unistd.h>

#import "../Shared/MZService.h"
#import "../Shared/MZSettings.h"
#import "../Shared/MZThrottle.h"
#import "../Shared/MZTrackExtras.h"
#import "MZApps/MZAppCatalog.h"
#import "MZApps/MZAppChecker.h"
#import "MZDiscord/MZDiscord.h"
#import "MZForegroundApps/MZForegroundApps.h"
#import "MZLog/MZLog.h"
#import "MZNowPlaying/MZNowPlaying.h"
#import "MZPresence/MZPresence.h"
#import "MZServiceListener/MZServiceListener.h"

static NSTimeInterval const MZSettingsInterval = 1;

// Darwin notifications carry no data and arrive on any thread; hand them to
// the main queue's observer.
static void MZForwardSettingsChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	static MZThrottle throttle;
	dispatch_async(dispatch_get_main_queue(), ^{
		MZThrottleRun(&throttle, MZSettingsInterval, ^{
			[NSNotificationCenter.defaultCenter postNotificationName:@MZSettingsChangedNotification object:nil];
		});
	});
}

static void MZPostDarwinNotification(CFStringRef name) {
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), name, NULL, NULL, true);
}

// How long removing the package waits for Discord to revoke the tokens.
static NSTimeInterval const MZSignOutTimeout = 10;

// prerm runs this as root; the tokens are the mobile user's, as when the
// daemon runs.
static int MZSignOutForRemoval(void) {
	struct passwd *mobile = getpwnam("mobile");
	if (getuid() == 0 && mobile) {
		if (setgid(mobile->pw_gid) != 0 || setuid(mobile->pw_uid) != 0) return 1;
		setenv("HOME", mobile->pw_dir, 1);
	}

	return MZSignOutStoredAccount(MZApplicationId, MZSignOutTimeout) ? 0 : 1;
}

int main(int argc, char *argv[]) {
	@autoreleasepool {
		if (argc == 2 && strcmp(argv[1], "--sign-out") == 0) return MZSignOutForRemoval();

		MZLog(@"menzend starting");

		MZDiscord *discord = [[MZDiscord alloc] initWithApplicationId:MZApplicationId];
		discord.accountStatusChangedHandler = ^{
			MZPostDarwinNotification(CFSTR(MZStatusChangedNotification));
		};
		[discord start];

		MZAppChecker *appChecker = [MZAppChecker new];
		[appChecker start];

		MZAppCatalog *appCatalog = [MZAppCatalog new];

		MZServiceListener *service = [[MZServiceListener alloc] initWithDiscord:discord];
		service.appChecker = appChecker;
		service.appCatalog = appCatalog;
		[service start];

		MZPresence *presence = [[MZPresence alloc] initWithDiscord:discord appCatalog:appCatalog];
		MZNowPlaying *nowPlaying = [[MZNowPlaying alloc] initWithHandler:^(MZTrack *track) {
			[presence handleTrack:track];
		}];
		MZForegroundApps *foregroundApps = [[MZForegroundApps alloc] initWithHandler:^(NSArray<NSString *> *visible) {
			[presence handleVisibleApps:visible];
		}];
		appCatalog.changedHandler = ^{
			[presence appCatalogChanged];
		};
		[appCatalog start];

		// Pull to refresh in the pane: hooks look up their extras again, and
		// what's playing is read and sent even if nothing changed.
		service.refreshHandler = ^{
			MZPostDarwinNotification(CFSTR(MZRefetchNotification));
			[nowPlaying refresh];
			[discord republish];
		};

		[NSNotificationCenter.defaultCenter addObserverForName:@MZSettingsChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
			CFPreferencesAppSynchronize((__bridge CFStringRef)MZSettingsDomain);
			MZLog(@"settings changed");
			[presence settingsChanged];
		}];
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, MZForwardSettingsChanged, CFSTR(MZSettingsChangedNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

		if (![nowPlaying start]) MZLog(@"could not start the now playing observer");
		if (![foregroundApps start]) MZLog(@"could not start watching which app is on screen");
		[NSRunLoop.mainRunLoop run];
	}

	return 0;
}
