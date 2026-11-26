#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

#import "../../Shared/MenzenCard.h"
#import "../../Shared/MenzenLocalization/MenzenLocalization.h"
#import "../../Shared/MenzenService.h"
#import "../../Shared/MenzenSettings.h"
#import "../Helpers/MenzenServiceClient.h"
#import "../Views/MenzenChoiceCells.h"
#import "../Views/MenzenPreviewCells.h"
#import "MenzenAppearanceListController.h"

static NSString *MenzenTrimmed(NSString *string) {
	return [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *const MenzenAppleMusic = @"com.apple.Music";

// It has no cover or artist picture, so pictures fall back to Apple Music's
// icon.
static NSDictionary<NSString *, id> *MenzenSampleActivity(NSDictionary<NSString *, NSString *> *icons) {
	NSDictionary *texts = @{@"title": MenzenLocalizedString(@"appearance.song_title", @"Song Title"), @"artist": MenzenLocalizedString(@"common.artist", @"Artist"), @"album": MenzenLocalizedString(@"common.album", @"Album")};
	NSMutableDictionary *activity = [NSMutableDictionary dictionary];
	activity[MenzenActivityKindKey] = @"listening";

	NSString *heading = MenzenPart(MenzenPartHeading);
	NSString *headingText = MenzenTrimmed(MenzenSettingString(MenzenSettingHeadingText, @""));
	if ([heading isEqualToString:@"custom"]) activity[MenzenActivityNameKey] = headingText.length ? headingText : nil;
	else if (![heading isEqualToString:@"menzen"]) activity[MenzenActivityNameKey] = texts[heading] ?: @"Apple Music";

	activity[MenzenActivityDetailsKey] = texts[MenzenPart(MenzenPartFirstLine)];
	NSString *state = texts[MenzenPart(MenzenPartSecondLine)];
	if (![state isEqualToString:activity[MenzenActivityDetailsKey]]) activity[MenzenActivityStateKey] = state;
	NSString *logo = icons[MenzenAppleMusic];
	if (![MenzenPart(MenzenPartBigPicture) isEqualToString:@"none"] && logo) {
		activity[MenzenActivityImageURLKey] = logo;
		NSString *thirdLine = texts[MenzenPart(MenzenPartThirdLine)];
		if (thirdLine && ![thirdLine isEqualToString:activity[MenzenActivityDetailsKey]] && ![thirdLine isEqualToString:state]) activity[MenzenActivityLargeTextKey] = thirdLine;
	}

	NSString *memberList = MenzenPart(MenzenPartMemberList);
	activity[MenzenActivityStatusDisplayKey] = [memberList isEqualToString:@"state"] && !activity[MenzenActivityStateKey] ? @"details" : memberList;

	NSTimeInterval now = NSDate.date.timeIntervalSince1970;
	activity[MenzenActivityStartKey] = @(now - 72);
	if ([MenzenPart(MenzenPartTime) isEqualToString:@"progress"]) activity[MenzenActivityEndKey] = @(now - 72 + 201);
	activity[MenzenActivityPausedKey] = @(now);
	return activity;
}

@implementation MenzenPreviewListController {
	NSDictionary<NSString *, id> *_status;
	NSDictionary<NSString *, NSString *> *_icons;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshStatus) name:MenzenStatusDidChangeNotification object:nil];
	[self refreshStatus];

	__weak typeof(self) weakSelf = self;
	[MenzenServiceProxy(nil) appIconsWithReply:^(NSDictionary<NSString *, NSString *> *icons) {
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf->_icons = icons;
			[strongSelf reloadPreview];
		});
	}];
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reloadSpecifiers];
}

- (void)refreshStatus {
	__weak typeof(self) weakSelf = self;
	MenzenFetchStatus(^(NSDictionary *status) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || !status) return;
		strongSelf->_status = status;
		[strongSelf reloadPreview];
	});
}

