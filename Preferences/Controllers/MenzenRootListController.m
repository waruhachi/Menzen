#import <AuthenticationServices/AuthenticationServices.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSListItemsController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <UIKit/UIKit.h>

#import "../../Shared/MenzenCustomActivity.h"
#import "../../Shared/MenzenLocalization/MenzenLocalization.h"
#import "../../Shared/MenzenSettings.h"
#import "../Helpers/MenzenLocalizeSpecifiers.h"
#import "../Helpers/MenzenServiceClient.h"
#import "../Views/MenzenDestructiveButtonCell.h"
#import "../Views/MenzenProfileCell.h"
#import "MenzenOtherDeviceSignIn.h"

// The pane never sees a token: menzend hands it an authorize URL, the web
// sign-in hands back a redirect, and the pane passes it straight to menzend.

// Connecting normally takes a few seconds. Much longer usually means the
// sign-in stopped working without Discord saying so, and signing in again
// fixes it.
static NSTimeInterval const MenzenConnectTimeout = 30;

// The pane's lists have no separators.
@interface MenzenListItemsController : PSListItemsController
@end

@implementation MenzenListItemsController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
}

@end

@interface MenzenRootListController : PSListController <ASWebAuthenticationPresentationContextProviding>
- (void)settingsChanged;
@end

static PSSpecifier *MenzenSpecifier(NSArray<PSSpecifier *> *specifiers, NSString *identifier) {
	for (PSSpecifier *specifier in specifiers) {
		if ([specifier.identifier isEqualToString:identifier]) return specifier;
	}

	return nil;
}

// Darwin notifications arrive on the main run loop, where the pane observes.
static void MenzenRootSettingsChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	[(__bridge MenzenRootListController *)observer settingsChanged];
}

@implementation MenzenRootListController {
	ASWebAuthenticationSession *_session;
	// nil until menzend answers, or when it can't be reached.
	NSDictionary<NSString *, id> *_status;
	BOOL _unreachable;
	BOOL _busy;
	// The last sign-in problem, shown until the next attempt.
	NSString *_message;
	UIRefreshControl *_refreshControl;
	// When the pane first saw menzend connecting, used until menzend says
	// since when (it only does once it has started connecting).
	NSDate *_connectingSeen;
	NSTimer *_connectTimer;
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
		MenzenLocalizeSpecifiers(specifiers);
		if (!_status && !_unreachable) {
			// Not knowing yet, rather than flashing the sign-in.
			specifiers = [NSMutableArray array];
		} else if (!self.signedIn) {
			// Nothing to set up without an account.
			NSArray *identifiers = @[@"account", @"accountButton", @"otherDevice", @"otherDeviceButton"];
			NSMutableArray *signInSpecifiers = [NSMutableArray array];
			for (NSString *identifier in identifiers) [signInSpecifiers addObject:MenzenSpecifier(specifiers, identifier)];
			specifiers = signInSpecifiers;
		} else {
			[specifiers removeObject:MenzenSpecifier(specifiers, @"otherDevice")];
			[specifiers removeObject:MenzenSpecifier(specifiers, @"otherDeviceButton")];
			NSArray *profileSpecifiers = self.profileSpecifiers;
			[specifiers insertObjects:profileSpecifiers atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, profileSpecifiers.count)]];
		}
		[self applyStatusToSpecifiers:specifiers];
		_specifiers = specifiers;
	}

	return _specifiers;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshStatus) name:MenzenStatusDidChangeNotification object:nil];
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, MenzenRootSettingsChanged, CFSTR(MenzenSettingsChangedNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	[self refreshStatus];

	_refreshControl = [UIRefreshControl new];
	[_refreshControl addTarget:self action:@selector(pulledToRefresh) forControlEvents:UIControlEventValueChanged];
	self.table.refreshControl = _refreshControl;
}

- (void)pulledToRefresh {
	__weak typeof(self) weakSelf = self;
	[self.service refreshWithReply:^{
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			[strongSelf->_refreshControl endRefreshing];
			[strongSelf refreshStatus];
		});
	}];
}

- (void)dealloc {
	CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, CFSTR(MenzenSettingsChangedNotification), NULL);
	[_session cancel];
	[_connectTimer invalidate];
}

// The Control Center modules change these switches' settings from SpringBoard.
- (void)settingsChanged {
	CFPreferencesAppSynchronize((__bridge CFStringRef)MenzenSettingsDomain);
	[self reloadSpecifierID:@"enabled" animated:NO];
	[self reloadSpecifierID:@"privacy" animated:NO];
}

- (id<MenzenService>)service {
	__weak typeof(self) weakSelf = self;
	return MenzenServiceProxy(^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf->_unreachable = YES;
		strongSelf->_busy = NO;
		[strongSelf->_refreshControl endRefreshing];
		[strongSelf reloadSpecifiers];
	});
}

- (void)refreshStatus {
	__weak typeof(self) weakSelf = self;
	[self.service statusWithReply:^(NSDictionary<NSString *, id> *status) {
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf->_status = status;
			strongSelf->_unreachable = NO;
			[strongSelf scheduleConnectTimeout];
			[strongSelf reloadSpecifiers];
		});
	}];
}

