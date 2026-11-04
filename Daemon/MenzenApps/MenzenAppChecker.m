#import <dlfcn.h>
#import <notify.h>
#import <signal.h>

#import "../../Shared/MenzenApps.h"
#import "MenzenAppChecker.h"

@interface FBSSystemService : NSObject
+ (instancetype)sharedService;
- (void)openApplication:(NSString *)bundleIdentifier options:(NSDictionary *)options withResult:(void (^)(NSError *error))result;
- (pid_t)pidForApplication:(NSString *)bundleIdentifier;
@end

// How long an app gets to save its check.
static NSTimeInterval const MenzenBackgroundTimeout = 30;
static NSTimeInterval const MenzenOpenTimeout = 120;
// After menzend starts, or apps change: let things settle first.
static NSTimeInterval const MenzenScanDelay = 15;
static NSTimeInterval const MenzenNextDelay = 2;

// Bundle ID to "<app version>|<Menzen version>" already launched in the
// background, so an app whose check never finishes isn't launched again on
// every start. The pane's button is for those.
static CFStringRef const MenzenCheckerDomain = CFSTR("moe.waru.menzend");
static CFStringRef const MenzenTriedKey = CFSTR("backgroundChecks");

static char const *const MenzenLockStateNotification = "com.apple.springboard.lockstate";
static CFStringRef const MenzenApplicationsChangedNotification = CFSTR("com.apple.LaunchServices.ApplicationsChanged");

static void *MenzenFrontBoardServices(void) {
	static void *handle;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		handle = dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY);
	});
	return handle;
}

static NSString *MenzenOptionKey(const char *symbol, NSString *fallback) {
	void *handle = MenzenFrontBoardServices();
	NSString *__unsafe_unretained *key = handle ? (NSString * __unsafe_unretained *)dlsym(handle, symbol) : NULL;
	return key && *key ? *key : fallback;
}

static FBSSystemService *MenzenSystemService(void) {
	MenzenFrontBoardServices();
	return [NSClassFromString(@"FBSSystemService") sharedService];
}

static NSString *MenzenTriedValue(NSString *version) {
	return [NSString stringWithFormat:@"%@|%@", version, @MENZEN_VERSION];
}

