#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

#import "../../Shared/MenzenApelin.h"
#import "../../Shared/MenzenApps.h"
#import "../../Shared/MenzenLocalization/MenzenLocalization.h"
#import "../../Shared/MenzenProviders.h"
#import "../../Shared/MenzenSettings.h"
#import "../../Shared/MenzenSupport.h"
#import "../Helpers/MenzenAppSupport.h"
#import "../Helpers/MenzenServiceClient.h"
#import "../Views/MenzenLogoCell.h"
#import "MenzenSourcesListController.h"

@interface UIImage (MenzenPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

static BOOL MenzenInstalled(NSDictionary *provider) {
	return [MenzenWorkspace() applicationIsInstalled:provider[MenzenProviderBundleIdentifierKey]];
}

static void MenzenSetSetting(PSSpecifier *specifier, NSString *key, id fallback) {
	[specifier setProperty:key forKey:@"key"];
	[specifier setProperty:MenzenSettingsDomain forKey:@"defaults"];
	[specifier setProperty:fallback forKey:@"default"];
	[specifier setProperty:@MenzenSettingsChangedNotification forKey:@"PostNotification"];
}

static NSString *MenzenSourceKey(NSDictionary *provider) {
	return [MenzenSettingSourcePrefix stringByAppendingString:provider[MenzenProviderBundleIdentifierKey]];
}

static NSString *MenzenGameKey(NSDictionary *game) {
	return [MenzenSettingGamePrefix stringByAppendingString:game[MenzenGameBundleIdentifierKey]];
}

// Apps that aren't installed stay off and can't be switched on.
static PSSpecifier *MenzenSourceSwitch(id target, NSDictionary *provider, NSString *name) {
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name target:target set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
	MenzenSetSetting(specifier, MenzenSourceKey(provider), @YES);
	BOOL installed = MenzenInstalled(provider);
	[specifier setProperty:@(installed) forKey:@"enabled"];
	[specifier setProperty:@(!installed) forKey:@"notInstalled"];
	return specifier;
}

static void MenzenSetAppIcon(PSSpecifier *specifier, NSString *bundleIdentifier) {
	UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:bundleIdentifier format:0 scale:UIScreen.mainScreen.scale];
	if (icon) [specifier setProperty:icon forKey:@"iconImage"];
}

static void MenzenSetIcon(PSSpecifier *specifier, NSDictionary *provider) {
	if (MenzenInstalled(provider)) MenzenSetAppIcon(specifier, provider[MenzenProviderBundleIdentifierKey]);
}

static NSString *MenzenGameSummary(NSDictionary *game) {
	if (!MenzenSettingBool(MenzenGameKey(game), YES)) return MenzenLocalizedString(@"common.off", @"Off");
	return [game[MenzenGameListedKey] boolValue] ? @"On" : MenzenLocalizedString(@"common.no_icon", @"No Icon");
}

static NSString *MenzenSourceSummary(NSDictionary *provider, NSSet<NSString *> *hooked) {
	if (!MenzenInstalled(provider)) return MenzenLocalizedString(@"sources.not_installed", @"Not Installed");
	if (!MenzenSettingBool(MenzenSourceKey(provider), YES)) return MenzenLocalizedString(@"common.off", @"Off");
	return MenzenSupportStateFor(provider, MenzenAppSupportStatus(provider[MenzenProviderBundleIdentifierKey]), hooked) == MenzenSupportStateMayNotWork ? MenzenLocalizedString(@"common.may_not_work", @"May Not Work") : @"On";
}