- (BOOL)signedIn {
	return [_status[MenzenStatusSignedInKey] boolValue];
}

- (NSDictionary<NSString *, id> *)profile {
	NSDictionary *profile = _status[MenzenStatusProfileKey];
	if ([profile isKindOfClass:NSDictionary.class]) return profile;
	NSString *username = _status[MenzenStatusUsernameKey];
	return username ? @{MenzenProfileUsernameKey: username} : @{};
}

- (BOOL)connecting {
	return self.signedIn && !_unreachable && !_status[MenzenStatusErrorKey] && ![_status[MenzenStatusConnectedKey] boolValue];
}

- (NSTimeInterval)connectingTime {
	NSNumber *since = _status[MenzenStatusConnectingSinceKey];
	NSDate *start = [since isKindOfClass:NSNumber.class] ? [NSDate dateWithTimeIntervalSince1970:since.doubleValue] : _connectingSeen;
	return start ? MAX(-start.timeIntervalSinceNow, 0) : 0;
}

// Reloads once connecting has taken too long, to swap the spinner for a hint.
- (void)scheduleConnectTimeout {
	[_connectTimer invalidate];
	_connectTimer = nil;
	if (!self.connecting) {
		_connectingSeen = nil;
		return;
	}

	if (!_connectingSeen) _connectingSeen = NSDate.date;
	NSTimeInterval remaining = MenzenConnectTimeout - self.connectingTime;
	if (remaining <= 0) return;
	__weak typeof(self) weakSelf = self;
	_connectTimer = [NSTimer scheduledTimerWithTimeInterval:remaining repeats:NO block:^(NSTimer *timer) {
		[weakSelf reloadSpecifiers];
	}];
}

- (NSString *)unreachableMessage {
	return MenzenLocalizedString(@"root.menzen_s_background_service_isn_t", @"Menzen's background service isn't running. Try reinstalling Menzen.");
}

- (NSString *)accountFooter {
	if (_message) return _message;
	if (self.signedIn) return [self.profile[MenzenProfileLimitedKey] boolValue] ? MenzenLocalizedString(@"root.sign_out_and_back_in_to", @"Sign out and back in to show your badges, banner and Nitro.") : nil;
	if (_unreachable) return self.unreachableMessage;
	if (!_status) return nil;
	return _status[MenzenStatusErrorKey] ?: MenzenLocalizedString(@"root.if_the_page_doesn_t_load", @"If the page doesn't load, sign in on another device.");
}

- (NSArray<PSSpecifier *> *)profileSpecifiers {
	PSSpecifier *header = [PSSpecifier preferenceSpecifierNamed:nil target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
	header.identifier = @"profile";
	[header setProperty:MenzenProfileCell.class forKey:@"cellClass"];
	[header setProperty:self.profile forKey:@"profile"];
	NSDictionary *activity = _status[MenzenStatusActivityKey];
	if ([activity isKindOfClass:NSDictionary.class]) [header setProperty:activity forKey:@"activity"];

	// Problems cover the profile, since it can't be trusted then.
	NSString *error = _status[MenzenStatusErrorKey];
	if (_unreachable) {
		[header setProperty:self.unreachableMessage forKey:@"overlay"];
	} else if (error) {
		[header setProperty:error forKey:@"overlay"];
	} else if (self.connecting && self.connectingTime >= MenzenConnectTimeout) {
		[header setProperty:MenzenLocalizedString(@"root.discord_isn_t_connecting_sign_out", @"Discord isn't connecting. If you're online, sign out and sign in again.") forKey:@"overlay"];
	} else if (self.connecting) {
		[header setProperty:MenzenLocalizedString(@"root.connecting_to_discord", @"Connecting to Discord…") forKey:@"overlay"];
		[header setProperty:@YES forKey:@"overlayBusy"];
	}

	PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
	[group setProperty:MenzenLocalizedString(@"root.pull_down_to_refresh", @"Pull down to refresh.") forKey:@"footerText"];
	return @[group, header];
}

- (BOOL)isSelfSizingRowAtIndexPath:(NSIndexPath *)indexPath {
	return [[self specifierAtIndexPath:indexPath].identifier isEqualToString:@"profile"];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([self isSelfSizingRowAtIndexPath:indexPath]) return UITableViewAutomaticDimension;
	return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([self isSelfSizingRowAtIndexPath:indexPath]) return 400;
	return [super tableView:tableView estimatedHeightForRowAtIndexPath:indexPath];
}

- (void)applyStatusToSpecifiers:(NSArray<PSSpecifier *> *)specifiers {
	[MenzenSpecifier(specifiers, @"account") setProperty:self.accountFooter forKey:@"footerText"];

	PSSpecifier *button = MenzenSpecifier(specifiers, @"accountButton");
	if (_busy) {
		button.name = MenzenLocalizedString(@"root.signing_in", @"Signing In…");
	} else {
		button.name = self.signedIn ? MenzenLocalizedString(@"root.sign_out", @"Sign Out") : MenzenLocalizedString(@"root.sign_in_with_discord", @"Sign In with Discord");
	}

	BOOL enabled = !_busy && !_unreachable && _status;
	[button setProperty:@(enabled) forKey:@"enabled"];
	if (self.signedIn && !_busy) [button setProperty:MenzenDestructiveButtonCell.class forKey:@"cellClass"];
	[MenzenSpecifier(specifiers, @"otherDeviceButton") setProperty:@(enabled) forKey:@"enabled"];

	[MenzenSpecifier(specifiers, @"resetButton") setProperty:MenzenDestructiveButtonCell.class forKey:@"cellClass"];
}

- (void)accountButtonTapped {
	if (_busy) return;
	if (self.signedIn) {
		[self confirmSignOut];
	} else {
		[self signIn];
	}
}

- (void)signIn {
	_busy = YES;
	_message = nil;
	[self reloadSpecifiers];

	__weak typeof(self) weakSelf = self;
	[self.service beginSignInWithReply:^(NSURL *authorizeURL) {
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			if (authorizeURL) {
				[strongSelf presentSignInWithURL:authorizeURL];
			} else {
				[strongSelf finishWithMessage:MenzenLocalizedString(@"common.menzen_couldn_t_start_the_sign", @"Menzen couldn't start the sign-in. Try again.")];
			}
		});
	}];
}

