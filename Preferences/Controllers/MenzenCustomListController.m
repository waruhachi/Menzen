#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

#import "../../Shared/MenzenCustomActivity.h"
#import "../../Shared/MenzenLocalization/MenzenLocalization.h"
#import "../../Shared/MenzenService.h"
#import "../Helpers/MenzenImageCheck.h"
#import "../Views/MenzenChoiceCells.h"
#import "../Views/MenzenDestructiveButtonCell.h"
#import "../Views/MenzenPreviewCells.h"
#import "MenzenCustomListController.h"

@interface UITableViewCell (MenzenEditable)
- (UITextField *)editableTextField;
- (UITextField *)textField;
@end

static void MenzenWriteSetting(NSString *key, id value) {
	CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)MenzenSettingsDomain);
	CFPreferencesAppSynchronize((__bridge CFStringRef)MenzenSettingsDomain);
}

static void MenzenPostSettingsChanged(void) {
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(MenzenSettingsChangedNotification), NULL, NULL, YES);
}

static void MenzenWritePresets(NSArray<NSDictionary *> *presets) {
	MenzenWriteSetting(MenzenSettingCustomPresets, presets);
	MenzenPostSettingsChanged();
}

static void MenzenUsePreset(NSString *identifier) {
	MenzenWriteSetting(MenzenSettingCustomPreset, identifier);
	MenzenWriteSetting(MenzenSettingCustomStart, NSDate.date);
	MenzenWriteSetting(MenzenSettingCustom, @YES);
	MenzenPostSettingsChanged();
}

static NSString *MenzenPresetTitle(NSDictionary *preset) {
	return MenzenPresetString(preset, MenzenPresetNameKey) ?: MenzenLocalizedString(@"custom.untitled", @"Untitled");
}

static void MenzenConfirmPresetImages(UIViewController *controller, NSDictionary *preset, void (^proceed)(void), void (^cancel)(void)) {
	MenzenCheckPresetImages(preset, ^(NSArray<NSString *> *problems) {
		if (!problems.count) {
			proceed();
			return;
		}
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:problems.count > 1 ? MenzenLocalizedString(@"custom.these_images_won_t_work", @"These Images Won't Work") : MenzenLocalizedString(@"common.this_image_won_t_work", @"This Image Won't Work") message:[problems componentsJoinedByString:@"\n\n"] preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:MenzenLocalizedString(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
			cancel();
		}]];
		[alert addAction:[UIAlertAction actionWithTitle:MenzenLocalizedString(@"custom.use_anyway", @"Use Anyway") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			proceed();
		}]];
		[controller presentViewController:alert animated:YES completion:nil];
	});
}

static void MenzenPushController(PSListController *parent, Class controllerClass, PSSpecifier *specifier) {
	PSListController *controller = [controllerClass new];
	controller.specifier = specifier;
	controller.rootController = parent.rootController;
	controller.parentController = parent;
	[parent showController:controller animate:YES];
}

@implementation MenzenCustomListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specifiers = [NSMutableArray array];
		[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		PSSpecifier *toggle = [PSSpecifier preferenceSpecifierNamed:MenzenLocalizedString(@"custom.custom_activity", @"Custom Activity") target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
		[toggle setProperty:MenzenSettingCustom forKey:@"key"];
		[toggle setProperty:MenzenSettingsDomain forKey:@"defaults"];
		[toggle setProperty:@NO forKey:@"default"];
		[toggle setProperty:@MenzenSettingsChangedNotification forKey:@"PostNotification"];
		NSArray<NSDictionary *> *presets = MenzenCustomPresets();
		[toggle setProperty:@(presets.count > 0) forKey:@"enabled"];
		[specifiers addObject:toggle];

		[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		PSSpecifier *add = [PSSpecifier preferenceSpecifierNamed:MenzenLocalizedString(@"custom.add_preset", @"Add Preset") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
		add.buttonAction = @selector(addPreset:);
		[specifiers addObject:add];

		if (presets.count) [specifiers addObject:[PSSpecifier groupSpecifierWithName:MenzenLocalizedString(@"custom.presets", @"Presets")]];
		for (NSDictionary *preset in presets) {
			PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:MenzenPresetTitle(preset) target:self set:nil get:@selector(presetSummary:) detail:MenzenPresetListController.class cell:PSLinkListCell edit:nil];
			[row setProperty:preset[MenzenPresetIdentifierKey] forKey:@"presetIdentifier"];
			[specifiers addObject:row];
		}
		_specifiers = specifiers;
	}

	return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	if (![[specifier propertyForKey:@"key"] isEqualToString:MenzenSettingCustom] || ![value boolValue]) {
		[super setPreferenceValue:value specifier:specifier];
		return;
	}

	__weak typeof(self) weakSelf = self;
	MenzenConfirmPresetImages(self, MenzenCustomPreset(MenzenSettingString(MenzenSettingCustomPreset, nil)) ?: @{}, ^{
		MenzenWriteSetting(MenzenSettingCustomStart, NSDate.date);
		[weakSelf superSetPreferenceValue:value specifier:specifier]; }, ^{ [weakSelf reloadSpecifiers]; });
}

- (void)superSetPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[super setPreferenceValue:value specifier:specifier];
}

