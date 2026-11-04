#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "../MenzenSupport.h"
#import "MenzenProvider.h"

static dispatch_queue_t MenzenStatusQueue(void) {
	static dispatch_queue_t queue;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		queue = dispatch_queue_create("moe.waru.menzen.status", DISPATCH_QUEUE_SERIAL);
	});
	return queue;
}

static NSString *MenzenAppVersion(void) {
	NSBundle *bundle = NSBundle.mainBundle;
	return MenzenSupportVersion(MenzenString([bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]), MenzenString([bundle objectForInfoDictionaryKey:@"CFBundleVersion"]));
}

static NSURL *MenzenStatusURL(void) {
	return [[NSURL fileURLWithPath:NSHomeDirectory()] URLByAppendingPathComponent:MenzenSupportStatusPath];
}

// Changes the status file with change, on the status queue.
static void MenzenUpdateStatus(void (^change)(NSMutableDictionary *status)) {
	dispatch_async(MenzenStatusQueue(), ^{
		NSURL *url = MenzenStatusURL();
		NSDictionary *old = [NSDictionary dictionaryWithContentsOfURL:url] ?: @{};
		NSMutableDictionary *status = [old mutableCopy];
		change(status);
		if ([status isEqualToDictionary:old]) return;
		[NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
		NSData *data = [NSPropertyListSerialization dataWithPropertyList:status format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
		[data writeToURL:url options:NSDataWritingAtomic error:nil];
	});
}

void MenzenProviderWorked(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		MenzenUpdateStatus(^(NSMutableDictionary *status) {
			status[MenzenSupportWorkedVersionKey] = MenzenAppVersion();
			status[MenzenSupportWorkedKey] = NSDate.date;
		});
	});
}

static BOOL MenzenHasOne(NSString *requirement) {
	NSArray<NSString *> *parts = [requirement componentsSeparatedByString:@" "];
	Class cls = objc_getClass(parts[0].UTF8String);
	if (!cls || parts.count > 2) return NO;
	if (parts.count == 1) return YES;
	NSString *member = parts[1];
	if (member.length < 2) return NO;
	SEL selector = NSSelectorFromString([member substringFromIndex:1]);
	switch ([member characterAtIndex:0]) {
		case '-':
			return class_getInstanceMethod(cls, selector) != NULL;
		case '+':
			return class_getClassMethod(cls, selector) != NULL;
		case '_': {
			Ivar ivar = class_getInstanceVariable(cls, member.UTF8String);
			const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
			return type && type[0] == '@';
		}
		default:
			return NO;
	}
}

static NSArray<NSString *> *MenzenMissing(NSArray<NSString *> *requirements) {
	NSMutableArray *missing = [NSMutableArray array];
	for (NSString *requirement in requirements) {
		BOOL found = NO;
		for (NSString *alternative in [requirement componentsSeparatedByString:@" | "]) {
			if ((found = MenzenHasOne(alternative))) break;
		}
		if (!found) [missing addObject:requirement];
	}

	return missing;
}

static UIViewController *MenzenTopViewController(void) {
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			if (!window.isKeyWindow) continue;
			UIViewController *top = window.rootViewController;
			while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
			return top;
		}
	}

	return nil;
}

