#import <Preferences/PSSpecifier.h>

#import "../../Shared/MenzenConnectedApps.h"
#import "../../Shared/MenzenLocalization/MenzenLocalization.h"
#import "MenzenConnectedListController.h"

static void MenzenConnectedAppsChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	MenzenConnectedListController *controller = (__bridge MenzenConnectedListController *)observer;
	dispatch_async(dispatch_get_main_queue(), ^{
		CFPreferencesAppSynchronize((__bridge CFStringRef)MenzenSettingsDomain);
		[controller reloadSpecifiers];
	});
}

@implementation MenzenConnectedListController

- (void)viewDidLoad {
	[super viewDidLoad];
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self, MenzenConnectedAppsChanged, CFSTR(MenzenConnectedAppsChangedNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)dealloc {
	CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self, CFSTR(MenzenConnectedAppsChangedNotification), NULL);
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specifiers = [NSMutableArray array];
		PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
		[group setProperty:MenzenLocalizedString(@"connected.other_tweaks_can_show_activity", @"Other tweaks can show their own activity through Menzen, each only once you allow it below.") forKey:@"footerText"];
		[specifiers addObject:group];
		PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:MenzenLocalizedString(@"priority.connected_apps", @"Connected Apps") target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
		enabled.identifier = MenzenSettingConnected;
		[enabled setProperty:MenzenSettingConnected forKey:@"key"];
		[enabled setProperty:@NO forKey:@"default"];
		[enabled setProperty:MenzenSettingsDomain forKey:@"defaults"];
		[enabled setProperty:@MenzenSettingsChangedNotification forKey:@"PostNotification"];
		[specifiers addObject:enabled];

		NSDictionary<NSString *, NSDictionary *> *apps = MenzenConnectedApps();
		PSSpecifier *appsGroup = [PSSpecifier groupSpecifierWithName:MenzenLocalizedString(@"connected.apps", @"Apps")];
		[appsGroup setProperty:apps.count ? MenzenLocalizedString(@"connected.apps_show_here_the_first", @"Apps show here the first time they ask. The one that updated last shows.") : MenzenLocalizedString(@"connected.no_apps_have_asked_yet", @"No apps have asked yet. Apps show here the first time they ask.") forKey:@"footerText"];
		[specifiers addObject:appsGroup];
		NSArray<NSString *> *identifiers = [apps.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
			return [apps[a][MenzenConnectedAppNameKey] localizedCaseInsensitiveCompare:apps[b][MenzenConnectedAppNameKey]];
		}];
		for (NSString *identifier in identifiers) {
			PSSpecifier *app = [PSSpecifier preferenceSpecifierNamed:apps[identifier][MenzenConnectedAppNameKey] target:self set:@selector(setAllowed:specifier:) get:@selector(allowed:) detail:nil cell:PSSwitchCell edit:nil];
			app.identifier = identifier;
			[specifiers addObject:app];
		}

		_specifiers = specifiers;
	}

	return _specifiers;
}

- (NSNumber *)allowed:(PSSpecifier *)specifier {
	return @([MenzenConnectedAllowed() containsObject:specifier.identifier]);
}

- (void)setAllowed:(NSNumber *)allowed specifier:(PSSpecifier *)specifier {
	NSMutableArray<NSString *> *identifiers = [MenzenConnectedAllowed() mutableCopy];
	[identifiers removeObject:specifier.identifier];
	if (allowed.boolValue) [identifiers addObject:specifier.identifier];
	CFPreferencesSetAppValue((__bridge CFStringRef)MenzenSettingConnectedAllowed, (__bridge CFArrayRef)identifiers, (__bridge CFStringRef)MenzenSettingsDomain);
	CFPreferencesAppSynchronize((__bridge CFStringRef)MenzenSettingsDomain);
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(MenzenSettingsChangedNotification), NULL, NULL, YES);
}

@end
