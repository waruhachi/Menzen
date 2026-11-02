#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

#import "../../Shared/MZApelin.h"
#import "../../Shared/MZApps.h"
#import "../../Shared/MZProviders.h"
#import "../../Shared/MZSettings.h"
#import "../../Shared/MZSupport.h"
#import "../Helpers/MZAppSupport.h"
#import "../Helpers/MZServiceClient.h"
#import "../Views/MZLogoCell.h"
#import "MZSourcesListController.h"

@interface UIImage (MZPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

static BOOL MZInstalled(NSDictionary *provider) {
	return [MZWorkspace() applicationIsInstalled:provider[MZProviderBundleIdentifierKey]];
}

static void MZSetSetting(PSSpecifier *specifier, NSString *key, id fallback) {
	[specifier setProperty:key forKey:@"key"];
	[specifier setProperty:MZSettingsDomain forKey:@"defaults"];
	[specifier setProperty:fallback forKey:@"default"];
	[specifier setProperty:@MZSettingsChangedNotification forKey:@"PostNotification"];
}

static NSString *MZSourceKey(NSDictionary *provider) {
	return [MZSettingSourcePrefix stringByAppendingString:provider[MZProviderBundleIdentifierKey]];
}

static NSString *MZGameKey(NSDictionary *game) {
	return [MZSettingGamePrefix stringByAppendingString:game[MZGameBundleIdentifierKey]];
}

// Apps that aren't installed stay off and can't be switched on.
static PSSpecifier *MZSourceSwitch(id target, NSDictionary *provider, NSString *name) {
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name target:target set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
	MZSetSetting(specifier, MZSourceKey(provider), @YES);
	BOOL installed = MZInstalled(provider);
	[specifier setProperty:@(installed) forKey:@"enabled"];
	[specifier setProperty:@(!installed) forKey:@"notInstalled"];
	return specifier;
}

static void MZSetAppIcon(PSSpecifier *specifier, NSString *bundleIdentifier) {
	UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:bundleIdentifier format:0 scale:UIScreen.mainScreen.scale];
	if (icon) [specifier setProperty:icon forKey:@"iconImage"];
}

static void MZSetIcon(PSSpecifier *specifier, NSDictionary *provider) {
	if (MZInstalled(provider)) MZSetAppIcon(specifier, provider[MZProviderBundleIdentifierKey]);
}

static NSString *MZGameSummary(NSDictionary *game) {
	if (!MZSettingBool(MZGameKey(game), YES)) return @"Off";
	return [game[MZGameListedKey] boolValue] ? @"On" : @"No Icon";
}

static NSString *MZSourceSummary(NSDictionary *provider, NSSet<NSString *> *hooked) {
	if (!MZInstalled(provider)) return @"Not Installed";
	if (!MZSettingBool(MZSourceKey(provider), YES)) return @"Off";
	return MZSupportStateFor(provider, MZAppSupportStatus(provider[MZProviderBundleIdentifierKey]), hooked) == MZSupportStateMayNotWork ? @"May Not Work" : @"On";
}