- (NSDictionary<NSString *, id> *)previewActivity {
	NSDictionary *preview = _status[MenzenStatusPreviewKey];
	if ([preview isKindOfClass:NSDictionary.class]) return preview;
	return MenzenSampleActivity(_icons);
}

- (NSArray<PSSpecifier *> *)previewSpecifiers {
	return @[[PSSpecifier emptyGroupSpecifier], self.previewSpecifier];
}

- (NSDictionary<NSString *, id> *)status {
	return _status;
}

- (PSSpecifier *)previewSpecifier {
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

- (void)reloadPreview {
	PSSpecifier *old = [self specifierForID:@"preview"];
	if (!old) return;
	PSSpecifier *preview = self.previewSpecifier;
	[self replaceContiguousSpecifiers:@[old] withSpecifiers:@[preview] animated:NO];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[super setPreferenceValue:value specifier:specifier];
	// The sample follows the settings here; menzend's preview follows them
	// once it has caught up, with a status change.
	[self reloadPreview];
}

- (BOOL)isPreviewRowAtIndexPath:(NSIndexPath *)indexPath {
	return [[self specifierAtIndexPath:indexPath].identifier isEqualToString:@"preview"];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([self isPreviewRowAtIndexPath:indexPath]) return UITableViewAutomaticDimension;
	return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([self isPreviewRowAtIndexPath:indexPath]) return 140;
	return [super tableView:tableView estimatedHeightForRowAtIndexPath:indexPath];
}

@end

static PSSpecifier *MenzenSettingSpecifier(id target, NSString *name, NSString *key, PSCellType cell) {
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name target:target set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:cell edit:nil];
	specifier.identifier = key;
	[specifier setProperty:key forKey:@"key"];
	[specifier setProperty:MenzenSettingsDomain forKey:@"defaults"];
	[specifier setProperty:@MenzenSettingsChangedNotification forKey:@"PostNotification"];
	return specifier;
}

@implementation MenzenCardListController

static BOOL MenzenPartAllows(NSString *part, NSString *value) {
	for (NSArray<NSString *> *choice in MenzenPartChoices(part)) {
		if ([choice.firstObject isEqualToString:value]) return YES;
	}

	return NO;
}

