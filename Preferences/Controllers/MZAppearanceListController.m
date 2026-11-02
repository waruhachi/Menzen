#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

#import "../../Shared/MZCard.h"
#import "../../Shared/MZService.h"
#import "../../Shared/MZSettings.h"
#import "../Helpers/MZServiceClient.h"
#import "../Views/MZChoiceCells.h"
#import "../Views/MZPreviewCells.h"
#import "MZAppearanceListController.h"

static NSString *MZTrimmed(NSString *string) {
	return [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

// Made-up song for the previews until something has played, following the
// card's parts the way menzend does. It has no cover or artist picture, so
// pictures fall back to the logo.
static NSDictionary<NSString *, id> *MZSampleActivity(void) {
	NSDictionary *texts = @{@"title": @"Song Title", @"artist": @"Artist", @"album": @"Album"};
	NSMutableDictionary *activity = [NSMutableDictionary dictionary];
	activity[MZActivityKindKey] = @"listening";

	NSString *heading = MZPart(MZPartHeading);
	NSString *headingText = MZTrimmed(MZSettingString(MZSettingHeadingText, @""));
	if ([heading isEqualToString:@"custom"]) activity[MZActivityNameKey] = headingText.length ? headingText : nil;
	else if (![heading isEqualToString:@"menzen"]) activity[MZActivityNameKey] = texts[heading] ?: @"Apple Music";

	activity[MZActivityDetailsKey] = texts[MZPart(MZPartFirstLine)];
	NSString *state = texts[MZPart(MZPartSecondLine)];
	if (![state isEqualToString:activity[MZActivityDetailsKey]]) activity[MZActivityStateKey] = state;
	if (![MZPart(MZPartBigPicture) isEqualToString:@"none"]) {
		activity[MZActivityImageURLKey] = @"apple_music";
		NSString *thirdLine = texts[MZPart(MZPartThirdLine)];
		if (thirdLine && ![thirdLine isEqualToString:activity[MZActivityDetailsKey]] && ![thirdLine isEqualToString:state]) activity[MZActivityLargeTextKey] = thirdLine;
	}

	NSString *memberList = MZMemberListDisplay();
	activity[MZActivityStatusDisplayKey] = !memberList || ([memberList isEqualToString:@"state"] && !activity[MZActivityStateKey]) ? @"details" : memberList;

	NSTimeInterval now = NSDate.date.timeIntervalSince1970;
	activity[MZActivityStartKey] = @(now - 72);
	if ([MZPart(MZPartTime) isEqualToString:@"progress"]) activity[MZActivityEndKey] = @(now - 72 + 201);
	activity[MZActivityPausedKey] = @(now);
	return activity;
}

static NSDictionary<NSString *, id> *MZPreviewActivity(NSDictionary *status) {
	NSDictionary *preview = status[MZStatusPreviewKey];
	return [preview isKindOfClass:NSDictionary.class] ? preview : MZSampleActivity();
}

@implementation MZPreviewListController {
	NSDictionary<NSString *, id> *_status;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshStatus) name:MZStatusDidChangeNotification object:nil];
	[self refreshStatus];
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
	MZFetchStatus(^(NSDictionary *status) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || !status) return;
		strongSelf->_status = status;
		[strongSelf reloadPreview];
	});
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

static PSSpecifier *MZSettingSpecifier(id target, NSString *name, NSString *key, PSCellType cell) {
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name target:target set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:cell edit:nil];
	specifier.identifier = key;
	[specifier setProperty:key forKey:@"key"];
	[specifier setProperty:MZSettingsDomain forKey:@"defaults"];
	[specifier setProperty:@MZSettingsChangedNotification forKey:@"PostNotification"];
	return specifier;
}

@implementation MZCardListController

static BOOL MZPartAllows(NSString *part, NSString *value) {
	for (NSArray<NSString *> *choice in MZPartChoices(part)) {
		if ([choice.firstObject isEqualToString:value]) return YES;
	}

	return NO;
}

