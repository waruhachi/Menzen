#import "../../Shared/MenzenApelin.h"
#import "../../Shared/MenzenApps.h"
#import "../../Shared/MenzenProviders.h"
#import "MenzenAppCatalog.h"
#import "MenzenAppInfo.h"

static NSString *const MenzenCatalogURL = @"https://raw.githubusercontent.com/waruhachi/Menzen/catalog/";
// What counts as a game; the other files only add icons.
static NSString *const MenzenGamesFile = @"games.json";
// The lists change about once a day.
static NSTimeInterval const MenzenCheckInterval = 6 * 60 * 60;
static NSTimeInterval const MenzenRetryInterval = 30 * 60;
// After menzend starts: let the network come up first.
static NSTimeInterval const MenzenFirstCheckDelay = 20;
// GitHub caches the file for 5 minutes anyway.
static NSTimeInterval const MenzenStaleAge = 10 * 60;

static CFStringRef const MenzenDaemonDomain = CFSTR("moe.waru.menzend");
// Before the catalog had a file per kind of app.
static CFStringRef const MenzenOldETagKey = CFSTR("gameCatalogETag");
static CFStringRef const MenzenApplicationsChangedNotification = CFSTR("com.apple.LaunchServices.ApplicationsChanged");

// Only links to Apple's artwork servers are sent to Discord, whatever the
// list says.
static BOOL MenzenIsIconURL(id value) {
	if (![value isKindOfClass:NSString.class]) return NO;
	NSURL *url = [NSURL URLWithString:value];
	NSString *host = url.host.lowercaseString;
	return [url.scheme isEqualToString:@"https"] && [host hasPrefix:@"is"] && [host hasSuffix:@"-ssl.mzstatic.com"] && [url.path hasPrefix:@"/image/thumb/"];
}

// Apps Menzen knows itself, bundle ID to the key of their art asset on the
// Discord application. They're installed by jailbreak packages, so they're
// System apps that aren't in the list or the home screen scan.
static NSDictionary<NSString *, NSString *> *MenzenBuiltInGames(void) {
	return @{MenzenApelinBundleIdentifier: MenzenApelinAsset};
}

static NSSet<NSString *> *MenzenInstalledBuiltInGames(void) {
	NSMutableSet *games = [NSMutableSet set];
	for (NSString *bundleIdentifier in MenzenBuiltInGames()) {
		if (MenzenInstalledAppVersion(bundleIdentifier)) [games addObject:bundleIdentifier];
	}

	return games;
}

static NSArray<NSString *> *MenzenCatalogFiles(void) {
	return @[MenzenGamesFile, @"audio.json", @"video.json"];
}

static NSString *MenzenCachePath(NSString *file) {
	NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
	return [[caches stringByAppendingPathComponent:@"moe.waru.menzend"] stringByAppendingPathComponent:file];
}

static NSString *MenzenETagKey(NSString *file) {
	return [@"catalogETag." stringByAppendingString:file];
}

// The apps on the home screen that aren't Apple's.
static NSSet<NSString *> *MenzenInstalledApps(void) {
	NSMutableSet *apps = [NSMutableSet set];
	@autoreleasepool {
		for (LSApplicationProxy *proxy in MenzenWorkspace().allInstalledApplications) {
			NSString *bundleIdentifier = proxy.bundleIdentifier;
			if ([proxy.applicationType isEqualToString:@"User"] && [bundleIdentifier isKindOfClass:NSString.class]) [apps addObject:bundleIdentifier];
		}
	}

	return apps;
}