static void MenzenAlert(NSArray<NSString *> *missing, NSUInteger attempt) {
	static BOOL answered;
	UIViewController *top = MenzenTopViewController();
	if (answered || attempt >= 10) return;
	if (!top) {
		// The app's first screen isn't up yet.
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			MenzenAlert(missing, attempt + 1);
		});
		return;
	}

	NSBundle *bundle = NSBundle.mainBundle;
	NSString *app = MenzenString([bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"]) ?: MenzenString([bundle objectForInfoDictionaryKey:@"CFBundleName"]);
	if (!app) app = bundle.bundleIdentifier;
	NSString *version = MenzenAppVersion();
	NSString *details = MenzenSupportDetails(app, version, bundle.bundleIdentifier, @MENZEN_VERSION, UIDevice.currentDevice.systemVersion, missing);
	// Only once the user has seen it.
	void (^seen)(void) = ^{
		answered = YES;
		MenzenUpdateStatus(^(NSMutableDictionary *status) {
			status[MenzenSupportAlertedVersionKey] = version;
		});
	};

	NSString *message = [NSString stringWithFormat:@"This version of %@ changed parts Menzen relies on, so Menzen probably can't show what you play in it until Menzen is updated. Reporting it helps get it fixed.\n\nMissing:\n%@", app, [missing componentsJoinedByString:@"\n"]];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Menzen may not work with %@ %@", app, version] message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"Report on GitHub" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		seen();
		[UIApplication.sharedApplication openURL:MenzenSupportReportURL(app, version, details) options:@{} completionHandler:nil];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Copy Details" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		seen();
		UIPasteboard.generalPasteboard.string = details;
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
		seen();
	}]];
	[top presentViewController:alert animated:YES completion:nil];

	// Apps replace their launch screens, and whatever they present, as they
	// start: show it again if it went with them.
	__weak UIAlertController *weakAlert = alert;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		if (!weakAlert.viewIfLoaded.window) MenzenAlert(missing, attempt + 1);
	});
}

// Runs the check and saves it, then tells menzend.
static void MenzenRunCheck(NSArray<NSString *> *required, NSArray<NSString *> *optional, BOOL background, void (^done)(void)) {
	NSArray *missing = MenzenMissing(required);
	NSArray *missingOptional = MenzenMissing(optional);
	NSString *version = MenzenAppVersion();
	MenzenUpdateStatus(^(NSMutableDictionary *status) {
		// Only a check says which versions the status is for.
		status[MenzenSupportAppVersionKey] = version;
		status[MenzenSupportMenzenVersionKey] = @MENZEN_VERSION;
		status[MenzenSupportCheckedKey] = NSDate.date;
		status[MenzenSupportMissingKey] = missing;
		status[MenzenSupportMissingOptionalKey] = missingOptional;
		status[MenzenSupportBackgroundKey] = @(background);
		BOOL alerted = [status[MenzenSupportAlertedVersionKey] isEqual:version];
		if (!missing.count || alerted || background) return;
		// A moment after the app's first screen is up, once per launch.
		static BOOL scheduled;
		if (scheduled) return;
		scheduled = YES;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			MenzenAlert(missing, 0);
		});
	});
	// After the status queue has written it.
	dispatch_async(MenzenStatusQueue(), ^{
		NSString *name = [@MenzenSupportCheckedNotificationPrefix stringByAppendingString:NSBundle.mainBundle.bundleIdentifier ?: @""];
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)name, NULL, NULL, true);
		if (done) dispatch_async(dispatch_get_main_queue(), done);
	});
}

void MenzenProviderCheck(NSArray<NSString *> *required, NSArray<NSString *> *optional) {
	// Every time the app comes up, once it's up: some frameworks load late,
	// and the settings pane may have opened it to check again.
	[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
		MenzenRunCheck(required, optional, NO, nil);
	}];

	// Launched in the background by menzend to check a new version: check
	// once it has started, while it still gets to run.
	__block id observer = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
		[NSNotificationCenter.defaultCenter removeObserver:observer];
		observer = nil;
		UIApplication *application = UIApplication.sharedApplication;
		if (application.applicationState != UIApplicationStateBackground) return;
		__block UIBackgroundTaskIdentifier task = [application beginBackgroundTaskWithName:@"moe.waru.menzen.check" expirationHandler:^{
			[application endBackgroundTask:task];
			task = UIBackgroundTaskInvalid;
		}];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			// Opened in the meantime: that check counts instead.
			if (application.applicationState != UIApplicationStateBackground) {
				[application endBackgroundTask:task];
				return;
			}
			MenzenRunCheck(required, optional, YES, ^{
				if (task != UIBackgroundTaskInvalid) [application endBackgroundTask:task];
			});
		});
	}];
}
