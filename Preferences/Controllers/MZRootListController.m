#import <AuthenticationServices/AuthenticationServices.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSListItemsController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <UIKit/UIKit.h>

#import "../../Shared/MZCustomActivity.h"
#import "../../Shared/MZSettings.h"
#import "../Helpers/MZServiceClient.h"
#import "../Views/MZDestructiveButtonCell.h"
#import "../Views/MZProfileCell.h"
#import "MZOtherDeviceSignIn.h"

// The pane never sees a token: menzend hands it an authorize URL, the web
// sign-in hands back a redirect, and the pane passes it straight to menzend.

// The pane's lists have no separators.
@interface MZListItemsController : PSListItemsController
@end

@implementation MZListItemsController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
}

@end

@interface MZRootListController : PSListController <ASWebAuthenticationPresentationContextProviding>
@end

static PSSpecifier *MZSpecifier(NSArray<PSSpecifier *> *specifiers, NSString *identifier) {
	for (PSSpecifier *specifier in specifiers) {
		if ([specifier.identifier isEqualToString:identifier]) return specifier;
	}

	return nil;
}

@implementation MZRootListController {
	ASWebAuthenticationSession *_session;
	// nil until menzend answers, or when it can't be reached.
	NSDictionary<NSString *, id> *_status;
	BOOL _unreachable;
	BOOL _busy;
	// The last sign-in problem, shown until the next attempt.
	NSString *_message;
	UIRefreshControl *_refreshControl;
}

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
		if (!_status && !_unreachable) {
			// Not knowing yet, rather than flashing the sign-in.
			specifiers = [NSMutableArray array];
		} else if (!self.signedIn) {
			// Nothing to set up without an account.
			NSArray *identifiers = @[@"account", @"accountButton", @"otherDevice", @"otherDeviceButton"];
			NSMutableArray *signInSpecifiers = [NSMutableArray array];
			for (NSString *identifier in identifiers) [signInSpecifiers addObject:MZSpecifier(specifiers, identifier)];
			specifiers = signInSpecifiers;
		} else {
			[specifiers removeObject:MZSpecifier(specifiers, @"otherDevice")];
			[specifiers removeObject:MZSpecifier(specifiers, @"otherDeviceButton")];
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
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshStatus) name:MZStatusDidChangeNotification object:nil];
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
	[_session cancel];
}

- (id<MZService>)service {
	__weak typeof(self) weakSelf = self;
	return MZServiceProxy(^{
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
			[strongSelf reloadSpecifiers];
		});
	}];
}

- (BOOL)signedIn {
	return [_status[MZStatusSignedInKey] boolValue];
}

- (NSDictionary<NSString *, id> *)profile {
	NSDictionary *profile = _status[MZStatusProfileKey];
	if ([profile isKindOfClass:NSDictionary.class]) return profile;
	NSString *username = _status[MZStatusUsernameKey];
	return username ? @{MZProfileUsernameKey: username} : @{};
}

- (NSString *)unreachableMessage {
	return @"Menzen's background service isn't running. Try reinstalling Menzen.";
}

- (NSString *)accountFooter {
	if (_message) return _message;
	if (self.signedIn) return [self.profile[MZProfileLimitedKey] boolValue] ? @"Sign out and back in to show your badges, banner and Nitro." : nil;
	if (_unreachable) return self.unreachableMessage;
	if (!_status) return nil;
	return _status[MZStatusErrorKey] ?: @"If the page doesn't load, sign in on another device.";
}

- (NSArray<PSSpecifier *> *)profileSpecifiers {
	PSSpecifier *header = [PSSpecifier preferenceSpecifierNamed:nil target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
	header.identifier = @"profile";
	[header setProperty:MZProfileCell.class forKey:@"cellClass"];
	[header setProperty:self.profile forKey:@"profile"];
	NSDictionary *activity = _status[MZStatusActivityKey];
	if ([activity isKindOfClass:NSDictionary.class]) [header setProperty:activity forKey:@"activity"];

	// Problems cover the profile, since it can't be trusted then.
	NSString *error = _status[MZStatusErrorKey];
	if (_unreachable) {
		[header setProperty:self.unreachableMessage forKey:@"overlay"];
	} else if (error) {
		[header setProperty:error forKey:@"overlay"];
	} else if (![_status[MZStatusConnectedKey] boolValue]) {
		[header setProperty:@"Connecting to Discord…" forKey:@"overlay"];
		[header setProperty:@YES forKey:@"overlayBusy"];
	}

	PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
	[group setProperty:@"Pull down to refresh." forKey:@"footerText"];
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
	[MZSpecifier(specifiers, @"account") setProperty:self.accountFooter forKey:@"footerText"];

	PSSpecifier *button = MZSpecifier(specifiers, @"accountButton");
	if (_busy) {
		button.name = @"Signing In…";
	} else {
		button.name = self.signedIn ? @"Sign Out" : @"Sign In with Discord";
	}

	BOOL enabled = !_busy && !_unreachable && _status;
	[button setProperty:@(enabled) forKey:@"enabled"];
	if (self.signedIn && !_busy) [button setProperty:MZDestructiveButtonCell.class forKey:@"cellClass"];
	[MZSpecifier(specifiers, @"otherDeviceButton") setProperty:@(enabled) forKey:@"enabled"];

	[MZSpecifier(specifiers, @"resetButton") setProperty:MZDestructiveButtonCell.class forKey:@"cellClass"];
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
				[strongSelf finishWithMessage:@"Menzen couldn't start the sign-in. Try again."];
			}
		});
	}];
}

- (void)otherDeviceButtonTapped {
	if (_busy || self.signedIn) return;
	_busy = YES;
	_message = nil;
	[self reloadSpecifiers];

	MZOtherDeviceSignInController *controller = [MZOtherDeviceSignInController new];
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
	_session = [[ASWebAuthenticationSession alloc] initWithURL:authorizeURL callbackURLScheme:MZCallbackScheme() completionHandler:^(NSURL *callbackURL, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf->_session = nil;
			if (!callbackURL) {
				BOOL cancelled = [error.domain isEqualToString:ASWebAuthenticationSessionErrorDomain] && error.code == ASWebAuthenticationSessionErrorCodeCanceledLogin;
				[strongSelf finishWithMessage:cancelled ? nil : @"The sign-in page couldn't be opened. Try again."];
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
		[self finishWithMessage:@"The sign-in page couldn't be opened. Try again."];
	}
}

- (void)finishWithMessage:(NSString *)message {
	_busy = NO;
	_message = message;
	[self reloadSpecifiers];
	[self refreshStatus];
}

- (void)confirmSignOut {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sign Out of Discord?" message:@"Menzen will stop showing what you're playing." preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"Sign Out" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
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
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset Settings?" message:@"Every setting goes back to its default. You stay signed in, and your custom activity presets are kept." preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[weakSelf resetSettings];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)resetSettings {
	CFStringRef domain = (__bridge CFStringRef)MZSettingsDomain;
	NSMutableArray *keys = [CFBridgingRelease(CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)) mutableCopy];
	[keys removeObject:MZSettingCustomPresets];
	if (keys.count) CFPreferencesSetMultiple(NULL, (__bridge CFArrayRef)keys, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(MZSettingsChangedNotification), NULL, NULL, YES);
	[self reloadSpecifiers];
}

- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
	return self.view.window;
}

@end
