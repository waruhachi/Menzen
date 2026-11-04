#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

#import "../../Shared/MZCustomActivity.h"
#import "../../Shared/MZLocalization/MZLocalization.h"
#import "../Helpers/MZImageCheck.h"
#import "../Views/MZChoiceCells.h"
#import "../Views/MZDestructiveButtonCell.h"
#import "MZCustomListController.h"

@interface UITableViewCell (MZEditable)
- (UITextField *)editableTextField;
- (UITextField *)textField;
@end

static void MZWriteSetting(NSString *key, id value) {
	CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)MZSettingsDomain);
	CFPreferencesAppSynchronize((__bridge CFStringRef)MZSettingsDomain);
}

static void MZPostSettingsChanged(void) {
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(MZSettingsChangedNotification), NULL, NULL, YES);
}

static void MZWritePresets(NSArray<NSDictionary *> *presets) {
	MZWriteSetting(MZSettingCustomPresets, presets);
	MZPostSettingsChanged();
}

static void MZUsePreset(NSString *identifier) {
	MZWriteSetting(MZSettingCustomPreset, identifier);
	MZWriteSetting(MZSettingCustomStart, NSDate.date);
	MZWriteSetting(MZSettingCustom, @YES);
	MZPostSettingsChanged();
}

static NSString *MZPresetTitle(NSDictionary *preset) {
	return MZPresetString(preset, MZPresetNameKey) ?: MZLocalizedString(@"custom.untitled", @"Untitled");
}

static void MZConfirmPresetImages(UIViewController *controller, NSDictionary *preset, void (^proceed)(void), void (^cancel)(void)) {
	MZCheckPresetImages(preset, ^(NSArray<NSString *> *problems) {
		if (!problems.count) {
			proceed();
			return;
		}
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:problems.count > 1 ? MZLocalizedString(@"custom.these_images_won_t_work", @"These Images Won't Work") : MZLocalizedString(@"common.this_image_won_t_work", @"This Image Won't Work") message:[problems componentsJoinedByString:@"\n\n"] preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:MZLocalizedString(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
			cancel();
		}]];
		[alert addAction:[UIAlertAction actionWithTitle:MZLocalizedString(@"custom.use_anyway", @"Use Anyway") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			proceed();
		}]];
		[controller presentViewController:alert animated:YES completion:nil];
	});
}

static void MZPushController(PSListController *parent, Class controllerClass, PSSpecifier *specifier) {
	PSListController *controller = [controllerClass new];
	controller.specifier = specifier;
	controller.rootController = parent.rootController;
	controller.parentController = parent;
	[parent showController:controller animate:YES];
}

@implementation MZCustomListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specifiers = [NSMutableArray array];
		[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		PSSpecifier *toggle = [PSSpecifier preferenceSpecifierNamed:MZLocalizedString(@"custom.custom_activity", @"Custom Activity") target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
		[toggle setProperty:MZSettingCustom forKey:@"key"];
		[toggle setProperty:MZSettingsDomain forKey:@"defaults"];
		[toggle setProperty:@NO forKey:@"default"];
		[toggle setProperty:@MZSettingsChangedNotification forKey:@"PostNotification"];
		NSArray<NSDictionary *> *presets = MZCustomPresets();
		[toggle setProperty:@(presets.count > 0) forKey:@"enabled"];
		[specifiers addObject:toggle];

		[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		PSSpecifier *add = [PSSpecifier preferenceSpecifierNamed:MZLocalizedString(@"custom.add_preset", @"Add Preset") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
		add.buttonAction = @selector(addPreset:);
		[specifiers addObject:add];

		if (presets.count) [specifiers addObject:[PSSpecifier groupSpecifierWithName:MZLocalizedString(@"custom.presets", @"Presets")]];
		for (NSDictionary *preset in presets) {
			PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:MZPresetTitle(preset) target:self set:nil get:@selector(presetSummary:) detail:MZPresetListController.class cell:PSLinkListCell edit:nil];
			[row setProperty:preset[MZPresetIdentifierKey] forKey:@"presetIdentifier"];
			[specifiers addObject:row];
		}
		_specifiers = specifiers;
	}

	return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	if (![[specifier propertyForKey:@"key"] isEqualToString:MZSettingCustom] || ![value boolValue]) {
		[super setPreferenceValue:value specifier:specifier];
		return;
	}

	__weak typeof(self) weakSelf = self;
	MZConfirmPresetImages(self, MZCustomPreset(MZSettingString(MZSettingCustomPreset, nil)) ?: @{}, ^{
		MZWriteSetting(MZSettingCustomStart, NSDate.date);
		[weakSelf superSetPreferenceValue:value specifier:specifier]; }, ^{ [weakSelf reloadSpecifiers]; });
}

- (void)superSetPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[super setPreferenceValue:value specifier:specifier];
}