// A menu of the part's choices. Menzen leaves out a line or picture that
// repeats one, so picking what another shown part of its kind uses swaps the
// two; when that part can't take this one's choice, the option is greyed out.
- (PSSpecifier *)partSpecifier:(NSString *)part named:(NSString *)name enabled:(BOOL)enabled {
	PSSpecifier *specifier = MenzenSettingSpecifier(self, name, part, PSStaticTextCell);
	[specifier setProperty:MenzenChoiceCell.class forKey:@"cellClass"];
	[specifier setProperty:MenzenPartChoices(part) forKey:@"choices"];
	[specifier setProperty:MenzenPart(part) forKey:@"choice"];
	[specifier setProperty:@(enabled) forKey:@"enabled"];

	// Without a big picture, Discord shows neither its text nor a small picture.
	BOOL bigPicture = ![MenzenPart(MenzenPartBigPicture) isEqualToString:@"none"];
	NSArray *shown = bigPicture ? @[@[MenzenPartHeading, MenzenPartFirstLine, MenzenPartSecondLine, MenzenPartThirdLine], @[MenzenPartBigPicture, MenzenPartSmallPicture]] : @[@[MenzenPartHeading, MenzenPartFirstLine, MenzenPartSecondLine]];
	NSString *current = MenzenPart(part);
	NSMutableArray *disabled = [NSMutableArray array];
	NSMutableDictionary<NSString *, NSString *> *swaps = [NSMutableDictionary dictionary];
	for (NSArray<NSString *> *kind in shown) {
		if (![kind containsObject:part]) continue;
		for (NSString *other in kind) {
			NSString *value = MenzenPart(other);
			if ([other isEqualToString:part] || [value isEqualToString:@"none"]) continue;
			if (MenzenPartAllows(other, current)) swaps[value] = other;
			else [disabled addObject:value];
		}
	}

	[specifier setProperty:disabled forKey:@"disabledValues"];
	[specifier setProperty:swaps forKey:@"swaps"];
	return specifier;
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		// Discord only shows a caption and a small picture with a big picture.
		BOOL bigPicture = ![MenzenPart(MenzenPartBigPicture) isEqualToString:@"none"];
		BOOL smallPicture = bigPicture && ![MenzenPart(MenzenPartSmallPicture) isEqualToString:@"none"];

		NSMutableArray *specifiers = [self.previewSpecifiers mutableCopy];
		[specifiers addObject:[PSSpecifier groupSpecifierWithName:MenzenLocalizedString(@"common.text", @"Text")]];
		[specifiers addObject:[self partSpecifier:MenzenPartHeading named:MenzenLocalizedString(@"common.heading", @"Heading") enabled:YES]];
		if ([MenzenPart(MenzenPartHeading) isEqualToString:@"custom"]) {
			PSSpecifier *text = MenzenSettingSpecifier(self, MenzenLocalizedString(@"common.custom_heading", @"Custom Heading"), MenzenSettingHeadingText, PSEditTextCell);
			[text setProperty:@"" forKey:@"default"];
			[text setProperty:MenzenLocalizedString(@"common.name", @"Name") forKey:@"placeholder"];
			[text setProperty:@YES forKey:@"noAutoCorrect"];
			[specifiers addObject:text];
		}
		[specifiers addObject:[self partSpecifier:MenzenPartFirstLine named:MenzenLocalizedString(@"common.first_line", @"First Line") enabled:YES]];
		[specifiers addObject:[self partSpecifier:MenzenPartSecondLine named:MenzenLocalizedString(@"common.second_line", @"Second Line") enabled:YES]];
		[specifiers addObject:[self partSpecifier:MenzenPartThirdLine named:MenzenLocalizedString(@"appearance.third_line", @"Third Line") enabled:bigPicture]];

		[specifiers addObject:[PSSpecifier groupSpecifierWithName:MenzenLocalizedString(@"appearance.pictures", @"Pictures")]];
		[specifiers addObject:[self partSpecifier:MenzenPartBigPicture named:MenzenLocalizedString(@"common.big_picture", @"Big Picture") enabled:YES]];
		[specifiers addObject:[self partSpecifier:MenzenPartSmallPicture named:MenzenLocalizedString(@"common.small_picture", @"Small Picture") enabled:bigPicture]];
		[specifiers addObject:[self partSpecifier:MenzenPartSmallPictureText named:MenzenLocalizedString(@"appearance.small_picture_text", @"Small Picture Text") enabled:smallPicture]];

		[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		[specifiers addObject:[self partSpecifier:MenzenPartTime named:MenzenLocalizedString(@"appearance.time", @"Time") enabled:YES]];
		PSSpecifier *links = MenzenSettingSpecifier(self, MenzenLocalizedString(@"appearance.links", @"Links"), MenzenSettingLinks, PSStaticTextCell);
		[links setProperty:MenzenChoiceCell.class forKey:@"cellClass"];
		[links setProperty:@[@[@YES, MenzenLocalizedString(@"common.on", @"On")], @[@NO, MenzenLocalizedString(@"common.off", @"Off")]] forKey:@"choices"];
		[links setProperty:@(MenzenSettingBool(MenzenSettingLinks, YES)) forKey:@"choice"];
		[specifiers addObject:links];
		_specifiers = specifiers;
	}

	return _specifiers;
}