@implementation MenzenSourcesListController {
	NSSet<NSString *> *_hooked;
	// From menzend (MenzenGame*Key); nil until it answers.
	NSArray<NSDictionary *> *_games;
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		_hooked = MenzenHookedBundles();
		NSMutableArray *specifiers = [NSMutableArray array];
		// Only the installed apps; the rest are on their own page.
		NSMutableArray<NSDictionary *> *missing = [NSMutableArray array];
		for (NSNumber *watching in @[@NO, @YES]) {
			NSMutableArray *rows = [NSMutableArray array];
			for (NSDictionary *provider in MenzenProviders()) {
				if ([provider[MenzenProviderWatchingKey] boolValue] != watching.boolValue) continue;
				if (!MenzenInstalled(provider)) {
					[missing addObject:provider];
					continue;
				}
				// A list cell for its value and layout; it opens the app's
				// page below, since PSListController only opens its own list
				// there.
				PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:provider[MenzenProviderNameKey] target:self set:nil get:@selector(sourceSummary:) detail:MenzenSourceListController.class cell:PSLinkListCell edit:nil];
				[specifier setProperty:provider forKey:@"provider"];
				MenzenSetIcon(specifier, provider);
				[rows addObject:specifier];
			}
			if (!rows.count) continue;
			[specifiers addObject:[PSSpecifier groupSpecifierWithName:watching.boolValue ? MenzenLocalizedString(@"common.watching", @"Watching") : MenzenLocalizedString(@"common.listening", @"Listening")]];
			[specifiers addObjectsFromArray:rows];
		}

		[specifiers addObjectsFromArray:[self gameSpecifiers]];

		if (missing.count) {
			PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
			if (missing.count == MenzenProviders().count) [group setProperty:MenzenLocalizedString(@"sources.none_of_the_apps_menzen_supports", @"None of the apps Menzen supports are installed.") forKey:@"footerText"];
			[specifiers addObject:group];
			PSSpecifier *more = [PSSpecifier preferenceSpecifierNamed:MenzenLocalizedString(@"common.more_supported_apps", @"More Supported Apps") target:self set:nil get:@selector(missingCount:) detail:MenzenMoreAppsListController.class cell:PSLinkListCell edit:nil];
			[more setProperty:missing forKey:@"providers"];
			[specifiers addObject:more];
		}

		PSSpecifier *other = [PSSpecifier groupSpecifierWithName:MenzenLocalizedString(@"sources.experimental", @"Experimental")];
		[other setProperty:MenzenLocalizedString(@"sources.shows_unsupported_apps_with_less_information", @"Shows unsupported apps, with less information. Browsers, chat and social networking apps are skipped.") forKey:@"footerText"];
		[specifiers addObject:other];
		PSSpecifier *otherApps = [PSSpecifier preferenceSpecifierNamed:MenzenLocalizedString(@"sources.other_apps", @"Other Apps") target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
		MenzenSetSetting(otherApps, MenzenSettingOtherApps, @NO);
		[specifiers addObject:otherApps];

		_specifiers = specifiers;
	}

	return _specifiers;
}

- (NSArray<PSSpecifier *> *)gameSpecifiers {
	if (!_games.count) return @[];
	NSMutableArray *specifiers = [NSMutableArray array];
	PSSpecifier *group = [PSSpecifier groupSpecifierWithName:MenzenLocalizedString(@"common.playing", @"Playing")];
	[specifiers addObject:group];
	for (NSDictionary *game in _games) {
		PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:game[MenzenGameNameKey] target:self set:nil get:@selector(gameSummary:) detail:MenzenGameListController.class cell:PSLinkListCell edit:nil];
		[row setProperty:game forKey:@"game"];
		MenzenSetAppIcon(row, game[MenzenGameBundleIdentifierKey]);
		[specifiers addObject:row];
	}

	return specifiers;
}

- (void)loadGames {
	__weak typeof(self) weakSelf = self;
	[MenzenServiceProxy(nil) gamesWithReply:^(NSArray<NSDictionary *> *games) {
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf || [games isEqual:strongSelf->_games]) return;
			strongSelf->_games = games;
			[strongSelf reloadSpecifiers];
		});
	}];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.title = MenzenLocalizedString(@"sources.apps", @"Apps");
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reloadSpecifiers];
	[self loadGames];
}

- (NSString *)sourceSummary:(PSSpecifier *)specifier {
	return MenzenSourceSummary([specifier propertyForKey:@"provider"], _hooked);
}

- (NSString *)gameSummary:(PSSpecifier *)specifier {
	return MenzenGameSummary([specifier propertyForKey:@"game"]);
}

