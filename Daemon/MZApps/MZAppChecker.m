#import <dlfcn.h>
#import <notify.h>
#import <signal.h>

#import "../../Shared/MZApps.h"
#import "../MZLog/MZLog.h"
#import "MZAppChecker.h"

@interface FBSSystemService : NSObject
+ (instancetype)sharedService;
- (void)openApplication:(NSString *)bundleIdentifier options:(NSDictionary *)options withResult:(void (^)(NSError *error))result;
- (pid_t)pidForApplication:(NSString *)bundleIdentifier;
@end

// How long an app gets to save its check.
static NSTimeInterval const MZBackgroundTimeout = 30;
static NSTimeInterval const MZOpenTimeout = 120;
// After menzend starts, or apps change: let things settle first.
static NSTimeInterval const MZScanDelay = 15;
static NSTimeInterval const MZNextDelay = 2;

// Bundle ID to "<app version>|<Menzen version>" already launched in the
// background, so an app whose check never finishes isn't launched again on
// every start. The pane's button is for those.
static CFStringRef const MZCheckerDomain = CFSTR("moe.waru.menzend");
static CFStringRef const MZTriedKey = CFSTR("backgroundChecks");

static char const *const MZLockStateNotification = "com.apple.springboard.lockstate";
static CFStringRef const MZApplicationsChangedNotification = CFSTR("com.apple.LaunchServices.ApplicationsChanged");

static void *MZFrontBoardServices(void) {
	static void *handle;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		handle = dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY);
	});
	return handle;
}

static NSString *MZOptionKey(const char *symbol, NSString *fallback) {
	void *handle = MZFrontBoardServices();
	NSString *__unsafe_unretained *key = handle ? (NSString * __unsafe_unretained *)dlsym(handle, symbol) : NULL;
	return key && *key ? *key : fallback;
}

static FBSSystemService *MZSystemService(void) {
	MZFrontBoardServices();
	return [NSClassFromString(@"FBSSystemService") sharedService];
}

static NSString *MZTriedValue(NSString *version) {
	return [NSString stringWithFormat:@"%@|%@", version, @MZ_VERSION];
}

@implementation MZAppChecker {
	NSMutableArray<NSString *> *_queue;
	NSMutableSet<NSString *> *_observed;
	BOOL _scanScheduled;
	int _lockToken;
	NSString *_current;
	pid_t _currentPid;
	NSUInteger _generation;
	NSString *_opened;
	NSString *_returnTo;
}

static void MZChecked(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	NSString *bundleIdentifier = [(__bridge NSString *)name substringFromIndex:strlen(MZSupportCheckedNotificationPrefix)];
	MZAppChecker *checker = (__bridge MZAppChecker *)observer;
	dispatch_async(dispatch_get_main_queue(), ^{
		[checker appChecked:bundleIdentifier];
	});
}

static void MZApplicationsChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	MZAppChecker *checker = (__bridge MZAppChecker *)observer;
	dispatch_async(dispatch_get_main_queue(), ^{
		[checker scheduleScan];
	});
}

- (instancetype)init {
	if ((self = [super init])) {
		_queue = [NSMutableArray array];
		_observed = [NSMutableSet set];
		_lockToken = NOTIFY_TOKEN_INVALID;
	}

	return self;
}

- (void)start {
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, MZApplicationsChanged, MZApplicationsChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	__weak typeof(self) weakSelf = self;
	notify_register_dispatch(MZLockStateNotification, &_lockToken, dispatch_get_main_queue(), ^(int token) {
		if (![weakSelf locked]) [weakSelf checkNext];
	});
	[self scheduleScan];
}

- (BOOL)locked {
	uint64_t state = 0;
	if (_lockToken == NOTIFY_TOKEN_INVALID || notify_get_state(_lockToken, &state) != NOTIFY_STATUS_OK) return NO;
	return state != 0;
}

- (void)observe:(NSString *)bundleIdentifier {
	if ([_observed containsObject:bundleIdentifier]) return;
	[_observed addObject:bundleIdentifier];
	NSString *name = [@MZSupportCheckedNotificationPrefix stringByAppendingString:bundleIdentifier];
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, MZChecked, (__bridge CFStringRef)name, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (NSDictionary<NSString *, NSString *> *)tried {
	CFPreferencesAppSynchronize(MZCheckerDomain);
	NSDictionary *tried = CFBridgingRelease(CFPreferencesCopyAppValue(MZTriedKey, MZCheckerDomain));
	return [tried isKindOfClass:NSDictionary.class] ? tried : @{};
}

- (void)setTried:(NSString *)bundleIdentifier version:(NSString *)version {
	NSMutableDictionary *tried = [self.tried mutableCopy];
	tried[bundleIdentifier] = MZTriedValue(version);
	CFPreferencesSetAppValue(MZTriedKey, (__bridge CFDictionaryRef)tried, MZCheckerDomain);
	CFPreferencesAppSynchronize(MZCheckerDomain);
}

- (void)scheduleScan {
	if (_scanScheduled) return;
	_scanScheduled = YES;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MZScanDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		self->_scanScheduled = NO;
		[self scan];
	});
}

