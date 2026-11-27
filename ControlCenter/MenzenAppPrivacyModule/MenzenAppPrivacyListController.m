#import <Preferences/PSSpecifier.h>

#import "../../Preferences/Helpers/MenzenAppIcon.h"
#import "../../Shared/MenzenAppPrivacy.h"
#import "MenzenAppPrivacyListController.h"

static NSString *const MenzenAppPrivacyValueKey = @"menzenApp";

@implementation MenzenAppPrivacyListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specifiers = [NSMutableArray arrayWithObject:[PSSpecifier emptyGroupSpecifier]];

		for (NSArray<NSString *> *choice in MenzenInstalledProviderApps()) {
			PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:choice[1] target:self set:nil get:nil detail:nil cell:PSListItemCell edit:nil];
			[specifier setProperty:choice[0] forKey:MenzenAppPrivacyValueKey];
			MenzenSetAppIcon(specifier, choice[0]);
			[specifiers addObject:specifier];
		}

		_specifiers = specifiers;
	}

	return _specifiers;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	NSBundle *bundle = [NSBundle bundleForClass:self.class];
	self.title = bundle.localizedInfoDictionary[@"CFBundleDisplayName"] ?: bundle.infoDictionary[@"CFBundleDisplayName"];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];

	// The module changes it from SpringBoard.
	MenzenSettingsSynchronize();
	[self reloadSpecifiers];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	NSString *value = [[self specifierAtIndexPath:indexPath] propertyForKey:MenzenAppPrivacyValueKey];

	if (value) cell.accessoryType = [value isEqualToString:MenzenPrivacyModuleApp()] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSString *value = [[self specifierAtIndexPath:indexPath] propertyForKey:MenzenAppPrivacyValueKey];
	if (!value) return;

	MenzenWriteSetting(MenzenSettingPrivacyModuleApp, value);
	MenzenPostDarwinNotification(CFSTR(MenzenSettingsChangedNotification));

	[self reloadSpecifiers];
}

@end