- (NSString *)presetSummary:(PSSpecifier *)specifier {
	return [[specifier propertyForKey:@"presetIdentifier"] isEqualToString:MenzenSettingString(MenzenSettingCustomPreset, nil)] ? MenzenLocalizedString(@"custom.in_use", @"In Use") : @"";
}

- (void)addPreset:(PSSpecifier *)specifier {
	NSString *identifier = NSUUID.UUID.UUIDString;
	NSDictionary *preset = @{MenzenPresetIdentifierKey: identifier, MenzenPresetKindKey: @"playing", MenzenPresetTimerKey: @YES};
	MenzenWritePresets([MenzenCustomPresets() arrayByAddingObject:preset]);
	// The first preset is the one in use, without switching it on.
	if (!MenzenCustomPreset(MenzenSettingString(MenzenSettingCustomPreset, nil))) {
		MenzenWriteSetting(MenzenSettingCustomPreset, identifier);
		MenzenWriteSetting(MenzenSettingCustomStart, NSDate.date);
	}

	PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:MenzenPresetTitle(preset) target:self set:nil get:nil detail:MenzenPresetListController.class cell:PSLinkListCell edit:nil];
	[row setProperty:identifier forKey:@"presetIdentifier"];
	MenzenPushController(self, MenzenPresetListController.class, row);
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.title = MenzenLocalizedString(@"custom.custom_activity", @"Custom Activity");
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
	MenzenPushController(self, MenzenPresetListController.class, specifier);
}

@end

@implementation MenzenPresetListController

- (NSString *)identifier {
	return [self.specifier propertyForKey:@"presetIdentifier"];
}

- (NSDictionary *)preset {
	return MenzenCustomPreset(self.identifier) ?: @{};
}

// The preset as menzend would show it (-[MenzenPresence customActivity]),
// timed from when it was chosen, or from now when it isn't in use.
- (NSDictionary<NSString *, id> *)previewActivity {
	NSDictionary *preset = self.preset;
	NSMutableDictionary *activity = [NSMutableDictionary dictionary];
	NSString *kind = MenzenPresetString(preset, MenzenPresetKindKey);
	activity[MenzenActivityKindKey] = [kind isEqualToString:@"listening"] || [kind isEqualToString:@"watching"] ? kind : @"playing";
	activity[MenzenActivityStatusDisplayKey] = @"name";
	activity[MenzenActivityNameKey] = MenzenPresetString(preset, MenzenPresetNameKey);
	NSString *largeImage = MenzenPresetString(preset, MenzenPresetLargeImageKey);
	if (MenzenCustomImageURLIsAllowed(largeImage)) activity[MenzenActivityImageURLKey] = largeImage;
	if (MenzenSettingBool(MenzenSettingPrivacy, NO)) return activity;

	activity[MenzenActivityDetailsKey] = MenzenPresetString(preset, MenzenPresetDetailsKey);
	activity[MenzenActivityStateKey] = MenzenPresetString(preset, MenzenPresetStateKey);
	if (activity[MenzenActivityImageURLKey]) {
		activity[MenzenActivityLargeTextKey] = MenzenPresetString(preset, MenzenPresetLargeTextKey);
		NSString *smallImage = MenzenPresetString(preset, MenzenPresetSmallImageKey);
		if (MenzenCustomImageURLIsAllowed(smallImage)) {
			activity[MenzenActivitySmallImageURLKey] = smallImage;
			activity[MenzenActivitySmallTextKey] = MenzenPresetString(preset, MenzenPresetSmallTextKey);
		}
	}

	id timer = preset[MenzenPresetTimerKey];
	if (![timer respondsToSelector:@selector(boolValue)] || [timer boolValue]) {
		NSDate *start = MenzenSettingValue(MenzenSettingCustomStart);
		BOOL inUse = [self.identifier isEqualToString:MenzenSettingString(MenzenSettingCustomPreset, nil)];
		activity[MenzenActivityStartKey] = @((inUse && [start isKindOfClass:NSDate.class] ? start : NSDate.date).timeIntervalSince1970);
	}

	return activity;
}