@implementation MZSourcesListController {
	NSSet<NSString *> *_hooked;
	// From menzend (MZGame*Key); nil until it answers.
	NSArray<NSDictionary *> *_games;
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		_hooked = MZHookedBundles();
		NSMutableArray *specifiers = [NSMutableArray array];
		// Only the installed apps; the rest are on their own page.
		NSMutableArray<NSDictionary *> *missing = [NSMutableArray array];
		for (NSNumber *watching in @[@NO, @YES]) {
			NSMutableArray *rows = [NSMutableArray array];
			for (NSDictionary *provider in MZProviders()) {
				if ([provider[MZProviderWatchingKey] boolValue] != watching.boolValue) continue;
				if (!MZInstalled(provider)) {
					[missing addObject:provider];
					continue;
				}
				// A list cell for its value and layout; it opens the app's
				// page below, since PSListController only opens its own list
				// there.
				PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:provider[MZProviderNameKey] target:self set:nil get:@selector(sourceSummary:) detail:MZSourceListController.class cell:PSLinkListCell edit:nil];
				[specifier setProperty:provider forKey:@"provider"];
				MZSetIcon(specifier, provider);
				[rows addObject:specifier];
			}
			if (!rows.count) continue;
			[specifiers addObject:[PSSpecifier groupSpecifierWithName:watching.boolValue ? @"Watching" : @"Listening"]];
			[specifiers addObjectsFromArray:rows];
		}

		[specifiers addObjectsFromArray:[self gameSpecifiers]];

		if (missing.count) {
			PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
			if (missing.count == MZProviders().count) [group setProperty:@"None of the apps Menzen supports are installed." forKey:@"footerText"];
			[specifiers addObject:group];
			PSSpecifier *more = [PSSpecifier preferenceSpecifierNamed:@"More Supported Apps" target:self set:nil get:@selector(missingCount:) detail:MZMoreAppsListController.class cell:PSLinkListCell edit:nil];
			[more setProperty:missing forKey:@"providers"];
			[specifiers addObject:more];
		}

		PSSpecifier *other = [PSSpecifier groupSpecifierWithName:@"Experimental"];
		[other setProperty:@"Shows unsupported apps, with less information. Browsers, chat and social networking apps are skipped." forKey:@"footerText"];
		[specifiers addObject:other];
		PSSpecifier *otherApps = [PSSpecifier preferenceSpecifierNamed:@"Other Apps" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
		MZSetSetting(otherApps, MZSettingOtherApps, @NO);
		[specifiers addObject:otherApps];

		_specifiers = specifiers;
	}

	return _specifiers;
}

- (NSArray<PSSpecifier *> *)gameSpecifiers {
	if (!_games.count) return @[];
	NSMutableArray *specifiers = [NSMutableArray array];
	PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"Playing"];
	[specifiers addObject:group];
	for (NSDictionary *game in _games) {
		PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:game[MZGameNameKey] target:self set:nil get:@selector(gameSummary:) detail:MZGameListController.class cell:PSLinkListCell edit:nil];
		[row setProperty:game forKey:@"game"];
		MZSetAppIcon(row, game[MZGameBundleIdentifierKey]);
		[specifiers addObject:row];
	}

	return specifiers;
}