- (NSString *)presetSummary:(PSSpecifier *)specifier {
	return [[specifier propertyForKey:@"presetIdentifier"] isEqualToString:MZSettingString(MZSettingCustomPreset, nil)] ? MZLocalizedString(@"custom.in_use", @"In Use") : @"";
}

- (void)addPreset:(PSSpecifier *)specifier {
	NSString *identifier = NSUUID.UUID.UUIDString;
	NSDictionary *preset = @{MZPresetIdentifierKey: identifier, MZPresetKindKey: @"playing", MZPresetTimerKey: @YES};
	MZWritePresets([MZCustomPresets() arrayByAddingObject:preset]);
	// The first preset is the one in use, without switching it on.
	if (!MZCustomPreset(MZSettingString(MZSettingCustomPreset, nil))) {
		MZWriteSetting(MZSettingCustomPreset, identifier);
		MZWriteSetting(MZSettingCustomStart, NSDate.date);
	}

	PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:MZPresetTitle(preset) target:self set:nil get:nil detail:MZPresetListController.class cell:PSLinkListCell edit:nil];
	[row setProperty:identifier forKey:@"presetIdentifier"];
	MZPushController(self, MZPresetListController.class, row);
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.title = MZLocalizedString(@"custom.custom_activity", @"Custom Activity");
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reloadSpecifiers];
}

// PSListController only opens its own list from a list cell.
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
	if (![specifier propertyForKey:@"presetIdentifier"]) {
		[super tableView:tableView didSelectRowAtIndexPath:indexPath];
		return;
	}

	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	MZPushController(self, MZPresetListController.class, specifier);
}

@end

@implementation MZPresetListController

- (NSString *)identifier {
	return [self.specifier propertyForKey:@"presetIdentifier"];
}

- (NSDictionary *)preset {
	return MZCustomPreset(self.identifier) ?: @{};
}

- (PSSpecifier *)fieldNamed:(NSString *)name key:(NSString *)key cell:(PSCellType)cell {
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:cell edit:nil];
	[specifier setProperty:key forKey:@"presetKey"];
	return specifier;
}

- (PSSpecifier *)textFieldNamed:(NSString *)name key:(NSString *)key placeholder:(NSString *)placeholder {
	PSSpecifier *specifier = [self fieldNamed:name key:key cell:PSEditTextCell];
	[specifier setProperty:placeholder forKey:@"placeholder"];
	[specifier setProperty:@YES forKey:@"noAutoCorrect"];
	return specifier;
}

