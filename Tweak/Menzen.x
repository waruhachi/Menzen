#import "Menzen.h"

#import <roothide.h>

// Debug only: logs everything MediaRemote reports, to see which artwork URLs
// and content IDs each app has. Written to a file because os_log truncates
// long messages.

#define MZLogDirectory jbroot(@"/var/mobile/Library/Logs/Menzen")
#define MZLogPath jbroot(@"/var/mobile/Library/Logs/Menzen/probe.log")
static unsigned long long const MZMaxLogSize = 8 * 1024 * 1024;

static dispatch_queue_t probeQueue;
static NSFileHandle *logHandle;
static NSUInteger snapshotGeneration;

static MRMediaRemoteGetNowPlayingInfoFn MRGetNowPlayingInfo;
static MRMediaRemoteGetNowPlayingApplicationIsPlayingFn MRGetNowPlayingApplicationIsPlaying;
static MRMediaRemoteGetNowPlayingClientFn MRGetNowPlayingClient;
static MRNowPlayingClientGetStringFn MRClientGetBundleIdentifier;
static MRNowPlayingClientGetStringFn MRClientGetParentAppBundleIdentifier;
static MRNowPlayingClientGetStringFn MRClientGetDisplayName;

static void MZOpenLog(void) {
	NSFileManager *fileManager = NSFileManager.defaultManager;
	NSString *oldPath = [MZLogDirectory stringByAppendingPathComponent:@"probe.old.log"];
	// Same as menzend's log: mobile only.
	NSDictionary *directoryAttributes = @{NSFilePosixPermissions: @0700};
	NSDictionary *fileAttributes = @{NSFilePosixPermissions: @0600};
	[fileManager createDirectoryAtPath:MZLogDirectory withIntermediateDirectories:YES attributes:directoryAttributes error:nil];
	[fileManager setAttributes:directoryAttributes ofItemAtPath:MZLogDirectory error:nil];

	NSDictionary *attributes = [fileManager attributesOfItemAtPath:MZLogPath error:nil];
	if (attributes.fileSize > MZMaxLogSize) {
		[fileManager removeItemAtPath:oldPath error:nil];
		[fileManager moveItemAtPath:MZLogPath toPath:oldPath error:nil];
	}

	if (![fileManager fileExistsAtPath:MZLogPath]) [fileManager createFileAtPath:MZLogPath contents:nil attributes:fileAttributes];
	[fileManager setAttributes:fileAttributes ofItemAtPath:MZLogPath error:nil];
	[fileManager setAttributes:fileAttributes ofItemAtPath:oldPath error:nil];

	logHandle = [NSFileHandle fileHandleForWritingAtPath:MZLogPath];
	[logHandle seekToEndOfFile];
	if (!logHandle) NSLog(@"[Menzen] could not open %@", MZLogPath);
}

// Only call on probeQueue.
static void MZLog(NSString *line) {
	static NSDateFormatter *formatter;
	if (!formatter) {
		formatter = [NSDateFormatter new];
		formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
	}

	NSString *stamped = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:NSDate.date], line];
	[logHandle writeData:[stamped dataUsingEncoding:NSUTF8StringEncoding]];
}

static NSString *MZDescribe(id value, NSUInteger depth);