- (void)otherDeviceButtonTapped {
	if (_busy || self.signedIn) return;
	_busy = YES;
	_message = nil;
	[self reloadSpecifiers];

	MenzenOtherDeviceSignInController *controller = [MenzenOtherDeviceSignInController new];
	__weak typeof(self) weakSelf = self;
	controller.completion = ^{
		[weakSelf finishWithMessage:nil];
	};
	UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
	navigation.modalPresentationStyle = UIModalPresentationFormSheet;
	[self presentViewController:navigation animated:YES completion:nil];
}

- (void)presentSignInWithURL:(NSURL *)authorizeURL {
	__weak typeof(self) weakSelf = self;
	_session = [[ASWebAuthenticationSession alloc] initWithURL:authorizeURL callbackURLScheme:MenzenCallbackScheme() completionHandler:^(NSURL *callbackURL, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf->_session = nil;
			if (!callbackURL) {
				BOOL cancelled = [error.domain isEqualToString:ASWebAuthenticationSessionErrorDomain] && error.code == ASWebAuthenticationSessionErrorCodeCanceledLogin;
				[strongSelf finishWithMessage:cancelled ? nil : MenzenLocalizedString(@"root.the_sign_in_page_couldn_t", @"The sign-in page couldn't be opened. Try again.")];
				return;
			}
			[strongSelf.service finishSignInWithCallbackURL:callbackURL reply:^(NSString *message) {
				dispatch_async(dispatch_get_main_queue(), ^{
					[weakSelf finishWithMessage:message];
				});
			}];
		});
	}];
	_session.presentationContextProvider = self;
	// Share Safari's cookies, so someone signed in to Discord there only has
	// to approve.
	_session.prefersEphemeralWebBrowserSession = NO;
	if (![_session start]) {
		_session = nil;
		[self finishWithMessage:MenzenLocalizedString(@"root.the_sign_in_page_couldn_t", @"The sign-in page couldn't be opened. Try again.")];
	}
}

- (void)finishWithMessage:(NSString *)message {
	_busy = NO;
	_message = message;
	[self reloadSpecifiers];
	[self refreshStatus];
}

- (void)confirmSignOut {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:MenzenLocalizedString(@"root.sign_out_of_discord", @"Sign Out of Discord?") message:MenzenLocalizedString(@"root.menzen_will_stop_showing_what_you", @"Menzen will stop showing what you're playing.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:MenzenLocalizedString(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:MenzenLocalizedString(@"root.sign_out", @"Sign Out") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[weakSelf.service signOutWithReply:^{
			dispatch_async(dispatch_get_main_queue(), ^{
				[weakSelf finishWithMessage:nil];
			});
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

// Every setting goes back to its default. The account isn't a setting: its
// tokens are in menzend's keychain, so this keeps Menzen signed in. The
// custom activity presets are the user's own writing, so they stay too.
- (void)confirmReset {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:MenzenLocalizedString(@"root.reset_settings", @"Reset Settings?") message:MenzenLocalizedString(@"root.every_setting_goes_back_to_its", @"Every setting goes back to its default. You stay signed in, and your custom activity presets are kept.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:MenzenLocalizedString(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:MenzenLocalizedString(@"root.reset", @"Reset") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[weakSelf resetSettings];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)resetSettings {
	CFStringRef domain = (__bridge CFStringRef)MenzenSettingsDomain;
	NSMutableArray *keys = [CFBridgingRelease(CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)) mutableCopy];
	[keys removeObject:MenzenSettingCustomPresets];
	if (keys.count) CFPreferencesSetMultiple(NULL, (__bridge CFArrayRef)keys, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(MenzenSettingsChangedNotification), NULL, NULL, YES);
	[self reloadSpecifiers];
}

- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
	return self.view.window;
}

@end