@implementation MenzenAppChecker {
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

static void MenzenChecked(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	NSString *bundleIdentifier = [(__bridge NSString *)name substringFromIndex:strlen(MenzenSupportCheckedNotificationPrefix)];
	MenzenAppChecker *checker = (__bridge MenzenAppChecker *)observer;
	dispatch_async(dispatch_get_main_queue(), ^{
		[checker appChecked:bundleIdentifier];
	});
}

static void MenzenApplicationsChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	MenzenAppChecker *checker = (__bridge MenzenAppChecker *)observer;
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
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, MenzenApplicationsChanged, MenzenApplicationsChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	__weak typeof(self) weakSelf = self;
	notify_register_dispatch(MenzenLockStateNotification, &_lockToken, dispatch_get_main_queue(), ^(int token) {
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
	NSString *name = [@MenzenSupportCheckedNotificationPrefix stringByAppendingString:bundleIdentifier];
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, MenzenChecked, (__bridge CFStringRef)name, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (NSDictionary<NSString *, NSString *> *)tried {
	CFPreferencesAppSynchronize(MenzenCheckerDomain);
	NSDictionary *tried = CFBridgingRelease(CFPreferencesCopyAppValue(MenzenTriedKey, MenzenCheckerDomain));
	return [tried isKindOfClass:NSDictionary.class] ? tried : @{};
}

- (void)setTried:(NSString *)bundleIdentifier version:(NSString *)version {
	NSMutableDictionary *tried = [self.tried mutableCopy];
	tried[bundleIdentifier] = MenzenTriedValue(version);
	CFPreferencesSetAppValue(MenzenTriedKey, (__bridge CFDictionaryRef)tried, MenzenCheckerDomain);
	CFPreferencesAppSynchronize(MenzenCheckerDomain);
}

- (void)scheduleScan {
	if (_scanScheduled) return;
	_scanScheduled = YES;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MenzenScanDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		self->_scanScheduled = NO;
		[self scan];
	});
}

// Apps with a provider, installed, without a check of this version by this
// Menzen, and not launched for it before.
- (void)scan {
	NSDictionary *tried = self.tried;
	for (NSString *bundleIdentifier in [MenzenHookedBundles().allObjects sortedArrayUsingSelector:@selector(compare:)]) {
		[self observe:bundleIdentifier];
		NSString *version = MenzenInstalledAppVersion(bundleIdentifier);
		if (!version || MenzenStatusIsCurrent(MenzenAppSupportStatus(bundleIdentifier), version)) continue;
		if ([tried[bundleIdentifier] isEqual:MenzenTriedValue(version)]) continue;
		if ([bundleIdentifier isEqual:_current] || [_queue containsObject:bundleIdentifier]) continue;
		[_queue addObject:bundleIdentifier];
	}

	[self checkNext];
}

- (void)checkNext {
	if (_current || !_queue.count || self.locked) return;
	NSString *bundleIdentifier = _queue.firstObject;
	[_queue removeObjectAtIndex:0];
	NSString *version = MenzenInstalledAppVersion(bundleIdentifier);
	FBSSystemService *service = MenzenSystemService();
	// Gone, already checked, or running: it checks itself when it's opened.
	if (!version || MenzenStatusIsCurrent(MenzenAppSupportStatus(bundleIdentifier), version) || !service || [service pidForApplication:bundleIdentifier] > 0) {
		[self checkNext];
		return;
	}

	_current = bundleIdentifier;
	_currentPid = 0;
	NSUInteger generation = ++_generation;
	[self setTried:bundleIdentifier version:version];
	NSDictionary *options = @{MenzenOptionKey("FBSOpenApplicationOptionKeyActivateSuspended", @"__ActivateSuspended"): @YES};
	[service openApplication:bundleIdentifier options:options withResult:^(NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (generation != self->_generation) return;
			if (error) {
				[self finishCurrent];
				return;
			}
			self->_currentPid = [service pidForApplication:bundleIdentifier];
		});
	}];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MenzenBackgroundTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (generation != self->_generation) return;
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
	NSDictionary *status = MenzenAppSupportStatus(bundleIdentifier);
	BOOL opened = status && ![status[MenzenSupportBackgroundKey] boolValue];
	if (pid > 0 && !opened && ![bundleIdentifier isEqual:_opened] && [MenzenSystemService() pidForApplication:bundleIdentifier] == pid) kill(pid, SIGKILL);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MenzenNextDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self checkNext];
	});
}

- (void)appChecked:(NSString *)bundleIdentifier {
	if ([bundleIdentifier isEqual:_current]) [self finishCurrent];
	// Only the check made with the app open: one made in the background
	// just before doesn't count.
	if ([bundleIdentifier isEqual:_opened] && ![MenzenAppSupportStatus(bundleIdentifier)[MenzenSupportBackgroundKey] boolValue]) {
		NSString *returnTo = _returnTo;
		_opened = nil;
		_returnTo = nil;
		[MenzenSystemService() openApplication:returnTo options:@{} withResult:^(NSError *error){}];
	}
}

- (void)openAppToCheck:(NSString *)bundleIdentifier returningTo:(NSString *)returnBundleIdentifier {
	if (![MenzenHookedBundles() containsObject:bundleIdentifier]) return;
	[self observe:bundleIdentifier];
	_opened = bundleIdentifier;
	_returnTo = returnBundleIdentifier;
	NSDictionary *options = @{MenzenOptionKey("FBSOpenApplicationOptionKeyUnlockDevice", @"__UnlockDevice"): @YES};
	[MenzenSystemService() openApplication:bundleIdentifier options:options withResult:^(NSError *error){}];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MenzenOpenTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (![self->_opened isEqual:bundleIdentifier]) return;
		self->_opened = nil;
		self->_returnTo = nil;
	});
}

@end