// A menu of the part's choices. Menzen leaves out a line or picture that
// repeats one, so picking what another shown part of its kind uses swaps the
// two; when that part can't take this one's choice, the option is greyed out.
- (PSSpecifier *)partSpecifier:(NSString *)part named:(NSString *)name enabled:(BOOL)enabled {
	PSSpecifier *specifier = MZSettingSpecifier(self, name, part, PSStaticTextCell);
	[specifier setProperty:MZChoiceCell.class forKey:@"cellClass"];
	[specifier setProperty:MZPartChoices(part) forKey:@"choices"];
	[specifier setProperty:MZPart(part) forKey:@"choice"];
	[specifier setProperty:@(enabled) forKey:@"enabled"];

	// Without a big picture, Discord shows neither its text nor a small picture.
	BOOL bigPicture = ![MZPart(MZPartBigPicture) isEqualToString:@"none"];
	NSArray *shown = bigPicture ? @[@[MZPartHeading, MZPartFirstLine, MZPartSecondLine, MZPartThirdLine], @[MZPartBigPicture, MZPartSmallPicture]] : @[@[MZPartHeading, MZPartFirstLine, MZPartSecondLine]];
	NSString *current = MZPart(part);
	NSMutableArray *disabled = [NSMutableArray array];
	NSMutableDictionary<NSString *, NSString *> *swaps = [NSMutableDictionary dictionary];
	for (NSArray<NSString *> *kind in shown) {
		if (![kind containsObject:part]) continue;
		for (NSString *other in kind) {
			NSString *value = MZPart(other);
			if ([other isEqualToString:part] || [value isEqualToString:@"none"]) continue;
			if (MZPartAllows(other, current)) swaps[value] = other;
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
		BOOL bigPicture = ![MZPart(MZPartBigPicture) isEqualToString:@"none"];
		BOOL smallPicture = bigPicture && ![MZPart(MZPartSmallPicture) isEqualToString:@"none"];

		NSMutableArray *specifiers = [NSMutableArray arrayWithObjects:[PSSpecifier emptyGroupSpecifier], self.previewSpecifier, nil];
		[specifiers addObject:[PSSpecifier groupSpecifierWithName:@"Text"]];
		[specifiers addObject:[self partSpecifier:MZPartHeading named:@"Heading" enabled:YES]];
		if ([MZPart(MZPartHeading) isEqualToString:@"custom"]) {
			PSSpecifier *text = MZSettingSpecifier(self, @"Custom Heading", MZSettingHeadingText, PSEditTextCell);
			[text setProperty:@"" forKey:@"default"];
			[text setProperty:@"Name" forKey:@"placeholder"];
			[text setProperty:@YES forKey:@"noAutoCorrect"];
			[specifiers addObject:text];
		}
		[specifiers addObject:[self partSpecifier:MZPartFirstLine named:@"First Line" enabled:YES]];
		[specifiers addObject:[self partSpecifier:MZPartSecondLine named:@"Second Line" enabled:YES]];
		[specifiers addObject:[self partSpecifier:MZPartThirdLine named:@"Third Line" enabled:bigPicture]];

		[specifiers addObject:[PSSpecifier groupSpecifierWithName:@"Pictures"]];
		[specifiers addObject:[self partSpecifier:MZPartBigPicture named:@"Big Picture" enabled:YES]];
		[specifiers addObject:[self partSpecifier:MZPartSmallPicture named:@"Small Picture" enabled:bigPicture]];
		[specifiers addObject:[self partSpecifier:MZPartSmallPictureText named:@"Small Picture Text" enabled:smallPicture]];

		[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		[specifiers addObject:[self partSpecifier:MZPartTime named:@"Time" enabled:YES]];
		PSSpecifier *links = MZSettingSpecifier(self, @"Links", MZSettingLinks, PSStaticTextCell);
		[links setProperty:MZChoiceCell.class forKey:@"cellClass"];
		[links setProperty:@[@[@YES, @"On"], @[@NO, @"Off"]] forKey:@"choices"];
		[links setProperty:@(MZSettingBool(MZSettingLinks, YES)) forKey:@"choice"];
		[specifiers addObject:links];
		_specifiers = specifiers;
	}

	return _specifiers;
}

- (PSSpecifier *)previewSpecifier {
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:nil target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
	specifier.identifier = @"preview";
	[specifier setProperty:MZCardPreviewCell.class forKey:@"cellClass"];
	[specifier setProperty:MZPreviewActivity(self.status) forKey:@"activity"];
	return specifier;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([[self specifierAtIndexPath:indexPath] propertyForKey:@"choices"]) return MZChoiceRowHeight;
	return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	// The part using the new choice takes this one's old choice.
	NSString *other = [specifier propertyForKey:@"swaps"][value];
	if (other) {
		PSSpecifier *swapped = MZSettingSpecifier(self, nil, other, PSStaticTextCell);
		[super setPreferenceValue:MZPart(specifier.identifier) specifier:swapped];
	}

	[super setPreferenceValue:value specifier:specifier];
	if (![specifier propertyForKey:@"choices"]) return;
	// Menus show the new choice, and parts that depend on it follow. Only
	// rows that changed are reloaded; the custom heading row comes and goes.
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

@implementation MZMemberListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specifiers = [NSMutableArray arrayWithObjects:[PSSpecifier emptyGroupSpecifier], self.previewSpecifier, nil];
		PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
		[group setProperty:@"Member lists can only show the heading, first line or second line. To pick something greyed out, put it on one of those lines on the Activity page." forKey:@"footerText"];
		[specifiers addObject:group];

		NSString *current = MZPart(MZPartMemberList);
		NSString *heading = MZPart(MZPartHeading);
		for (NSArray<NSString *> *choice in MZPartChoices(MZPartMemberList)) {
			NSString *name = choice[1];
			if ([choice[0] isEqualToString:@"name"]) {
				// A heading of Artist or Album is already offered as that.
				if ([heading isEqualToString:@"artist"] || [heading isEqualToString:@"album"]) continue;
				NSString *text = MZTrimmed(MZSettingString(MZSettingHeadingText, @""));
				name = [heading isEqualToString:@"custom"] ? (text.length ? text : @"Custom Heading") : MZPartTitle(MZPartHeading, heading);
			}
			PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
			specifier.buttonAction = @selector(choose:);
			[specifier setProperty:MZCheckCell.class forKey:@"cellClass"];
			[specifier setProperty:choice[0] forKey:@"value"];
			[specifier setProperty:@([choice[0] isEqualToString:current]) forKey:@"checked"];
			[specifier setProperty:@(!!MZMemberListDisplayFor(choice[0])) forKey:@"enabled"];
			[specifiers addObject:specifier];
		}
		_specifiers = specifiers;
	}

	return _specifiers;
}

- (PSSpecifier *)previewSpecifier {
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:nil target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
	specifier.identifier = @"preview";
	[specifier setProperty:MZMemberPreviewCell.class forKey:@"cellClass"];
	NSDictionary *profile = self.status[MZStatusProfileKey];
	if ([profile isKindOfClass:NSDictionary.class]) [specifier setProperty:profile forKey:@"profile"];
	[specifier setProperty:MZPreviewActivity(self.status) forKey:@"activity"];
	return specifier;
}

- (void)choose:(PSSpecifier *)choice {
	PSSpecifier *setting = [PSSpecifier preferenceSpecifierNamed:nil target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
	[setting setProperty:MZSettingMemberList forKey:@"key"];
	[setting setProperty:MZSettingsDomain forKey:@"defaults"];
	[setting setProperty:@"title" forKey:@"default"];
	[setting setProperty:@MZSettingsChangedNotification forKey:@"PostNotification"];
	[self setPreferenceValue:[choice propertyForKey:@"value"] specifier:setting];
	[self reloadSpecifiers];
}

@end
