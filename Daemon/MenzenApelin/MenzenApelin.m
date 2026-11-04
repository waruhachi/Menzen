#import <roothide.h>

#import "../../Shared/MenzenLocalization/MenzenLocalization.h"
#import "MenzenApelin.h"

// Each agent session is a folder in Apelin's documents: session.json has the
// project ({"project": {"name"}}), events.jsonl one event per line
// ({"seq", "date", "event": {"<kind>": {...}}}), appended as the agent works.
static NSString *const MenzenSessionsPath = @"/var/mobile/Documents/wiki.qaq.apelin/sessions";
static NSUInteger const MenzenSessionMaxSize = 64 * 1024;
// The last events say what's happening; the log keeps every token count.
static unsigned long long const MenzenEventsTail = 32 * 1024;
static NSUInteger const MenzenProjectMaxLength = 64;
// An agent that stopped writing without finishing was stopped some other
// way. One waiting for approval waits as long as it takes.
static NSTimeInterval const MenzenStaleAge = 10 * 60;

static NSString *const MenzenIdle = @"";
static NSString *const MenzenWaitingForApproval = @"Waiting for approval";

@implementation MenzenApelinSession
@end

static NSDate *MenzenModified(NSURL *url) {
	NSDate *date;
	return [url getResourceValue:&date forKey:NSURLContentModificationDateKey error:NULL] ? date : nil;
}

static NSURL *MenzenNewestSession(void) {
	NSURL *sessions = [NSURL fileURLWithPath:jbroot(MenzenSessionsPath) isDirectory:YES];
	NSArray<NSURL *> *folders = [NSFileManager.defaultManager contentsOfDirectoryAtURL:sessions includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
	NSURL *newest;
	NSDate *newestDate;
	for (NSURL *folder in folders) {
		NSDate *date = MenzenModified([folder URLByAppendingPathComponent:@"events.jsonl"]) ?: MenzenModified([folder URLByAppendingPathComponent:@"session.json"]);
		if (date && (!newestDate || [date compare:newestDate] == NSOrderedDescending)) {
			newest = folder;
			newestDate = date;
		}
	}

	return newest;
}

static NSString *MenzenProject(NSURL *session) {
	NSData *data = [NSData dataWithContentsOfURL:[session URLByAppendingPathComponent:@"session.json"] options:NSDataReadingMappedIfSafe error:NULL];
	if (!data || data.length > MenzenSessionMaxSize) return nil;
	NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
	NSDictionary *project = [json isKindOfClass:NSDictionary.class] ? json[@"project"] : nil;
	NSString *name = [project isKindOfClass:NSDictionary.class] ? project[@"name"] : nil;
	if (![name isKindOfClass:NSString.class]) return nil;
	name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (!name.length || name.length > MenzenProjectMaxLength || [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return nil;
	return name;
}

// The tool's name is somewhere in the event; which field isn't fixed, so any
// string that's a known tool counts.
static NSString *MenzenToolName(id value, NSSet<NSString *> *tools, NSUInteger depth) {
	if ([value isKindOfClass:NSString.class]) return [tools containsObject:value] ? value : nil;
	if (depth == 0) return nil;
	NSArray *values = [value isKindOfClass:NSDictionary.class] ? [value allValues] : [value isKindOfClass:NSArray.class] ? value
																														 : nil;
	for (id item in values) {
		NSString *name = MenzenToolName(item, tools, depth - 1);
		if (name) return name;
	}

	return nil;
}

static NSString *MenzenToolState(id payload) {
	static NSDictionary<NSString *, NSString *> *states;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		states = @{
			@"apelin_project_build": @"Building",
			@"apelin_package_install": @"Installing a package",
			@"apelin_package_publish": @"Packaging",
			@"apelin_package_remove": @"Removing a package",
			@"apelin_device_respring": @"Respringing",
			@"file_edit": @"Editing files",
			@"file_write": @"Editing files",
			@"file_read": @"Reading files",
			@"git_clone": @"Cloning a repository",
		};
	});
	NSString *name = MenzenToolName(payload, [NSSet setWithArray:states.allKeys], 3);
	return name ? states[name] : @"Running tools";
}

// nil for an event that says nothing new (token counts, notices, titles).
static NSString *MenzenAgentState(NSString *kind, id payload) {
	static NSSet<NSString *> *idle, *thinking;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		idle = [NSSet setWithArray:@[@"finished", @"error", @"messageDiscarded", @"queuedMessagesDropped"]];
		thinking = [NSSet setWithArray:@[@"promptSubmitted", @"userMessage", @"steered", @"messageStarted", @"thinkingDelta", @"messageFinished", @"toolCallFinished", @"approvalResolved", @"compactionFinished"]];
	});
	if ([idle containsObject:kind]) return MenzenIdle;
	if ([thinking containsObject:kind]) return @"Thinking";
	if ([kind isEqualToString:@"textDelta"]) return @"Responding";
	if ([kind isEqualToString:@"toolCallPreparing"] || [kind isEqualToString:@"toolCallStarted"]) return MenzenToolState(payload);
	if ([kind isEqualToString:@"approvalRequested"]) return MenzenWaitingForApproval;
	if ([kind isEqualToString:@"compactionStarted"]) return @"Compacting";
	if ([kind isEqualToString:@"reconnecting"]) return @"Reconnecting";
	return nil;
}