// Apps with a provider, installed, without a check of this version by this
// Menzen, and not launched for it before.
- (void)scan {
	NSDictionary *tried = self.tried;
	for (NSString *bundleIdentifier in [MZHookedBundles().allObjects sortedArrayUsingSelector:@selector(compare:)]) {
		[self observe:bundleIdentifier];
		NSString *version = MZInstalledAppVersion(bundleIdentifier);
		if (!version || MZStatusIsCurrent(MZAppSupportStatus(bundleIdentifier), version)) continue;
		if ([tried[bundleIdentifier] isEqual:MZTriedValue(version)]) continue;
		if ([bundleIdentifier isEqual:_current] || [_queue containsObject:bundleIdentifier]) continue;
		[_queue addObject:bundleIdentifier];
	}

	if (_queue.count) MZLog(@"apps to check: %@", [_queue componentsJoinedByString:@", "]);
	[self checkNext];
}

- (void)checkNext {
	if (_current || !_queue.count || self.locked) return;
	NSString *bundleIdentifier = _queue.firstObject;
	[_queue removeObjectAtIndex:0];
	NSString *version = MZInstalledAppVersion(bundleIdentifier);
	FBSSystemService *service = MZSystemService();
	// Gone, already checked, or running: it checks itself when it's opened.
	if (!version || MZStatusIsCurrent(MZAppSupportStatus(bundleIdentifier), version) || !service || [service pidForApplication:bundleIdentifier] > 0) {
		[self checkNext];
		return;
	}

	_current = bundleIdentifier;
	_currentPid = 0;
	NSUInteger generation = ++_generation;
	[self setTried:bundleIdentifier version:version];
	MZLog(@"checking %@ %@ in the background", bundleIdentifier, version);
	NSDictionary *options = @{MZOptionKey("FBSOpenApplicationOptionKeyActivateSuspended", @"__ActivateSuspended"): @YES};
	[service openApplication:bundleIdentifier options:options withResult:^(NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (generation != self->_generation) return;
			if (error) {
				MZLog(@"could not launch %@: %@", bundleIdentifier, error.localizedDescription);
				[self finishCurrent];
				return;
			}
			self->_currentPid = [service pidForApplication:bundleIdentifier];
		});
	}];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MZBackgroundTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (generation != self->_generation) return;
		MZLog(@"%@ didn't check in time", bundleIdentifier);
		[self finishCurrent];
	});
}

// Closes the app if menzend launched it and it's still in the background,
// then moves on.
- (void)finishCurrent {
	NSString *bundleIdentifier = _current;
	pid_t pid = _currentPid;
	_current = nil;
	_currentPid = 0;
	_generation++;
	NSDictionary *status = MZAppSupportStatus(bundleIdentifier);
	BOOL opened = status && ![status[MZSupportBackgroundKey] boolValue];
	if (pid > 0 && !opened && ![bundleIdentifier isEqual:_opened] && [MZSystemService() pidForApplication:bundleIdentifier] == pid) kill(pid, SIGKILL);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MZNextDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self checkNext];
	});
}

- (void)appChecked:(NSString *)bundleIdentifier {
	MZLog(@"%@ saved its check", bundleIdentifier);
	if ([bundleIdentifier isEqual:_current]) [self finishCurrent];
	// Only the check made with the app open: one made in the background
	// just before doesn't count.
	if ([bundleIdentifier isEqual:_opened] && ![MZAppSupportStatus(bundleIdentifier)[MZSupportBackgroundKey] boolValue]) {
		NSString *returnTo = _returnTo;
		_opened = nil;
		_returnTo = nil;
		[MZSystemService() openApplication:returnTo options:@{} withResult:^(NSError *error) {
			if (error) MZLog(@"could not go back to %@: %@", returnTo, error.localizedDescription);
		}];
	}
}

- (void)openAppToCheck:(NSString *)bundleIdentifier returningTo:(NSString *)returnBundleIdentifier {
	if (![MZHookedBundles() containsObject:bundleIdentifier]) return;
	[self observe:bundleIdentifier];
	_opened = bundleIdentifier;
	_returnTo = returnBundleIdentifier;
	MZLog(@"opening %@ to check, then back to %@", bundleIdentifier, returnBundleIdentifier);
	NSDictionary *options = @{MZOptionKey("FBSOpenApplicationOptionKeyUnlockDevice", @"__UnlockDevice"): @YES};
	[MZSystemService() openApplication:bundleIdentifier options:options withResult:^(NSError *error) {
		if (error) MZLog(@"could not open %@: %@", bundleIdentifier, error.localizedDescription);
	}];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MZOpenTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (![self->_opened isEqual:bundleIdentifier]) return;
		self->_opened = nil;
		self->_returnTo = nil;
	});
}

@end