- (PSSpecifier *)previewSpecifier {
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:nil target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
	specifier.identifier = @"preview";
	[specifier setProperty:MenzenCardPreviewCell.class forKey:@"cellClass"];
	[specifier setProperty:self.previewActivity forKey:@"activity"];
	return specifier;
}

- (void)reloadPreview {
	PSSpecifier *old = [self specifierForID:@"preview"];
	if (old) [self replaceContiguousSpecifiers:@[old] withSpecifiers:@[self.previewSpecifier] animated:NO];
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
		BOOL inUse = [self.identifier isEqualToString:MenzenSettingString(MenzenSettingCustomPreset, nil)];
		BOOL showing = inUse && MenzenSettingBool(MenzenSettingCustom, NO);
		NSMutableArray *specifiers = [NSMutableArray array];
		[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		[specifiers addObject:self.previewSpecifier];

		if (!showing) {
			[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
			PSSpecifier *use = [PSSpecifier preferenceSpecifierNamed:MenzenLocalizedString(@"custom.use_this_preset", @"Use This Preset") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
			use.buttonAction = @selector(usePreset:);
			[specifiers addObject:use];
		}

		[specifiers addObject:[PSSpecifier groupSpecifierWithName:MenzenLocalizedString(@"common.text", @"Text")]];
		PSSpecifier *kind = [self fieldNamed:MenzenLocalizedString(@"custom.type", @"Type") key:MenzenPresetKindKey cell:PSStaticTextCell];
		[kind setProperty:MenzenChoiceCell.class forKey:@"cellClass"];
		[kind setProperty:@[@[@"playing", MenzenLocalizedString(@"common.playing", @"Playing")], @[@"listening", MenzenLocalizedString(@"common.listening", @"Listening")], @[@"watching", MenzenLocalizedString(@"common.watching", @"Watching")]] forKey:@"choices"];
		[kind setProperty:MenzenPresetString(preset, MenzenPresetKindKey) ?: @"playing" forKey:@"choice"];
		[specifiers addObject:kind];
		[specifiers addObject:[self textFieldNamed:MenzenLocalizedString(@"common.name", @"Name") key:MenzenPresetNameKey placeholder:@"Menzen"]];
		[specifiers addObject:[self textFieldNamed:MenzenLocalizedString(@"common.first_line", @"First Line") key:MenzenPresetDetailsKey placeholder:MenzenLocalizedString(@"common.none", @"None")]];
		[specifiers addObject:[self textFieldNamed:MenzenLocalizedString(@"common.second_line", @"Second Line") key:MenzenPresetStateKey placeholder:MenzenLocalizedString(@"common.none", @"None")]];

		[specifiers addObject:[PSSpecifier groupSpecifierWithName:MenzenLocalizedString(@"common.big_picture", @"Big Picture")]];
		[specifiers addObject:[self linkFieldNamed:MenzenLocalizedString(@"common.image_link", @"Image Link") key:MenzenPresetLargeImageKey]];
		[specifiers addObject:[self textFieldNamed:MenzenLocalizedString(@"common.text", @"Text") key:MenzenPresetLargeTextKey placeholder:MenzenLocalizedString(@"common.none", @"None")]];

		[specifiers addObject:[PSSpecifier groupSpecifierWithName:MenzenLocalizedString(@"common.small_picture", @"Small Picture")]];
		[specifiers addObject:[self linkFieldNamed:MenzenLocalizedString(@"common.image_link", @"Image Link") key:MenzenPresetSmallImageKey]];
		[specifiers addObject:[self textFieldNamed:MenzenLocalizedString(@"common.text", @"Text") key:MenzenPresetSmallTextKey placeholder:MenzenLocalizedString(@"common.none", @"None")]];

		[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		PSSpecifier *timer = [self fieldNamed:MenzenLocalizedString(@"common.time_elapsed", @"Time Elapsed") key:MenzenPresetTimerKey cell:PSSwitchCell];
		[specifiers addObject:timer];

		[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		PSSpecifier *delete = [PSSpecifier preferenceSpecifierNamed:MenzenLocalizedString(@"custom.delete_preset", @"Delete Preset") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
		delete.buttonAction = @selector(confirmDelete:);
		[delete setProperty:MenzenDestructiveButtonCell.class forKey:@"cellClass"];
		[specifiers addObject:delete];
		_specifiers = specifiers;
	}

	return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
	NSString *key = [specifier propertyForKey:@"presetKey"];
	if (!key) return [super readPreferenceValue:specifier];
	id value = self.preset[key];
	if ([key isEqualToString:MenzenPresetTimerKey]) return value ?: @YES;
	return value ?: @"";
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	NSString *key = [specifier propertyForKey:@"presetKey"];
	if (!key) {
		[super setPreferenceValue:value specifier:specifier];
		return;
	}

	NSMutableArray<NSDictionary *> *presets = [MenzenCustomPresets() mutableCopy];
	for (NSUInteger i = 0; i < presets.count; i++) {
		if (![presets[i][MenzenPresetIdentifierKey] isEqualToString:self.identifier]) continue;
		NSMutableDictionary *preset = [presets[i] mutableCopy];
		preset[key] = value;
		presets[i] = preset;
	}

	MenzenWritePresets(presets);
	if ([key isEqualToString:MenzenPresetNameKey]) self.title = MenzenPresetTitle(self.preset);
	if ([key isEqualToString:MenzenPresetKindKey]) [self reloadSpecifiers];
	else [self reloadPreview];
	if (([key isEqualToString:MenzenPresetLargeImageKey] || [key isEqualToString:MenzenPresetSmallImageKey]) && [value isKindOfClass:NSString.class]) [self checkLink:value];
}

- (void)checkLink:(NSString *)link {
	link = [link stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (!link.length) return;
	__weak typeof(self) weakSelf = self;
	MenzenCheckImageLink(link, ^(NSString *problem) {
		typeof(self) strongSelf = weakSelf;
		if (!problem || !strongSelf.view.window || strongSelf.presentedViewController) return;
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:MenzenLocalizedString(@"common.this_image_won_t_work", @"This Image Won't Work") message:problem preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
		[strongSelf presentViewController:alert animated:YES completion:nil];
	});
}

- (void)usePreset:(PSSpecifier *)specifier {
	[self.view endEditing:YES];
	NSString *identifier = self.identifier;
	__weak typeof(self) weakSelf = self;
	MenzenConfirmPresetImages(self, self.preset, ^{
		MenzenUsePreset(identifier);
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

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([[self specifierAtIndexPath:indexPath].identifier isEqualToString:@"preview"]) return UITableViewAutomaticDimension;
	return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([[self specifierAtIndexPath:indexPath].identifier isEqualToString:@"preview"]) return 140;
	return [super tableView:tableView estimatedHeightForRowAtIndexPath:indexPath];
}

- (void)confirmDelete:(PSSpecifier *)specifier {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:MenzenLocalizedString(@"custom.delete_x", @"Delete “%@”?"), MenzenPresetTitle(self.preset)] message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:MenzenLocalizedString(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:MenzenLocalizedString(@"common.delete", @"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[weakSelf deletePreset];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)deletePreset {
	NSString *identifier = self.identifier;
	NSArray *presets = [MenzenCustomPresets() filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"%K != %@", MenzenPresetIdentifierKey, identifier]];
	// Without the preset in use, nothing custom shows.
	if ([identifier isEqualToString:MenzenSettingString(MenzenSettingCustomPreset, nil)]) {
		MenzenWriteSetting(MenzenSettingCustomPreset, nil);
		MenzenWriteSetting(MenzenSettingCustom, nil);
	}

	MenzenWritePresets(presets);
	[self.navigationController popViewControllerAnimated:YES];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.title = MenzenPresetTitle(self.preset);
}

// Text fields save as they lose focus, so leaving the page saves too.
- (void)viewWillDisappear:(BOOL)animated {
	[self.view endEditing:YES];
	[super viewWillDisappear:animated];
}

@end
