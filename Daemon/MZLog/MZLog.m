#import <roothide.h>

#import "MZLog.h"

#ifdef DEBUG

static unsigned long long const MZMaxLogSize = 2 * 1024 * 1024;

static dispatch_queue_t logQueue;
static NSFileHandle *logHandle;
static NSDateFormatter *formatter;

static void MZOpenLog(void) {
	NSFileManager *fileManager = NSFileManager.defaultManager;
	NSString *directory = jbroot(@"/var/mobile/Library/Logs/Menzen");
	NSString *path = [directory stringByAppendingPathComponent:@"menzend.log"];
	NSString *oldPath = [directory stringByAppendingPathComponent:@"menzend.old.log"];
	// The log has what was played and which apps were open: mobile only.
	NSDictionary *directoryAttributes = @{NSFilePosixPermissions: @0700};
	NSDictionary *fileAttributes = @{NSFilePosixPermissions: @0600};
	[fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:directoryAttributes error:nil];
	[fileManager setAttributes:directoryAttributes ofItemAtPath:directory error:nil];

	NSDictionary *attributes = [fileManager attributesOfItemAtPath:path error:nil];
	if (attributes.fileSize > MZMaxLogSize) {
		[fileManager removeItemAtPath:oldPath error:nil];
		[fileManager moveItemAtPath:path toPath:oldPath error:nil];
	}

	if (![fileManager fileExistsAtPath:path]) [fileManager createFileAtPath:path contents:nil attributes:fileAttributes];
	[fileManager setAttributes:fileAttributes ofItemAtPath:path error:nil];
	[fileManager setAttributes:fileAttributes ofItemAtPath:oldPath error:nil];

	logHandle = [NSFileHandle fileHandleForWritingAtPath:path];
	[logHandle seekToEndOfFile];

	formatter = [NSDateFormatter new];
	formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
}

void MZLog(NSString *format, ...) {
	va_list arguments;
	va_start(arguments, format);
	NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
	va_end(arguments);

	NSDate *date = NSDate.date;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		logQueue = dispatch_queue_create("moe.waru.menzend.log", DISPATCH_QUEUE_SERIAL);
		dispatch_async(logQueue, ^{ MZOpenLog(); });
	});
	dispatch_async(logQueue, ^{
		NSString *line = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:date], message];
		[logHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
	});
	NSLog(@"[Menzen] %@", message);
}

void MZLogFlush(void) {
	if (logQueue) dispatch_sync(logQueue, ^{
		[logHandle synchronizeFile];
	});
}

#endif