static NSString *MZIndent(NSUInteger depth) {
	return [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
}

// Objects and plain scalars only: no blocks, structs, pointers or C strings.
static BOOL MZIsReadablePropertyType(const char *attributes) {
	if (!attributes || attributes[0] != 'T') return NO;
	char type = attributes[1];
	if (type == '@') return attributes[2] != '?';
	return strchr("cislqCISLQfdB", type) != NULL;
}

static BOOL MZShouldDumpProperties(id value) {
	NSString *name = NSStringFromClass([value class]);
	return [name hasPrefix:@"MR"] || [name hasPrefix:@"_MR"];
}

static NSString *MZDescribeProperties(id object, NSUInteger depth) {
	NSMutableString *out = [NSMutableString stringWithFormat:@"<%@>", NSStringFromClass([object class])];
	if (depth >= 5) return out;

	static NSSet *skipped;
	if (!skipped) skipped = [NSSet setWithArray:@[@"hash", @"superclass", @"description", @"debugDescription"]];

	NSMutableSet *seen = [NSMutableSet set];
	for (Class cls = [object class]; cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
		unsigned int count = 0;
		objc_property_t *properties = class_copyPropertyList(cls, &count);
		for (unsigned int i = 0; i < count; i++) {
			NSString *name = @(property_getName(properties[i]));
			if ([seen containsObject:name] || [skipped containsObject:name]) continue;
			[seen addObject:name];
			if (!MZIsReadablePropertyType(property_getAttributes(properties[i]))) continue;

			id value = nil;
			@try {
				value = [object valueForKey:name];
			}
			@catch (NSException *exception) {
				continue;
			}
			if (!value) continue;
			[out appendFormat:@"\n%@%@ = %@", MZIndent(depth + 1), name, MZDescribe(value, depth + 1)];
		}
		free(properties);
	}

	return out;
}

static NSString *MZDescribe(id value, NSUInteger depth) {
	if (!value) return @"nil";
	// Artwork bytes and serialized protobufs: the size is all we need.
	if ([value isKindOfClass:NSData.class]) return [NSString stringWithFormat:@"<%lu bytes>", (unsigned long)[value length]];
	if ([value isKindOfClass:NSString.class]) return [NSString stringWithFormat:@"\"%@\"", value];
	if ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSURL.class] || [value isKindOfClass:NSDate.class] || [value isKindOfClass:NSUUID.class]) {
		return [value description];
	}

	if ([value isKindOfClass:NSDictionary.class]) {
		NSDictionary *dictionary = value;
		NSArray *keys = [dictionary.allKeys sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
			return [[a description] compare:[b description]];
		}];
		NSMutableString *out = [NSMutableString stringWithString:@"{"];
		for (id key in keys) {
			[out appendFormat:@"\n%@%@ = %@", MZIndent(depth + 1), key, MZDescribe(dictionary[key], depth + 1)];
		}
		[out appendFormat:@"\n%@}", MZIndent(depth)];
		return out;
	}

	if ([value isKindOfClass:NSArray.class] || [value isKindOfClass:NSSet.class]) {
		NSMutableString *out = [NSMutableString stringWithString:@"["];
		NSUInteger index = 0;
		for (id element in value) {
			[out appendFormat:@"\n%@%lu: %@", MZIndent(depth + 1), (unsigned long)index++, MZDescribe(element, depth + 1)];
		}
		[out appendFormat:@"\n%@]", MZIndent(depth)];
		return out;
	}

	if (MZShouldDumpProperties(value)) return MZDescribeProperties(value, depth);

	NSString *description = [value description];
	if (description.length > 500) description = [[description substringToIndex:500] stringByAppendingString:@"…"];
	return [NSString stringWithFormat:@"<%@> %@", NSStringFromClass([value class]), description];
}

static void MZLogSnapshot(NSString *reason) {
	dispatch_group_t group = dispatch_group_create();
	__block NSDictionary *info;
	__block NSString *isPlaying = @"unknown";
	__block NSString *bundleIdentifier, *parentBundleIdentifier, *displayName;

	if (MRGetNowPlayingInfo) {
		dispatch_group_enter(group);
		MRGetNowPlayingInfo(probeQueue, ^(CFDictionaryRef raw) {
			info = [(__bridge NSDictionary *)raw copy];
			dispatch_group_leave(group);
		});
	}

	if (MRGetNowPlayingApplicationIsPlaying) {
		dispatch_group_enter(group);
		MRGetNowPlayingApplicationIsPlaying(probeQueue, ^(Boolean playing) {
			isPlaying = playing ? @"YES" : @"NO";
			dispatch_group_leave(group);
		});
	}

	if (MRGetNowPlayingClient) {
		dispatch_group_enter(group);
		MRGetNowPlayingClient(probeQueue, ^(id client) {
			if (client) {
				if (MRClientGetBundleIdentifier) bundleIdentifier = [(__bridge NSString *)MRClientGetBundleIdentifier(client) copy];
				if (MRClientGetParentAppBundleIdentifier) parentBundleIdentifier = [(__bridge NSString *)MRClientGetParentAppBundleIdentifier(client) copy];
				if (MRClientGetDisplayName) displayName = [(__bridge NSString *)MRClientGetDisplayName(client) copy];
			}
			dispatch_group_leave(group);
		});
	}

	dispatch_group_notify(group, probeQueue, ^{
		MZLog([NSString stringWithFormat:@"==== snapshot (%@)\napp: bundle=%@ parent=%@ name=%@\nplaying: %@\ninfo = %@",
			reason, bundleIdentifier, parentBundleIdentifier, displayName, isPlaying, MZDescribe(info, 0)]);
	});
}

