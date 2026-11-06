#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

#import "../../Shared/MenzenLocalization/MenzenLocalization.h"
#import "../../Shared/MenzenSettings.h"
#import "MenzenPriorityListController.h"

static NSString *MenzenSourceTitle(NSString *source) {
	if ([source isEqualToString:MenzenSourceCustom]) return MenzenLocalizedString(@"root.custom_activity", @"Custom Activity");
	if ([source isEqualToString:MenzenSourceConnected]) return MenzenLocalizedString(@"priority.connected_apps", @"Connected Apps");
	if ([source isEqualToString:MenzenSourceGames]) return MenzenLocalizedString(@"priority.games", @"Games");
	return MenzenLocalizedString(@"priority.music_and_video", @"Music & Video");
}

static NSString *MenzenSourceSymbol(NSString *source) {
	if ([source isEqualToString:MenzenSourceCustom]) return @"square.and.pencil";
	if ([source isEqualToString:MenzenSourceConnected]) return @"link";
	if ([source isEqualToString:MenzenSourceGames]) return @"gamecontroller";
	return @"play.circle";
}

@implementation MenzenPriorityListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specifiers = [NSMutableArray array];
		PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
		[group setProperty:MenzenLocalizedString(@"priority.menzen_shows_the_first_of", @"Menzen shows the first of these that has something to show. Drag to reorder.") forKey:@"footerText"];
		[specifiers addObject:group];
		for (NSString *source in MenzenPriority()) {
			PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:MenzenSourceTitle(source) target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
			row.identifier = source;
			[row setProperty:[UIImage systemImageNamed:MenzenSourceSymbol(source)] forKey:@"iconImage"];
			[specifiers addObject:row];
		}

		_specifiers = specifiers;
	}

	return _specifiers;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.editing = YES;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	cell.showsReorderControl = YES;
	return cell;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
	return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
	return NO;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
	// The rows are the only ones in their group, after its specifier.
	PSSpecifier *moved = _specifiers[from.row + 1];
	[_specifiers removeObjectAtIndex:from.row + 1];
	[_specifiers insertObject:moved atIndex:to.row + 1];

	NSMutableArray<NSString *> *order = [NSMutableArray array];
	for (PSSpecifier *specifier in _specifiers) {
		if (specifier.identifier.length && specifier.cellType != PSGroupCell) [order addObject:specifier.identifier];
	}

	CFPreferencesSetAppValue((__bridge CFStringRef)MenzenSettingPriority, (__bridge CFArrayRef)order, (__bridge CFStringRef)MenzenSettingsDomain);
	CFPreferencesAppSynchronize((__bridge CFStringRef)MenzenSettingsDomain);
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(MenzenSettingsChangedNotification), NULL, NULL, YES);
}

@end
