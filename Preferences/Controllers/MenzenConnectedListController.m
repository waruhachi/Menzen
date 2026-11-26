#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

#import "../../Shared/MenzenConnectedApps.h"
#import "../../Shared/MenzenLocalization/MenzenLocalization.h"
#import "../Helpers/MenzenAppIcon.h"
#import "../Helpers/MenzenServiceClient.h"
#import "../Views/MenzenDestructiveButtonCell.h"
#import "MenzenConnectedListController.h"

static void MenzenConnectedAppsChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	MenzenConnectedListController *controller = (__bridge MenzenConnectedListController *)observer;
	dispatch_async(dispatch_get_main_queue(), ^{
		MenzenSettingsSynchronize();
		[controller reloadSpecifiers];
	});
}

@implementation MenzenConnectedListController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self, MenzenConnectedAppsChanged, CFSTR(MenzenConnectedAppsChangedNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reloadSpecifiers];
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
			PSSpecifier *app = [PSSpecifier preferenceSpecifierNamed:apps[identifier][MenzenConnectedAppNameKey] target:self set:nil get:@selector(appSummary:) detail:MenzenConnectedAppListController.class cell:PSLinkListCell edit:nil];
			app.identifier = identifier;
			[app setProperty:identifier forKey:@"connectedApp"];
			MenzenSetAppIcon(app, identifier);
			[specifiers addObject:app];
		}

		_specifiers = specifiers;
	}

	return _specifiers;
}

- (NSString *)appSummary:(PSSpecifier *)specifier {
	return [MenzenConnectedAllowed() containsObject:specifier.identifier] ? MenzenLocalizedString(@"common.on", @"On") : MenzenLocalizedString(@"common.off", @"Off");
}

// PSLinkListCell would open a list of choices.
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];

	if (![specifier propertyForKey:@"connectedApp"]) {
		[super tableView:tableView didSelectRowAtIndexPath:indexPath];
		return;
	}

	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	MenzenConnectedAppListController *controller = [MenzenConnectedAppListController new];
	controller.specifier = specifier;
	controller.rootController = self.rootController;
	controller.parentController = self;

	[self showController:controller animate:YES];
}

@end

@implementation MenzenConnectedAppListController

- (NSString *)appIdentifier {
	return [self.specifier propertyForKey:@"connectedApp"];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.title = self.specifier.name;
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specifiers = [NSMutableArray array];
		[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		PSSpecifier *allowed = [PSSpecifier preferenceSpecifierNamed:self.specifier.name target:self set:@selector(setAllowed:specifier:) get:@selector(allowed:) detail:nil cell:PSSwitchCell edit:nil];
		[specifiers addObject:allowed];

		[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		PSSpecifier *remove = [PSSpecifier preferenceSpecifierNamed:MenzenLocalizedString(@"connected.remove_app", @"Remove App") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
		remove.buttonAction = @selector(confirmRemove:);
		[remove setProperty:MenzenDestructiveButtonCell.class forKey:@"cellClass"];
		[specifiers addObject:remove];

		_specifiers = specifiers;
	}

	return _specifiers;
}

- (NSNumber *)allowed:(PSSpecifier *)specifier {
	return @([MenzenConnectedAllowed() containsObject:self.appIdentifier]);
}

- (void)setAllowed:(NSNumber *)allowed specifier:(PSSpecifier *)specifier {
	MenzenConnectedSetAllowed(self.appIdentifier, allowed.boolValue);
}

- (void)confirmRemove:(PSSpecifier *)specifier {
	NSString *title = [NSString stringWithFormat:MenzenLocalizedString(@"connected.remove_x", @"Remove %@?"), self.specifier.name];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:MenzenLocalizedString(@"connected.it_shows_up_here_again", @"It shows up here again, switched off, the next time it asks to show activity.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:MenzenLocalizedString(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:MenzenLocalizedString(@"connected.remove", @"Remove") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[weakSelf remove];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

// The allowed list is the pane's to write, the list of apps menzend's.
- (void)remove {
	NSString *identifier = self.appIdentifier;
	MenzenConnectedSetAllowed(identifier, NO);
	[MenzenServiceProxy(nil) removeConnectedApp:identifier reply:^{}];
	[self.navigationController popViewControllerAnimated:YES];
}

@end
