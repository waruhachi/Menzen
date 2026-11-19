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
		[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:MenzenLocalizedString(@"priority.connected_apps", @"Connected Apps") target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
		enabled.identifier = MenzenSettingConnected;
		[enabled setProperty:MenzenSettingConnected forKey:@"key"];
		[enabled setProperty:@NO forKey:@"default"];
		[enabled setProperty:MenzenSettingsDomain forKey:@"defaults"];
		[enabled setProperty:@MenzenSettingsChangedNotification forKey:@"PostNotification"];
		[specifiers addObject:enabled];

		NSDictionary<NSString *, NSDictionary *> *apps = MenzenConnectedApps();
		[specifiers addObject:[PSSpecifier groupSpecifierWithName:MenzenLocalizedString(@"connected.apps", @"Apps")]];
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
	MenzenConnectedSetAllowed(specifier.identifier, allowed.boolValue);
}

@end