static NSString *MenzenAgent(NSURL *session) {
	NSURL *events = [session URLByAppendingPathComponent:@"events.jsonl"];
	NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:events error:NULL];
	unsigned long long size = 0;
	if (!handle || ![handle seekToEndReturningOffset:&size error:NULL]) return nil;
	unsigned long long start = size > MenzenEventsTail ? size - MenzenEventsTail : 0;
	if (![handle seekToOffset:start error:NULL]) return nil;
	NSData *data = [handle readDataUpToLength:(NSUInteger)(size - start) error:NULL];
	[handle closeAndReturnError:NULL];
	NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
	NSMutableArray<NSString *> *lines = [[text componentsSeparatedByString:@"\n"] mutableCopy];
	// Cut mid-line, or mid-character (then the text is nil and nothing shows).
	if (start > 0 && lines.count) [lines removeObjectAtIndex:0];

	NSString *state;
	for (NSString *line in lines.reverseObjectEnumerator) {
		NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
		NSDictionary *entry = lineData.length ? [NSJSONSerialization JSONObjectWithData:lineData options:0 error:NULL] : nil;
		id event = [entry isKindOfClass:NSDictionary.class] ? entry[@"event"] : nil;
		NSString *kind = [event isKindOfClass:NSString.class] ? event : [event isKindOfClass:NSDictionary.class] && [event count] == 1 ? [event allKeys].firstObject
																																	   : nil;
		state = [kind isKindOfClass:NSString.class] ? MenzenAgentState(kind, [event isKindOfClass:NSDictionary.class] ? event[kind] : nil) : nil;
		if (state) break;
	}

	if (!state.length) return nil;
	NSDate *modified = MenzenModified(events);
	if (![state isEqualToString:MenzenWaitingForApproval] && (!modified || -modified.timeIntervalSinceNow > MenzenStaleAge)) return nil;
	return state;
}

// "Installing a package" -> "installing_a_package".
static NSString *MenzenStateKey(NSString *state) {
	NSMutableString *key = [state.lowercaseString mutableCopy];
	[key replaceOccurrencesOfString:@" " withString:@"_" options:0 range:NSMakeRange(0, key.length)];
	return key;
}

MenzenApelinSession *MenzenReadApelinSession(void) {
	NSURL *folder = MenzenNewestSession();
	if (!folder) return nil;
	MenzenApelinSession *session = [MenzenApelinSession new];
	session.project = MenzenProject(folder);
	NSString *agent = MenzenAgent(folder);
	// What the agent is doing, as people read it.
	session.agent = agent ? MenzenLocalizedString([@"apelin.state." stringByAppendingString:MenzenStateKey(agent)], agent) : nil;
	return session;
}