- (NSString *)missingCount:(PSSpecifier *)specifier {
	return @([[specifier propertyForKey:@"providers"] count]).stringValue;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
	Class controllerClass = [specifier propertyForKey:@"provider"] ? MenzenSourceListController.class : [specifier propertyForKey:@"game"] ? MenzenGameListController.class
																																		   : nil;
	if (!controllerClass) {
		[super tableView:tableView didSelectRowAtIndexPath:indexPath];
		return;
	}

	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	PSListController *controller = [controllerClass new];
	controller.specifier = specifier;
	controller.rootController = self.rootController;
	controller.parentController = self;
	[self showController:controller animate:YES];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
	if ([[specifier propertyForKey:@"notInstalled"] boolValue]) return @NO;
	return [super readPreferenceValue:specifier];
}

@end

@implementation MenzenSourceListController

- (NSDictionary *)provider {
	return [self.specifier propertyForKey:@"provider"];
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSDictionary *provider = self.provider;
		NSMutableArray *specifiers = [NSMutableArray array];
		[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		[specifiers addObject:MenzenSourceSwitch(self, provider, provider[MenzenProviderNameKey])];
		if (MenzenInstalled(provider)) [specifiers addObjectsFromArray:[self supportSpecifiers]];
		_specifiers = specifiers;
	}

	return _specifiers;
}