- (void)loadGames {
	__weak typeof(self) weakSelf = self;
	[MZServiceProxy(nil) gamesWithReply:^(NSArray<NSDictionary *> *games) {
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
	self.title = @"Apps";
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reloadSpecifiers];
	[self loadGames];
}

- (NSString *)sourceSummary:(PSSpecifier *)specifier {
	return MZSourceSummary([specifier propertyForKey:@"provider"], _hooked);
}

- (NSString *)gameSummary:(PSSpecifier *)specifier {
	return MZGameSummary([specifier propertyForKey:@"game"]);
}

- (NSString *)missingCount:(PSSpecifier *)specifier {
	return @([[specifier propertyForKey:@"providers"] count]).stringValue;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
	Class controllerClass = [specifier propertyForKey:@"provider"] ? MZSourceListController.class : [specifier propertyForKey:@"game"] ? MZGameListController.class
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

@implementation MZSourceListController

- (NSDictionary *)provider {
	return [self.specifier propertyForKey:@"provider"];
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSDictionary *provider = self.provider;
		NSMutableArray *specifiers = [NSMutableArray array];
		[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		[specifiers addObject:MZSourceSwitch(self, provider, provider[MZProviderNameKey])];
		if (MZInstalled(provider)) [specifiers addObjectsFromArray:[self supportSpecifiers]];
		_specifiers = specifiers;
	}

	return _specifiers;
}

- (NSArray<PSSpecifier *> *)supportSpecifiers {
	NSDictionary *provider = self.provider;
	NSString *name = provider[MZProviderNameKey];
	NSDictionary *status = MZAppSupportStatus(provider[MZProviderBundleIdentifierKey]);
	MZSupportState state = MZSupportStateFor(provider, status, MZHookedBundles());
	NSString *version = MZInstalledVersion(provider);
	NSMutableArray *specifiers = [NSMutableArray array];

	PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"Support"];
	[specifiers addObject:group];
	NSString *summary, *footer;
	switch (state) {
		case MZSupportStateNotHooked:
			summary = @"Media Controls Only";
			footer = [NSString stringWithFormat:@"Menzen shows what %@ shares with the system's media controls.", name];
			break;
		case MZSupportStateNotChecked:
			summary = @"Not Checked";
			footer = [NSString stringWithFormat:@"Menzen hasn't checked this version of %@ yet. Opening it lets Menzen check, then brings you back here.", name];
			break;
		case MZSupportStateNotFullyChecked:
			summary = @"Not Fully Checked";
			footer = [NSString stringWithFormat:@"Some parts of %@ only load once it's open. Opening it lets Menzen finish checking, then brings you back here.", name];
			break;
		case MZSupportStateWorks:
			summary = @"Works";
			break;
		case MZSupportStateMayNotWork:
			summary = @"May Not Work";
			break;
	}

	[group setProperty:footer forKey:@"footerText"];

	PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:@"Status" target:self set:nil get:@selector(supportValue:) detail:nil cell:PSTitleValueCell edit:nil];
	[row setProperty:summary forKey:@"supportValue"];
	[specifiers addObject:row];
	if (state != MZSupportStateNotHooked) {
		PSSpecifier *versionRow = [PSSpecifier preferenceSpecifierNamed:@"Version" target:self set:nil get:@selector(supportValue:) detail:nil cell:PSTitleValueCell edit:nil];
		[versionRow setProperty:version forKey:@"supportValue"];
		[specifiers addObject:versionRow];
	}

	if (state == MZSupportStateNotChecked || state == MZSupportStateNotFullyChecked || state == MZSupportStateMayNotWork) [specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
	if (state == MZSupportStateNotChecked || state == MZSupportStateNotFullyChecked) {
		PSSpecifier *check = [PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"Open %@ to Check", name] target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
		check.buttonAction = @selector(openToCheck:);
		[specifiers addObject:check];
	}

	if (state == MZSupportStateMayNotWork) {
		NSString *details = MZSupportDetails(name, version, provider[MZProviderBundleIdentifierKey], @MZ_VERSION, UIDevice.currentDevice.systemVersion, MZMissingParts(status));
		PSSpecifier *copy = [PSSpecifier preferenceSpecifierNamed:@"Copy Details" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
		copy.buttonAction = @selector(copyDetails:);
		[copy setProperty:details forKey:@"details"];
		[specifiers addObject:copy];
		PSSpecifier *report = [PSSpecifier preferenceSpecifierNamed:@"Report on GitHub" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
		report.buttonAction = @selector(report:);
		[report setProperty:details forKey:@"details"];
		[specifiers addObject:report];
	}

	return specifiers;
}

- (void)openToCheck:(PSSpecifier *)specifier {
	[MZServiceProxy(nil) checkAppWithBundleIdentifier:self.provider[MZProviderBundleIdentifierKey]];
}

- (NSString *)supportValue:(PSSpecifier *)specifier {
	return [specifier propertyForKey:@"supportValue"];
}

- (void)report:(PSSpecifier *)specifier {
	NSString *details = [specifier propertyForKey:@"details"];
	[UIApplication.sharedApplication openURL:MZSupportReportURL(self.provider[MZProviderNameKey], MZInstalledVersion(self.provider), details) options:@{} completionHandler:nil];
}

- (void)copyDetails:(PSSpecifier *)specifier {
	UIPasteboard.generalPasteboard.string = [specifier propertyForKey:@"details"];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.title = self.provider[MZProviderNameKey];
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

@implementation MZGameListController {
	NSDictionary *_game;
}

- (NSDictionary *)game {
	return _game ?: [self.specifier propertyForKey:@"game"];
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSDictionary *game = self.game;
		NSString *name = game[MZGameNameKey];
		BOOL listed = [game[MZGameListedKey] boolValue];
		NSMutableArray *specifiers = [NSMutableArray array];
		[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		PSSpecifier *toggle = [PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
		MZSetSetting(toggle, MZGameKey(game), @YES);
		[specifiers addObject:toggle];
		if ([game[MZGameBundleIdentifierKey] isEqualToString:MZApelinBundleIdentifier]) [specifiers addObjectsFromArray:[self apelinSpecifiers]];

		[specifiers addObject:[PSSpecifier groupSpecifierWithName:@"Support"]];
		PSSpecifier *status = [PSSpecifier preferenceSpecifierNamed:@"Status" target:self set:nil get:@selector(supportValue:) detail:nil cell:PSTitleValueCell edit:nil];
		[status setProperty:listed ? @"Works" : @"No Icon" forKey:@"supportValue"];
		[specifiers addObject:status];
		PSSpecifier *versionRow = [PSSpecifier preferenceSpecifierNamed:@"Version" target:self set:nil get:@selector(supportValue:) detail:nil cell:PSTitleValueCell edit:nil];
		[versionRow setProperty:MZInstalledAppVersion(game[MZGameBundleIdentifierKey]) ?: @"?" forKey:@"supportValue"];
		[specifiers addObject:versionRow];
		if (!listed) {
			[specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
			PSSpecifier *request = [PSSpecifier preferenceSpecifierNamed:@"Request Icon on GitHub" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
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
	NSMutableArray *specifiers = [NSMutableArray arrayWithObject:[PSSpecifier groupSpecifierWithName:@"Activity"]];
	NSDictionary *rows = @{@"Project Name": MZSettingApelinProject, @"Agent Status": MZSettingApelinAgent};
	for (NSString *name in @[@"Project Name", @"Agent Status"]) {
		PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
		MZSetSetting(row, rows[name], @YES);
		[specifiers addObject:row];
	}

	return specifiers;
}

- (void)requestIcon:(PSSpecifier *)specifier {
	[UIApplication.sharedApplication openURL:MZAppRequestURL(self.game[MZGameBundleIdentifierKey]) options:@{} completionHandler:nil];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.title = self.game[MZGameNameKey];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	NSString *bundleIdentifier = self.game[MZGameBundleIdentifierKey];
	__weak typeof(self) weakSelf = self;
	[MZServiceProxy(nil) gamesWithReply:^(NSArray<NSDictionary *> *games) {
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			for (NSDictionary *game in games) {
				if (![game[MZGameBundleIdentifierKey] isEqualToString:bundleIdentifier] || [game isEqual:strongSelf.game]) continue;
				strongSelf->_game = game;
				[strongSelf reloadSpecifiers];
			}
		});
	}];
}

@end

@implementation MZMoreAppsListController {
	NSDictionary<NSString *, NSString *> *_icons;
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSArray<NSDictionary *> *providers = [self.specifier propertyForKey:@"providers"];
		NSMutableArray *specifiers = [NSMutableArray array];
		for (NSNumber *watching in @[@NO, @YES]) {
			NSMutableArray *rows = [NSMutableArray array];
			for (NSDictionary *provider in providers) {
				if ([provider[MZProviderWatchingKey] boolValue] != watching.boolValue) continue;
				PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:provider[MZProviderNameKey] target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
				[specifier setProperty:MZLogoCell.class forKey:@"cellClass"];
				[specifier setProperty:_icons[provider[MZProviderBundleIdentifierKey]] forKey:@"logo"];
				[rows addObject:specifier];
			}
			if (!rows.count) continue;
			[specifiers addObject:[PSSpecifier groupSpecifierWithName:watching.boolValue ? @"Watching" : @"Listening"]];
			[specifiers addObjectsFromArray:rows];
		}
		_specifiers = specifiers;
	}

	return _specifiers;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.title = @"More Supported Apps";
	__weak typeof(self) weakSelf = self;
	[MZServiceProxy(nil) appIconsWithReply:^(NSDictionary<NSString *, NSString *> *icons) {
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf || [icons isEqual:strongSelf->_icons]) return;
			strongSelf->_icons = icons;
			[strongSelf reloadSpecifiers];
		});
	}];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return MZLogoCellHeight;
}

@end