// A file's entries for the given apps, bundle ID to {icon, appStoreId};
// nil when the file isn't the list. iOS 14 gives a daemon 6 MB, and the list
// parsed whole takes several times that, so the file is mapped rather than
// read, and only the lines of the apps asked about are parsed: the catalog
// writes one app per line (.github/scripts/catalog.py).
static NSDictionary<NSString *, NSDictionary *> *MenzenReadCatalog(NSString *path, NSSet<NSString *> *apps) {
	NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedAlways error:NULL];
	if (data.length < 2 || ((const char *)data.bytes)[0] != '{') return nil;
	NSMutableDictionary *entries = [NSMutableDictionary dictionary];
	const char *bytes = data.bytes;
	const char *end = bytes + data.length;
	for (const char *line = bytes; line < end;) {
		const char *lineEnd = memchr(line, '\n', end - line) ?: end;
		@autoreleasepool {
			// \t"<bundle ID>": {...},
			const char *keyStart = memchr(line, '"', lineEnd - line);
			const char *keyEnd = keyStart ? memchr(keyStart + 1, '"', lineEnd - keyStart - 1) : NULL;
			const char *object = keyEnd ? memchr(keyEnd, '{', lineEnd - keyEnd) : NULL;
			const char *objectEnd = lineEnd;
			while (object && objectEnd > object && objectEnd[-1] != '}') objectEnd--;
			NSString *bundleIdentifier = keyEnd ? [[NSString alloc] initWithBytes:keyStart + 1 length:keyEnd - keyStart - 1 encoding:NSUTF8StringEncoding] : nil;
			if (bundleIdentifier && object && objectEnd > object && [apps containsObject:bundleIdentifier]) {
				NSDictionary *entry = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytesNoCopy:(void *)object length:objectEnd - object freeWhenDone:NO] options:0 error:NULL];
				if ([entry isKindOfClass:NSDictionary.class] && MenzenIsIconURL(entry[@"icon"])) {
					id appStoreId = entry[@"appStoreId"];
					entries[bundleIdentifier] = [appStoreId isKindOfClass:NSNumber.class] ? @{@"icon": entry[@"icon"], @"appStoreId": appStoreId} : @{@"icon": entry[@"icon"]};
				}
			}
		}
		line = lineEnd + 1;
	}

	return entries;
}

@implementation MenzenAppCatalog {
	// Only the installed apps and the supported ones: the lists have
	// thousands.
	NSDictionary<NSString *, NSDictionary *> *_games;
	NSDictionary<NSString *, NSDictionary *> *_apps;
	NSSet<NSString *> *_builtIn;
	NSSet<NSString *> *_installed;
	NSURLSession *_session;
	NSUInteger _checkGeneration;
	NSUInteger _readGeneration;
	NSDate *_lastCheck;
}

static void MenzenApplicationsChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	MenzenAppCatalog *catalog = (__bridge MenzenAppCatalog *)observer;
	dispatch_async(dispatch_get_main_queue(), ^{
		[catalog read];
	});
}

- (instancetype)init {
	if ((self = [super init])) {
		_games = @{};
		_apps = @{};
		_installed = [NSSet set];
		_builtIn = [NSSet set];
		NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
		// The ETag decides; a cached answer would hide a newer list.
		configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
		_session = [NSURLSession sessionWithConfiguration:configuration];
	}

	return self;
}

- (void)start {
	CFPreferencesSetAppValue(MenzenOldETagKey, NULL, MenzenDaemonDomain);
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, MenzenApplicationsChanged, MenzenApplicationsChangedNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	[self read];
	[self scheduleCheckAfter:MenzenFirstCheckDelay];
}

- (void)read {
	NSUInteger generation = ++_readGeneration;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		NSSet *installed = MenzenInstalledApps();
		NSSet *builtIn = MenzenInstalledBuiltInGames();
		// The supported apps too, for the pane's list of the ones that
		// aren't installed.
		NSMutableSet *wanted = [installed mutableCopy];
		for (NSDictionary *provider in MenzenProviders()) [wanted addObject:provider[MenzenProviderBundleIdentifierKey]];

		NSDictionary *games = @{};
		NSMutableDictionary *apps = [NSMutableDictionary dictionary];
		for (NSString *file in MenzenCatalogFiles()) {
			NSDictionary *entries = MenzenReadCatalog(MenzenCachePath(file), wanted) ?: @{};
			if ([file isEqualToString:MenzenGamesFile]) games = entries;
			[apps addEntriesFromDictionary:entries];
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			if (generation != self->_readGeneration) return;
			self->_installed = installed;
			self->_builtIn = builtIn;
			self->_games = games;
			self->_apps = apps;
			if (self.changedHandler) self.changedHandler();
		});
	});
}

- (void)scheduleCheckAfter:(NSTimeInterval)delay {
	NSUInteger generation = ++_checkGeneration;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (generation == self->_checkGeneration) [self check];
	});
}