- (NSArray<PSSpecifier *> *)supportSpecifiers {
	NSDictionary *provider = self.provider;
	NSString *name = provider[MenzenProviderNameKey];
	NSDictionary *status = MenzenAppSupportStatus(provider[MenzenProviderBundleIdentifierKey]);
	MenzenSupportState state = MenzenSupportStateFor(provider, status, MenzenHookedBundles());
	NSString *version = MenzenInstalledVersion(provider);
	NSMutableArray *specifiers = [NSMutableArray array];

	PSSpecifier *group = [PSSpecifier groupSpecifierWithName:MenzenLocalizedString(@"common.support", @"Support")];
	[specifiers addObject:group];
	NSString *summary, *footer;
	switch (state) {
		case MenzenSupportStateNotHooked:
			summary = MenzenLocalizedString(@"sources.media_controls_only", @"Media Controls Only");
			footer = [NSString stringWithFormat:MenzenLocalizedString(@"sources.menzen_shows_what_x_shares_with", @"Menzen shows what %@ shares with the system's media controls."), name];
			break;
		case MenzenSupportStateNotChecked:
			summary = MenzenLocalizedString(@"sources.not_checked", @"Not Checked");
			footer = [NSString stringWithFormat:MenzenLocalizedString(@"sources.menzen_hasn_t_checked_this_version", @"Menzen hasn't checked this version of %@ yet. Opening it lets Menzen check, then brings you back here."), name];
			break;
		case MenzenSupportStateNotFullyChecked:
			summary = MenzenLocalizedString(@"sources.not_fully_checked", @"Not Fully Checked");
			footer = [NSString stringWithFormat:MenzenLocalizedString(@"sources.some_parts_of_x_only_load", @"Some parts of %@ only load once it's open. Opening it lets Menzen finish checking, then brings you back here."), name];
			break;
		case MenzenSupportStateWorks:
			summary = MenzenLocalizedString(@"common.works", @"Works");
			break;
		case MenzenSupportStateMayNotWork:
			summary = MenzenLocalizedString(@"common.may_not_work", @"May Not Work");
			break;
	}

	[group setProperty:footer forKey:@"footerText"];

	PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:MenzenLocalizedString(@"common.status", @"Status") target:self set:nil get:@selector(supportValue:) detail:nil cell:PSTitleValueCell edit:nil];
	[row setProperty:summary forKey:@"supportValue"];
	[specifiers addObject:row];
	if (state != MenzenSupportStateNotHooked) {
		PSSpecifier *versionRow = [PSSpecifier preferenceSpecifierNamed:MenzenLocalizedString(@"common.version", @"Version") target:self set:nil get:@selector(supportValue:) detail:nil cell:PSTitleValueCell edit:nil];
		[versionRow setProperty:version forKey:@"supportValue"];
		[specifiers addObject:versionRow];
	}

	if (state == MenzenSupportStateNotChecked || state == MenzenSupportStateNotFullyChecked || state == MenzenSupportStateMayNotWork) [specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
	if (state == MenzenSupportStateNotChecked || state == MenzenSupportStateNotFullyChecked) {
		PSSpecifier *check = [PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:MenzenLocalizedString(@"sources.open_x_to_check", @"Open %@ to Check"), name] target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
		check.buttonAction = @selector(openToCheck:);
		[specifiers addObject:check];
	}

	if (state == MenzenSupportStateMayNotWork) {
		NSString *details = MenzenSupportDetails(name, version, provider[MenzenProviderBundleIdentifierKey], @MENZEN_VERSION, UIDevice.currentDevice.systemVersion, MenzenMissingParts(status));
		PSSpecifier *copy = [PSSpecifier preferenceSpecifierNamed:MenzenLocalizedString(@"common.copy_details", @"Copy Details") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
		copy.buttonAction = @selector(copyDetails:);
		[copy setProperty:details forKey:@"details"];
		[specifiers addObject:copy];
		PSSpecifier *report = [PSSpecifier preferenceSpecifierNamed:MenzenLocalizedString(@"common.report_on_github", @"Report on GitHub") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
		report.buttonAction = @selector(report:);
		[report setProperty:details forKey:@"details"];
		[specifiers addObject:report];
	}

	return specifiers;
}

- (void)openToCheck:(PSSpecifier *)specifier {
	[MenzenServiceProxy(nil) checkAppWithBundleIdentifier:self.provider[MenzenProviderBundleIdentifierKey]];
}

- (NSString *)supportValue:(PSSpecifier *)specifier {
	return [specifier propertyForKey:@"supportValue"];
}

- (void)report:(PSSpecifier *)specifier {
	NSString *details = [specifier propertyForKey:@"details"];
	[UIApplication.sharedApplication openURL:MenzenSupportReportURL(self.provider[MenzenProviderNameKey], MenzenInstalledVersion(self.provider), details) options:@{} completionHandler:nil];
}

- (void)copyDetails:(PSSpecifier *)specifier {
	UIPasteboard.generalPasteboard.string = [specifier propertyForKey:@"details"];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.title = self.provider[MenzenProviderNameKey];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reloadSpecifiers];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
	if ([[specifier propertyForKey:@"notInstalled"] boolValue]) return @NO;
	return [super readPreferenceValue:specifier];
}

@end

@implementation MenzenGameListController {
	NSDictionary *_game;
}

- (NSDictionary *)game {
	return _game ?: [self.specifier propertyForKey:@"game"];
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSDictionary *game = self.game;
		NSString *name = game[MenzenGameNameKey];
		BOOL listed = [game[MenzenGameListedKey] boolValue];
		NSMutableArray *specifiers = [NSMutableArray array];
		[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		PSSpecifier *toggle = [PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
		MenzenSetSetting(toggle, MenzenGameKey(game), @YES);
		[specifiers addObject:toggle];
		if ([game[MenzenGameBundleIdentifierKey] isEqualToString:MenzenApelinBundleIdentifier]) [specifiers addObjectsFromArray:[self apelinSpecifiers]];

		[specifiers addObject:[PSSpecifier groupSpecifierWithName:MenzenLocalizedString(@"common.support", @"Support")]];
		PSSpecifier *status = [PSSpecifier preferenceSpecifierNamed:MenzenLocalizedString(@"common.status", @"Status") target:self set:nil get:@selector(supportValue:) detail:nil cell:PSTitleValueCell edit:nil];
		[status setProperty:listed ? MenzenLocalizedString(@"common.works", @"Works") : MenzenLocalizedString(@"common.no_icon", @"No Icon") forKey:@"supportValue"];
		[specifiers addObject:status];
		PSSpecifier *versionRow = [PSSpecifier preferenceSpecifierNamed:MenzenLocalizedString(@"common.version", @"Version") target:self set:nil get:@selector(supportValue:) detail:nil cell:PSTitleValueCell edit:nil];
		[versionRow setProperty:MenzenInstalledAppVersion(game[MenzenGameBundleIdentifierKey]) ?: @"?" forKey:@"supportValue"];
		[specifiers addObject:versionRow];
		if (!listed) {
			[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
			PSSpecifier *request = [PSSpecifier preferenceSpecifierNamed:MenzenLocalizedString(@"sources.request_icon_on_github", @"Request Icon on GitHub") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
			request.buttonAction = @selector(requestIcon:);
			[specifiers addObject:request];
		}
		_specifiers = specifiers;
	}

	return _specifiers;
}

- (NSString *)supportValue:(PSSpecifier *)specifier {
	return [specifier propertyForKey:@"supportValue"];
}

// What the agent's session adds below the name.
- (NSArray<PSSpecifier *> *)apelinSpecifiers {
	NSMutableArray *specifiers = [NSMutableArray arrayWithObject:[PSSpecifier groupSpecifierWithName:MenzenLocalizedString(@"sources.activity", @"Activity")]];
	NSDictionary *rows = @{MenzenLocalizedString(@"common.project_name", @"Project Name"): MenzenSettingApelinProject, MenzenLocalizedString(@"common.agent_status", @"Agent Status"): MenzenSettingApelinAgent};
	for (NSString *name in @[MenzenLocalizedString(@"common.project_name", @"Project Name"), MenzenLocalizedString(@"common.agent_status", @"Agent Status")]) {
		PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
		MenzenSetSetting(row, rows[name], @YES);
		[specifiers addObject:row];
	}

	return specifiers;
}

- (void)requestIcon:(PSSpecifier *)specifier {
	[UIApplication.sharedApplication openURL:MenzenAppRequestURL(self.game[MenzenGameBundleIdentifierKey]) options:@{} completionHandler:nil];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.title = self.game[MenzenGameNameKey];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	NSString *bundleIdentifier = self.game[MenzenGameBundleIdentifierKey];
	__weak typeof(self) weakSelf = self;
	[MenzenServiceProxy(nil) gamesWithReply:^(NSArray<NSDictionary *> *games) {
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			for (NSDictionary *game in games) {
				if (![game[MenzenGameBundleIdentifierKey] isEqualToString:bundleIdentifier] || [game isEqual:strongSelf.game]) continue;
				strongSelf->_game = game;
				[strongSelf reloadSpecifiers];
			}
		});
	}];
}

@end

@implementation MenzenMoreAppsListController {
	NSDictionary<NSString *, NSString *> *_icons;
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSArray<NSDictionary *> *providers = [self.specifier propertyForKey:@"providers"];
		NSMutableArray *specifiers = [NSMutableArray array];
		for (NSNumber *watching in @[@NO, @YES]) {
			NSMutableArray *rows = [NSMutableArray array];
			for (NSDictionary *provider in providers) {
				if ([provider[MenzenProviderWatchingKey] boolValue] != watching.boolValue) continue;
				PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:provider[MenzenProviderNameKey] target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
				[specifier setProperty:MenzenLogoCell.class forKey:@"cellClass"];
				[specifier setProperty:_icons[provider[MenzenProviderBundleIdentifierKey]] forKey:@"logo"];
				[rows addObject:specifier];
			}
			if (!rows.count) continue;
			[specifiers addObject:[PSSpecifier groupSpecifierWithName:watching.boolValue ? MenzenLocalizedString(@"common.watching", @"Watching") : MenzenLocalizedString(@"common.listening", @"Listening")]];
			[specifiers addObjectsFromArray:rows];
		}
		_specifiers = specifiers;
	}

	return _specifiers;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.title = MenzenLocalizedString(@"common.more_supported_apps", @"More Supported Apps");
	__weak typeof(self) weakSelf = self;
	[MenzenServiceProxy(nil) appIconsWithReply:^(NSDictionary<NSString *, NSString *> *icons) {
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf || [icons isEqual:strongSelf->_icons]) return;
			strongSelf->_icons = icons;
			[strongSelf reloadSpecifiers];
		});
	}];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return MenzenLogoCellHeight;
}

@end
