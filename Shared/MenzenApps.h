#import <Foundation/Foundation.h>
#import <fcntl.h>
#import <roothide.h>
#import <sys/stat.h>

#import "MenzenSupport.h"

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

static inline NSArray<NSDictionary *> *MenzenProviderFilters(void) {
	NSString *directory = jbroot(@"/Library/MobileSubstrate/DynamicLibraries");
	NSMutableArray *filters = [NSMutableArray array];
	for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil]) {
		if (![name hasPrefix:@"Menzen"] || ![name.pathExtension isEqualToString:@"plist"]) continue;
		NSDictionary *filter = [NSDictionary dictionaryWithContentsOfFile:[directory stringByAppendingPathComponent:name]];
		if ([filter isKindOfClass:NSDictionary.class]) [filters addObject:filter];
	}
	return filters;
}

static inline NSSet<NSString *> *MenzenHookedBundles(void) {
	NSMutableSet *bundles = [NSMutableSet set];
	for (NSDictionary *filter in MenzenProviderFilters()) {
		NSDictionary *loader = [filter[@"Filter"] isKindOfClass:NSDictionary.class] ? filter[@"Filter"] : nil;
		NSArray *names = loader[@"Bundles"];
		if ([names isKindOfClass:NSArray.class]) [bundles addObjectsFromArray:names];
	}
	return bundles;
}

static inline LSApplicationWorkspace *MenzenWorkspace(void) {
	return [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
}

static inline LSApplicationProxy *_Nullable MenzenAppProxy(NSString *bundleIdentifier) {
	return [NSClassFromString(@"LSApplicationProxy") applicationProxyForIdentifier:bundleIdentifier];
}

// In the format the status uses; nil when it isn't installed.
static inline NSString *_Nullable MenzenInstalledAppVersion(NSString *bundleIdentifier) {
	LSApplicationProxy *proxy = MenzenAppProxy(bundleIdentifier);
	NSString *version = proxy.shortVersionString;
	if (![version isKindOfClass:NSString.class] || !version.length) return nil;
	return MenzenSupportVersion(version, proxy.bundleVersion);
}

// The status file is in the app's own container, so the app can write
// anything there: only what MenzenProviderCheck writes is kept, in its types.
static NSUInteger const MenzenStatusMaxSize = 64 * 1024;
static NSUInteger const MenzenStatusMaxLength = 256;
static NSUInteger const MenzenStatusMaxItems = 64;

// No control or format characters: no line breaks in the alert or the
// report, and no right-to-left overrides.
static inline NSString *_Nullable MenzenStatusString(id _Nullable value) {
	if (![value isKindOfClass:NSString.class] || ![value length] || [value length] > MenzenStatusMaxLength) return nil;
	NSMutableCharacterSet *invalid = [NSMutableCharacterSet controlCharacterSet];
	[invalid formUnionWithCharacterSet:NSCharacterSet.illegalCharacterSet];
	return [value rangeOfCharacterFromSet:invalid].location == NSNotFound ? value : nil;
}

static inline NSArray<NSString *> *_Nullable MenzenStatusStrings(id _Nullable value) {
	if (![value isKindOfClass:NSArray.class]) return nil;
	NSMutableArray *strings = [NSMutableArray array];
	for (id item in value) {
		if (strings.count == MenzenStatusMaxItems) break;
		NSString *string = MenzenStatusString(item);
		if (string) [strings addObject:string];
	}

	return strings;
}

// A regular file only: not a link to another file, and not a FIFO, which
// would block the read.
static inline NSData *_Nullable MenzenReadStatusFile(NSString *path) {
	int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
	if (fd < 0) return nil;
	struct stat info;
	if (fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_size > (off_t)MenzenStatusMaxSize) {
		close(fd);
		return nil;
	}

	NSFileHandle *handle = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
	NSData *data = [handle readDataUpToLength:MenzenStatusMaxSize + 1 error:NULL];
	return data.length <= MenzenStatusMaxSize ? data : nil;
}

static inline NSDictionary *_Nullable MenzenAppSupportStatus(NSString *bundleIdentifier) {
	NSURL *container = MenzenAppProxy(bundleIdentifier).dataContainerURL;
	if (![container isKindOfClass:NSURL.class] || !container.isFileURL) return nil;
	NSData *data = MenzenReadStatusFile([container URLByAppendingPathComponent:MenzenSupportStatusPath].path);
	NSDictionary *file = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL] : nil;
	if (![file isKindOfClass:NSDictionary.class]) return nil;

	NSMutableDictionary *status = [NSMutableDictionary dictionary];
	for (NSString *key in @[MenzenSupportAppVersionKey, MenzenSupportMenzenVersionKey, MenzenSupportWorkedVersionKey, MenzenSupportAlertedVersionKey]) status[key] = MenzenStatusString(file[key]);
	for (NSString *key in @[MenzenSupportCheckedKey, MenzenSupportWorkedKey]) status[key] = [file[key] isKindOfClass:NSDate.class] ? file[key] : nil;
	for (NSString *key in @[MenzenSupportMissingKey, MenzenSupportMissingOptionalKey]) status[key] = MenzenStatusStrings(file[key]);
	status[MenzenSupportBackgroundKey] = [file[MenzenSupportBackgroundKey] isKindOfClass:NSNumber.class] ? file[MenzenSupportBackgroundKey] : nil;
	return status;
}

static inline BOOL MenzenStatusIsCurrent(NSDictionary *_Nullable status, NSString *_Nullable installedVersion) {
	return status && installedVersion && [status[MenzenSupportAppVersionKey] isEqual:installedVersion] && [status[MenzenSupportMenzenVersionKey] isEqual:@MENZEN_VERSION] && status[MenzenSupportCheckedKey];
}

NS_ASSUME_NONNULL_END