- (PSSpecifier *)linkFieldNamed:(NSString *)name key:(NSString *)key {
	PSSpecifier *specifier = [self textFieldNamed:name key:key placeholder:@"https://"];
	[specifier setProperty:@YES forKey:@"isURL"];
	[specifier setProperty:@"UIKeyboardTypeURL" forKey:@"keyboard"];
	return specifier;
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSDictionary *preset = self.preset;
		BOOL inUse = [self.identifier isEqualToString:MZSettingString(MZSettingCustomPreset, nil)];
		BOOL showing = inUse && MZSettingBool(MZSettingCustom, NO);
		NSMutableArray *specifiers = [NSMutableArray array];

		if (!showing) {
			[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
			PSSpecifier *use = [PSSpecifier preferenceSpecifierNamed:MZLocalizedString(@"custom.use_this_preset", @"Use This Preset") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
			use.buttonAction = @selector(usePreset:);
			[specifiers addObject:use];
		}

		[specifiers addObject:[PSSpecifier groupSpecifierWithName:MZLocalizedString(@"common.text", @"Text")]];
		PSSpecifier *kind = [self fieldNamed:MZLocalizedString(@"custom.type", @"Type") key:MZPresetKindKey cell:PSStaticTextCell];
		[kind setProperty:MZChoiceCell.class forKey:@"cellClass"];
		[kind setProperty:@[@[@"playing", MZLocalizedString(@"common.playing", @"Playing")], @[@"listening", MZLocalizedString(@"common.listening", @"Listening")], @[@"watching", MZLocalizedString(@"common.watching", @"Watching")]] forKey:@"choices"];
		[kind setProperty:MZPresetString(preset, MZPresetKindKey) ?: @"playing" forKey:@"choice"];
		[specifiers addObject:kind];
		[specifiers addObject:[self textFieldNamed:MZLocalizedString(@"common.name", @"Name") key:MZPresetNameKey placeholder:@"Menzen"]];
		[specifiers addObject:[self textFieldNamed:MZLocalizedString(@"common.first_line", @"First Line") key:MZPresetDetailsKey placeholder:MZLocalizedString(@"common.none", @"None")]];
		[specifiers addObject:[self textFieldNamed:MZLocalizedString(@"common.second_line", @"Second Line") key:MZPresetStateKey placeholder:MZLocalizedString(@"common.none", @"None")]];

		[specifiers addObject:[PSSpecifier groupSpecifierWithName:MZLocalizedString(@"common.big_picture", @"Big Picture")]];
		[specifiers addObject:[self linkFieldNamed:MZLocalizedString(@"common.image_link", @"Image Link") key:MZPresetLargeImageKey]];
		[specifiers addObject:[self textFieldNamed:MZLocalizedString(@"common.text", @"Text") key:MZPresetLargeTextKey placeholder:MZLocalizedString(@"common.none", @"None")]];

		[specifiers addObject:[PSSpecifier groupSpecifierWithName:MZLocalizedString(@"common.small_picture", @"Small Picture")]];
		[specifiers addObject:[self linkFieldNamed:MZLocalizedString(@"common.image_link", @"Image Link") key:MZPresetSmallImageKey]];
		[specifiers addObject:[self textFieldNamed:MZLocalizedString(@"common.text", @"Text") key:MZPresetSmallTextKey placeholder:MZLocalizedString(@"common.none", @"None")]];

		[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		PSSpecifier *timer = [self fieldNamed:MZLocalizedString(@"common.time_elapsed", @"Time Elapsed") key:MZPresetTimerKey cell:PSSwitchCell];
		[specifiers addObject:timer];

		[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		PSSpecifier *delete = [PSSpecifier preferenceSpecifierNamed:MZLocalizedString(@"custom.delete_preset", @"Delete Preset") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
		delete.buttonAction = @selector(confirmDelete:);
		[delete setProperty:MZDestructiveButtonCell.class forKey:@"cellClass"];
		[specifiers addObject:delete];
		_specifiers = specifiers;
	}

	return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
	NSString *key = [specifier propertyForKey:@"presetKey"];
	if (!key) return [super readPreferenceValue:specifier];
	id value = self.preset[key];
	if ([key isEqualToString:MZPresetTimerKey]) return value ?: @YES;
	return value ?: @"";
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	NSString *key = [specifier propertyForKey:@"presetKey"];
	if (!key) {
		[super setPreferenceValue:value specifier:specifier];
		return;
	}

	NSMutableArray<NSDictionary *> *presets = [MZCustomPresets() mutableCopy];
	for (NSUInteger i = 0; i < presets.count; i++) {
		if (![presets[i][MZPresetIdentifierKey] isEqualToString:self.identifier]) continue;
		NSMutableDictionary *preset = [presets[i] mutableCopy];
		preset[key] = value;
		presets[i] = preset;
	}

	MZWritePresets(presets);
	if ([key isEqualToString:MZPresetNameKey]) self.title = MZPresetTitle(self.preset);
	if ([key isEqualToString:MZPresetKindKey]) [self reloadSpecifiers];
	if (([key isEqualToString:MZPresetLargeImageKey] || [key isEqualToString:MZPresetSmallImageKey]) && [value isKindOfClass:NSString.class]) [self checkLink:value];
}

- (void)checkLink:(NSString *)link {
	link = [link stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (!link.length) return;
	__weak typeof(self) weakSelf = self;
	MZCheckImageLink(link, ^(NSString *problem) {
		typeof(self) strongSelf = weakSelf;
		if (!problem || !strongSelf.view.window || strongSelf.presentedViewController) return;
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:MZLocalizedString(@"common.this_image_won_t_work", @"This Image Won't Work") message:problem preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
		[strongSelf presentViewController:alert animated:YES completion:nil];
	});
}

- (void)usePreset:(PSSpecifier *)specifier {
	[self.view endEditing:YES];
	NSString *identifier = self.identifier;
	__weak typeof(self) weakSelf = self;
	MZConfirmPresetImages(self, self.preset, ^{
		MZUsePreset(identifier);
		[weakSelf reloadSpecifiers];
	}, ^{});
}

// Like Settings' own values.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	UITextField *field = nil;
	if ([cell respondsToSelector:@selector(editableTextField)]) field = cell.editableTextField;
	else if ([cell respondsToSelector:@selector(textField)]) field = cell.textField;
	if ([field isKindOfClass:UITextField.class]) field.textAlignment = NSTextAlignmentRight;
	return cell;
}

- (void)confirmDelete:(PSSpecifier *)specifier {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:MZLocalizedString(@"custom.delete_x", @"Delete “%@”?"), MZPresetTitle(self.preset)] message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:MZLocalizedString(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:MZLocalizedString(@"common.delete", @"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[weakSelf deletePreset];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)deletePreset {
	NSString *identifier = self.identifier;
	NSArray *presets = [MZCustomPresets() filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"%K != %@", MZPresetIdentifierKey, identifier]];
	// Without the preset in use, nothing custom shows.
	if ([identifier isEqualToString:MZSettingString(MZSettingCustomPreset, nil)]) {
		MZWriteSetting(MZSettingCustomPreset, nil);
		MZWriteSetting(MZSettingCustom, nil);
	}

	MZWritePresets(presets);
	[self.navigationController popViewControllerAnimated:YES];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.title = MZPresetTitle(self.preset);
}

// Text fields save as they lose focus, so leaving the page saves too.
- (void)viewWillDisappear:(BOOL)animated {
	[self.view endEditing:YES];
	[super viewWillDisappear:animated];
}

@end