- (void)checkIfStale {
	if (!_lastCheck || -_lastCheck.timeIntervalSinceNow > MenzenStaleAge) [self check];
}

- (void)check {
	// Any check scheduled before is replaced by the one this schedules.
	_checkGeneration++;
	_lastCheck = NSDate.date;
	dispatch_group_t group = dispatch_group_create();
	__block BOOL changed = NO;
	__block BOOL failed = NO;
	for (NSString *file in MenzenCatalogFiles()) {
		dispatch_group_enter(group);
		[self download:file completion:^(BOOL saved, BOOL current) {
			changed |= saved;
			failed |= !current;
			dispatch_group_leave(group);
		}];
	}

	dispatch_group_notify(group, dispatch_get_main_queue(), ^{
		if (changed) [self read];
		[self scheduleCheckAfter:failed ? MenzenRetryInterval : MenzenCheckInterval];
	});
}

// Calls back on the main queue: saved when a new copy replaced the old one,
// current when the copy on disk is the latest (saved, or unchanged).
- (void)download:(NSString *)file completion:(void (^)(BOOL saved, BOOL current))completion {
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[MenzenCatalogURL stringByAppendingString:file]]];
	NSString *path = MenzenCachePath(file);
	NSString *etag = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)MenzenETagKey(file), MenzenDaemonDomain));
	// Without a copy on disk, a 304 would leave nothing to read.
	if ([etag isKindOfClass:NSString.class] && [NSFileManager.defaultManager fileExistsAtPath:path]) [request setValue:etag forHTTPHeaderField:@"If-None-Match"];

	// Downloaded to a file, which is all MenzenReadCatalog needs, rather than
	// into memory.
	[[_session downloadTaskWithRequest:request completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
		NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
		BOOL saved = NO;
		if (http.statusCode == 200 && location && MenzenReadCatalog(location.path, [NSSet set])) {
			[NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
			[NSFileManager.defaultManager removeItemAtPath:path error:nil];
			saved = [NSFileManager.defaultManager moveItemAtPath:location.path toPath:path error:nil];
		}

		NSString *newETag = saved ? http.allHeaderFields[@"ETag"] : nil;
		BOOL current = saved || http.statusCode == 304;
		dispatch_async(dispatch_get_main_queue(), ^{
			if (saved) {
				CFPreferencesSetAppValue((__bridge CFStringRef)MenzenETagKey(file), (__bridge CFStringRef)newETag, MenzenDaemonDomain);
				CFPreferencesAppSynchronize(MenzenDaemonDomain);
			}
			completion(saved, current);
		});
	}] resume];
}

- (NSString *)iconURLForApp:(NSString *)bundleIdentifier {
	if ([_builtIn containsObject:bundleIdentifier]) return MenzenBuiltInGames()[bundleIdentifier];
	return _apps[bundleIdentifier][@"icon"];
}

- (NSString *)storeURLForApp:(NSString *)bundleIdentifier {
	NSNumber *appStoreId = _apps[bundleIdentifier][@"appStoreId"];
	return appStoreId ? [NSString stringWithFormat:@"https://apps.apple.com/app/id%@", appStoreId] : nil;
}

- (BOOL)isGame:(NSString *)bundleIdentifier {
	return _games[bundleIdentifier] != nil || [_builtIn containsObject:bundleIdentifier] || MenzenIsGameApp(bundleIdentifier);
}

- (NSArray<NSString *> *)installedGames {
	NSMutableArray *games = [NSMutableArray array];
	@autoreleasepool {
		for (NSString *bundleIdentifier in _installed) {
			if ([self isGame:bundleIdentifier]) [games addObject:bundleIdentifier];
		}
	}

	[games addObjectsFromArray:_builtIn.allObjects];
	return games;
}

- (NSDictionary<NSString *, NSString *> *)providerIcons {
	NSMutableDictionary *icons = [NSMutableDictionary dictionary];
	for (NSDictionary *provider in MenzenProviders()) {
		NSString *bundleIdentifier = provider[MenzenProviderBundleIdentifierKey];
		icons[bundleIdentifier] = _apps[bundleIdentifier][@"icon"];
	}

	return icons;
}

@end