// Notifications come in bursts (track change, artwork, elapsed time), so wait
// for a quiet moment before taking one snapshot. Only call on probeQueue.
static void MZScheduleSnapshot(NSString *reason) {
	NSUInteger generation = ++snapshotGeneration;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), probeQueue, ^{
		if (generation == snapshotGeneration) MZLogSnapshot(reason);
	});
}

static void *MZSymbol(void *handle, const char *name) {
	void *symbol = dlsym(handle, name);
	if (!symbol) NSLog(@"[Menzen] missing MediaRemote symbol %s", name);
	return symbol;
}

static void MZStartProbe(void) {
	void *handle = dlopen(MZMediaRemotePath, RTLD_LAZY);
	if (!handle) {
		NSLog(@"[Menzen] could not open MediaRemote: %s", dlerror());
		return;
	}

	MRMediaRemoteRegisterForNowPlayingNotificationsFn registerForNotifications = MZSymbol(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
	MRGetNowPlayingInfo = MZSymbol(handle, "MRMediaRemoteGetNowPlayingInfo");
	MRGetNowPlayingApplicationIsPlaying = MZSymbol(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
	MRGetNowPlayingClient = MZSymbol(handle, "MRMediaRemoteGetNowPlayingClient");
	MRClientGetBundleIdentifier = MZSymbol(handle, "MRNowPlayingClientGetBundleIdentifier");
	MRClientGetParentAppBundleIdentifier = MZSymbol(handle, "MRNowPlayingClientGetParentAppBundleIdentifier");
	MRClientGetDisplayName = MZSymbol(handle, "MRNowPlayingClientGetDisplayName");

	probeQueue = dispatch_queue_create("moe.waru.menzen.probe", DISPATCH_QUEUE_SERIAL);
	dispatch_async(probeQueue, ^{
		MZOpenLog();
		MZLog([NSString stringWithFormat:@"==== probe started (iOS %@)", UIDevice.currentDevice.systemVersion]);
	});

	const char *notificationSymbols[] = {
		"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
		"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
		"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
		// Its userInfo can carry the updated MRContentItems themselves.
		"kMRMediaRemotePlayerNowPlayingInfoDidChangeNotification",
	};
	for (size_t i = 0; i < sizeof(notificationSymbols) / sizeof(*notificationSymbols); i++) {
		CFStringRef *namePointer = MZSymbol(handle, notificationSymbols[i]);
		if (!namePointer || !*namePointer) continue;
		NSString *name = (__bridge NSString *)*namePointer;
		[NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *notification) {
			NSDictionary *userInfo = [notification.userInfo copy];
			dispatch_async(probeQueue, ^{
				MZLog([NSString stringWithFormat:@"-- %@ userInfo = %@", name, MZDescribe(userInfo, 0)]);
				MZScheduleSnapshot(name);
			});
		}];
	}

	if (registerForNotifications) registerForNotifications(dispatch_get_main_queue());
	dispatch_async(probeQueue, ^{ MZScheduleSnapshot(@"startup"); });
	NSLog(@"[Menzen] probe running, logging to %@", MZLogPath);
}

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
	%orig;
	MZStartProbe();
}

%end