- (PSSpecifier *)previewSpecifier {
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:nil target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
	specifier.identifier = @"preview";
	[specifier setProperty:MenzenCardPreviewCell.class forKey:@"cellClass"];
	[specifier setProperty:self.previewActivity forKey:@"activity"];
	return specifier;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([[self specifierAtIndexPath:indexPath] propertyForKey:@"choices"]) return MenzenChoiceRowHeight;
	return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	NSString *other = [specifier propertyForKey:@"swaps"][value];
	if (other) {
		PSSpecifier *swapped = MenzenSettingSpecifier(self, nil, other, PSStaticTextCell);
		[super setPreferenceValue:MenzenPart(specifier.identifier) specifier:swapped];
	}

	[super setPreferenceValue:value specifier:specifier];
	if (![specifier propertyForKey:@"choices"]) return;
	NSMutableArray<PSSpecifier *> *old = _specifiers;
	_specifiers = nil;
	NSArray<PSSpecifier *> *fresh = self.specifiers;
	_specifiers = old;
	if (old.count != fresh.count) {
		[self reloadSpecifiers];
		return;
	}

	for (NSUInteger i = 0; i < fresh.count; i++) {
		PSSpecifier *was = old[i], *now = fresh[i];
		if (![was propertyForKey:@"choices"]) continue;
		// Swaps are read when an option is picked, so they don't need a redraw.
		[was setProperty:[now propertyForKey:@"swaps"] forKey:@"swaps"];
		NSArray<NSString *> *keys = @[@"choice", @"enabled", @"disabledValues"];
		BOOL same = YES;
		for (NSString *key in keys) same = same && ([was propertyForKey:key] == [now propertyForKey:key] || [[was propertyForKey:key] isEqual:[now propertyForKey:key]]);
		if (same) continue;
		for (NSString *key in keys) [was setProperty:[now propertyForKey:key] forKey:key];
		// reloadSpecifier: doesn't redraw these cells; the visible one is
		// redrawn here, and one off screen is drawn fresh when it scrolls in.
		NSIndexPath *indexPath = [self indexPathForSpecifier:was];
		PSTableCell *cell = indexPath ? (PSTableCell *)[self.table cellForRowAtIndexPath:indexPath] : nil;
		if ([cell isKindOfClass:PSTableCell.class]) [cell refreshCellContentsWithSpecifier:was];
	}
}

@end

@implementation MenzenMemberListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specifiers = [self.previewSpecifiers mutableCopy];
		PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
		[group setProperty:MenzenLocalizedString(@"appearance.games_always_show_their_name", @"Games always show their name. When the line you pick is empty, the first line or the heading shows instead.") forKey:@"footerText"];
		[specifiers addObject:group];

		NSString *current = MenzenPart(MenzenPartMemberList);
		for (NSArray<NSString *> *choice in MenzenPartChoices(MenzenPartMemberList)) {
			NSString *name = choice[1];
			PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
			specifier.buttonAction = @selector(choose:);
			[specifier setProperty:MenzenCheckCell.class forKey:@"cellClass"];
			[specifier setProperty:choice[0] forKey:@"value"];
			[specifier setProperty:@([choice[0] isEqualToString:current]) forKey:@"checked"];
			[specifiers addObject:specifier];
		}
		_specifiers = specifiers;
	}

	return _specifiers;
}

- (PSSpecifier *)previewSpecifier {
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:nil target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
	specifier.identifier = @"preview";
	[specifier setProperty:MenzenMemberPreviewCell.class forKey:@"cellClass"];
	NSDictionary *profile = self.status[MenzenStatusProfileKey];
	if ([profile isKindOfClass:NSDictionary.class]) [specifier setProperty:profile forKey:@"profile"];
	[specifier setProperty:self.previewActivity forKey:@"activity"];
	return specifier;
}

- (void)choose:(PSSpecifier *)choice {
	PSSpecifier *setting = [PSSpecifier preferenceSpecifierNamed:nil target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
	[setting setProperty:MenzenSettingMemberList forKey:@"key"];
	[setting setProperty:MenzenSettingsDomain forKey:@"defaults"];
	[setting setProperty:@"details" forKey:@"default"];
	[setting setProperty:@MenzenSettingsChangedNotification forKey:@"PostNotification"];
	[self setPreferenceValue:[choice propertyForKey:@"value"] specifier:setting];
	[self reloadSpecifiers];
}

@end
