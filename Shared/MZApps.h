#import <Foundation/Foundation.h>
#import <fcntl.h>
#import <roothide.h>
#import <sys/stat.h>

#import "MZSupport.h"

NS_ASSUME_NONNULL_BEGIN

@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)bundleIdentifier;
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *applicationType;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *shortVersionString;
@property (nonatomic, readonly) NSString *bundleVersion;
@property (nonatomic, readonly) NSURL *dataContainerURL;
- (nullable id)entitlementValueForKey:(NSString *)key ofClass:(Class)valueClass;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
- (BOOL)applicationIsInstalled:(NSString *)bundleIdentifier;
@end

static inline NSArray<NSDictionary *> *MZProviderFilters(void) {
	NSString *directory = jbroot(@"/Library/MobileSubstrate/DynamicLibraries");
	NSMutableArray *filters = [NSMutableArray array];
	for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil]) {
		if (![name hasPrefix:@"Menzen"] || ![name.pathExtension isEqualToString:@"plist"]) continue;
		NSDictionary *filter = [NSDictionary dictionaryWithContentsOfFile:[directory stringByAppendingPathComponent:name]];
		if ([filter isKindOfClass:NSDictionary.class]) [filters addObject:filter];
	}
	return filters;
}

static inline NSSet<NSString *> *MZHookedBundles(void) {
	NSMutableSet *bundles = [NSMutableSet set];
	for (NSDictionary *filter in MZProviderFilters()) {
		NSDictionary *loader = [filter[@"Filter"] isKindOfClass:NSDictionary.class] ? filter[@"Filter"] : nil;
		NSArray *names = loader[@"Bundles"];
		if ([names isKindOfClass:NSArray.class]) [bundles addObjectsFromArray:names];
	}
	return bundles;
}

static inline LSApplicationWorkspace *MZWorkspace(void) {
	return [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
}

static inline LSApplicationProxy *_Nullable MZAppProxy(NSString *bundleIdentifier) {
	return [NSClassFromString(@"LSApplicationProxy") applicationProxyForIdentifier:bundleIdentifier];
}

// In the format the status uses; nil when it isn't installed.
static inline NSString *_Nullable MZInstalledAppVersion(NSString *bundleIdentifier) {
	LSApplicationProxy *proxy = MZAppProxy(bundleIdentifier);
	NSString *version = proxy.shortVersionString;
	if (![version isKindOfClass:NSString.class] || !version.length) return nil;
	return MZSupportVersion(version, proxy.bundleVersion);
}

// The status file is in the app's own container, so the app can write
// anything there: only what MZProviderCheck writes is kept, in its types.
static NSUInteger const MZStatusMaxSize = 64 * 1024;
static NSUInteger const MZStatusMaxLength = 256;
static NSUInteger const MZStatusMaxItems = 64;

// No control or format characters: no line breaks in the alert or the
// report, and no right-to-left overrides.
static inline NSString *_Nullable MZStatusString(id _Nullable value) {
	if (![value isKindOfClass:NSString.class] || ![value length] || [value length] > MZStatusMaxLength) return nil;
	NSMutableCharacterSet *invalid = [NSMutableCharacterSet controlCharacterSet];
	[invalid formUnionWithCharacterSet:NSCharacterSet.illegalCharacterSet];
	return [value rangeOfCharacterFromSet:invalid].location == NSNotFound ? value : nil;
}

static inline NSArray<NSString *> *_Nullable MZStatusStrings(id _Nullable value) {
	if (![value isKindOfClass:NSArray.class]) return nil;
	NSMutableArray *strings = [NSMutableArray array];
	for (id item in value) {
		if (strings.count == MZStatusMaxItems) break;
		NSString *string = MZStatusString(item);
		if (string) [strings addObject:string];
	}

	return strings;
}

// A regular file only: not a link to another file, and not a FIFO, which
// would block the read.
static inline NSData *_Nullable MZReadStatusFile(NSString *path) {
	int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
	if (fd < 0) return nil;
	struct stat info;
	if (fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_size > (off_t)MZStatusMaxSize) {
		close(fd);
		return nil;
	}

	NSFileHandle *handle = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
	NSData *data = [handle readDataUpToLength:MZStatusMaxSize + 1 error:NULL];
	return data.length <= MZStatusMaxSize ? data : nil;
}

static inline NSDictionary *_Nullable MZAppSupportStatus(NSString *bundleIdentifier) {
	NSURL *container = MZAppProxy(bundleIdentifier).dataContainerURL;
	if (![container isKindOfClass:NSURL.class] || !container.isFileURL) return nil;
	NSData *data = MZReadStatusFile([container URLByAppendingPathComponent:MZSupportStatusPath].path);
	NSDictionary *file = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL] : nil;
	if (![file isKindOfClass:NSDictionary.class]) return nil;

	NSMutableDictionary *status = [NSMutableDictionary dictionary];
	for (NSString *key in @[MZSupportAppVersionKey, MZSupportMenzenVersionKey, MZSupportWorkedVersionKey, MZSupportAlertedVersionKey]) status[key] = MZStatusString(file[key]);
	for (NSString *key in @[MZSupportCheckedKey, MZSupportWorkedKey]) status[key] = [file[key] isKindOfClass:NSDate.class] ? file[key] : nil;
	for (NSString *key in @[MZSupportMissingKey, MZSupportMissingOptionalKey]) status[key] = MZStatusStrings(file[key]);
	status[MZSupportBackgroundKey] = [file[MZSupportBackgroundKey] isKindOfClass:NSNumber.class] ? file[MZSupportBackgroundKey] : nil;
	return status;
}

static inline BOOL MZStatusIsCurrent(NSDictionary *_Nullable status, NSString *_Nullable installedVersion) {
	return status && installedVersion && [status[MZSupportAppVersionKey] isEqual:installedVersion] && [status[MZSupportMenzenVersionKey] isEqual:@MZ_VERSION] && status[MZSupportCheckedKey];
}

NS_ASSUME_NONNULL_END
