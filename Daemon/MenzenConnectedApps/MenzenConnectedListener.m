#import "../../Client/Menzen.h"
#import "../../Shared/MenzenConnectedApps.h"
#import "../../Shared/MenzenCustomActivity.h"
#import "../../Shared/MenzenService.h"
#import "../MenzenCodeSigning/MenzenCodeSigning.h"
#import "../MenzenDiscord/MenzenDiscord.h"
#import "../MenzenDiscord/MenzenKeychain.h"
#import "../MenzenPresence/MenzenPresence.h"
#import "MenzenConnectedListener.h"

// More at once than any device runs; the rest are turned away.
static NSUInteger const MenzenConnectedConnectionLimit = 64;
// So one process can't take all of them.
static NSUInteger const MenzenConnectedProcessConnectionLimit = 4;
static NSUInteger const MenzenConnectedTextLimit = 128;
static NSUInteger const MenzenConnectedURLLimit = 512;
// Requests SpringBoard hasn't shown by then never will be (it restarted).
static NSTimeInterval const MenzenConnectedRequestAge = 60;
// The apps the user allowed, each with the signing identifier of the process
// that was allowed, so another process can't claim to be it.
static NSString *const MenzenConnectedApprovalsAccount = @"connectedApprovals";

static NSString *MenzenConnectedText(id text) {
	if (![text isKindOfClass:NSString.class]) return nil;

	text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (![text length]) return nil;
	if ([text length] <= MenzenConnectedTextLimit) return text;

	return [text substringToIndex:[text rangeOfComposedCharacterSequenceAtIndex:MenzenConnectedTextLimit - 1].location];
}

static NSString *MenzenConnectedImage(id url) {
	if (![url isKindOfClass:NSString.class] || [url length] > MenzenConnectedURLLimit) return nil;

	return MenzenCustomURLIsAllowed(url) ? url : nil;
}

// Between 2000 and 2100: anything else isn't a time an activity started or
// ends.
static NSDate *MenzenConnectedDate(id seconds) {
	if (![seconds isKindOfClass:NSNumber.class]) return nil;

	double value = [seconds doubleValue];
	if (!isfinite(value) || value < 946684800 || value > 4102444800) return nil;

	return [NSDate dateWithTimeIntervalSince1970:value];
}

// Only what MenzenConnectedActivity reads is kept of what a client sends.
static NSDictionary *MenzenConnectedFields(id sent) {
	if (![sent isKindOfClass:NSDictionary.class]) return nil;

	NSArray *texts = @[MenzenActivityKindKey, MenzenActivityNameKey, MenzenActivityDetailsKey, MenzenActivityStateKey, MenzenActivityLargeTextKey, MenzenActivitySmallTextKey, MenzenActivityStatusDisplayKey];
	NSArray *links = @[MenzenActivityImageURLKey, MenzenActivitySmallImageURLKey];
	NSArray *dates = @[MenzenActivityStartKey, MenzenActivityEndKey];
	NSMutableDictionary *fields = [NSMutableDictionary dictionary];

	for (NSString *key in texts) fields[key] = MenzenConnectedText(sent[key]);
	for (NSString *key in links) fields[key] = MenzenConnectedImage(sent[key]);
	for (NSString *key in dates) fields[key] = [sent[key] isKindOfClass:NSNumber.class] ? sent[key] : nil;

	return fields;
}

static MenzenActivity *MenzenConnectedActivity(NSDictionary *info, NSString *appName) {
	MenzenActivity *activity = [MenzenActivity new];
	id kind = info[MenzenActivityKindKey];
	activity.kind = [kind isEqual:@"listening"] ? MenzenActivityKindListening : [kind isEqual:@"watching"] ? MenzenActivityKindWatching
																										   : MenzenActivityKindPlaying;
	activity.name = MenzenConnectedText(info[MenzenActivityNameKey]) ?: appName;
	activity.largeImageURL = MenzenConnectedImage(info[MenzenActivityImageURLKey]);
	activity.statusDisplay = MenzenStatusDisplayName;
	if (MenzenSettingBool(MenzenSettingPrivacy, NO)) return activity;

	activity.details = MenzenConnectedText(info[MenzenActivityDetailsKey]);
	activity.state = MenzenConnectedText(info[MenzenActivityStateKey]);
	id display = info[MenzenActivityStatusDisplayKey];
	if ([display isEqual:@"details"] && activity.details) activity.statusDisplay = MenzenStatusDisplayDetails;
	else if ([display isEqual:@"state"] && activity.state) activity.statusDisplay = MenzenStatusDisplayState;
	// Discord only shows these with a big picture.
	if (activity.largeImageURL) {
		activity.largeText = MenzenConnectedText(info[MenzenActivityLargeTextKey]);
		activity.smallImageURL = MenzenConnectedImage(info[MenzenActivitySmallImageURLKey]);
		if (activity.smallImageURL) activity.smallText = MenzenConnectedText(info[MenzenActivitySmallTextKey]);
	}

	activity.startDate = MenzenConnectedDate(info[MenzenActivityStartKey]);
	NSDate *end = MenzenConnectedDate(info[MenzenActivityEndKey]);
	if (activity.startDate && [end compare:activity.startDate] == NSOrderedDescending) activity.endDate = end;

	return activity;
}

@class MenzenConnectedSession;

@interface MenzenConnectedListener () <NSXPCListenerDelegate>
- (void)session:(MenzenConnectedSession *)session registerWithIdentifier:(NSString *)identifier name:(NSString *)name;
- (void)session:(MenzenConnectedSession *)session setActivity:(NSDictionary *)activity;
- (void)sessionEnded:(MenzenConnectedSession *)session;
@end

// XPC calls arrive on the connection's queue; the listener lives on the main
// queue.
@interface MenzenConnectedSession : NSObject <MenzenConnectedService>
@property (nonatomic, weak) MenzenConnectedListener *listener;
@property (nonatomic, weak) NSXPCConnection *connection;
@property (nonatomic, copy) NSString *process;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSDictionary *sentActivity;
@property (nonatomic) uint64_t sent;
@property (nonatomic) MenzenClientState state;
@end

@implementation MenzenConnectedSession

- (void)registerWithIdentifier:(NSString *)identifier name:(NSString *)name {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.listener session:self registerWithIdentifier:identifier name:name];
	});
}

- (void)setActivity:(NSDictionary *)activity {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.listener session:self setActivity:activity];
	});
}

@end

@implementation MenzenConnectedListener {
	MenzenPresence *_presence;
	NSXPCListener *_listener;
	NSMutableArray<MenzenConnectedSession *> *_sessions;
	uint64_t _sends;
	MenzenActivity *_shown;
	NSDictionary<NSString *, NSString *> *_approvals;
}

- (instancetype)initWithPresence:(MenzenPresence *)presence {
	if ((self = [super init])) {
		_presence = presence;
		_sessions = [NSMutableArray array];
	}

	return self;
}

- (void)start {
	_listener = [[NSXPCListener alloc] initWithMachServiceName:MenzenConnectedServiceName];
	_listener.delegate = self;
	[_listener resume];
}

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
	NSString *process = MenzenSigningIdentifier(connection.auditToken);
	if (!process) return NO;

	__block BOOL full;
	dispatch_sync(dispatch_get_main_queue(), ^{
		NSUInteger fromProcess = 0;

		for (MenzenConnectedSession *session in self->_sessions) {
			if ([session.process isEqualToString:process]) fromProcess++;
		}

		full = self->_sessions.count >= MenzenConnectedConnectionLimit || fromProcess >= MenzenConnectedProcessConnectionLimit;
	});

	if (full) return NO;

	MenzenConnectedSession *session = [MenzenConnectedSession new];
	session.listener = self;
	session.connection = connection;
	session.process = process;

	connection.exportedInterface = MenzenConnectedServiceInterface();
	connection.exportedObject = session;
	connection.remoteObjectInterface = MenzenConnectedClientInterface();

	__weak typeof(self) weakSelf = self;
	__weak MenzenConnectedSession *weakSession = session;
	connection.invalidationHandler = ^{
		dispatch_async(dispatch_get_main_queue(), ^{
			MenzenConnectedSession *ended = weakSession;
			if (ended) [weakSelf sessionEnded:ended];
		});
	};

	dispatch_sync(dispatch_get_main_queue(), ^{
		[self->_sessions addObject:session];
	});

	[connection resume];

	return YES;
}

// Before the first unlock the Keychain can't be read yet: nothing is allowed
// until it can.
- (NSDictionary<NSString *, NSString *> *)approvals {
	if (_approvals) return _approvals;

	OSStatus status;
	id saved = MenzenKeychainLoadItem(MenzenConnectedApprovalsAccount, &status);

	if (status == errSecItemNotFound) {
		_approvals = [self approvalsFromSettings];
		if (_approvals.count) MenzenKeychainSaveItem(MenzenConnectedApprovalsAccount, _approvals);

		return _approvals;
	}

	if (status != errSecSuccess) return @{};

	NSMutableDictionary *approvals = [NSMutableDictionary dictionary];

	if ([saved isKindOfClass:NSDictionary.class]) {
		[saved enumerateKeysAndObjectsUsingBlock:^(id identifier, id process, BOOL *stop) {
			if (MenzenConnectedIdentifierIsValid(identifier) && [process isKindOfClass:NSString.class] && [process length]) approvals[identifier] = process;
		}];
	}

	_approvals = approvals;

	return _approvals;
}

// Versions before the Keychain kept them in the settings.
- (NSDictionary<NSString *, NSString *> *)approvalsFromSettings {
	NSDictionary<NSString *, NSDictionary *> *apps = MenzenConnectedApps();
	NSMutableDictionary *approvals = [NSMutableDictionary dictionary];

	for (NSString *identifier in MenzenConnectedAllowed()) {
		id process = apps[identifier][MenzenConnectedAppProcessKey];
		if ([process isKindOfClass:NSString.class] && [process length]) approvals[identifier] = process;
	}

	return approvals;
}

- (BOOL)saveApprovals:(NSDictionary<NSString *, NSString *> *)approvals {
	OSStatus status = approvals.count ? MenzenKeychainSaveItem(MenzenConnectedApprovalsAccount, approvals) : MenzenKeychainDeleteItem(MenzenConnectedApprovalsAccount);
	if (status != errSecSuccess) return NO;

	_approvals = [approvals copy];
	MenzenWriteSetting(MenzenSettingConnectedAllowed, [approvals.allKeys sortedArrayUsingSelector:@selector(compare:)]);
	MenzenPostDarwinNotification(CFSTR(MenzenConnectedAppsChangedNotification));

	return YES;
}

- (void)setApp:(NSString *)identifier allowed:(BOOL)allowed {
	NSMutableDictionary *approvals = [self.approvals mutableCopy];

	if (allowed) {
		// The process connected now, else the one it was last time.
		NSString *process;

		for (MenzenConnectedSession *session in _sessions) {
			if ([session.identifier isEqualToString:identifier] && session.process) process = session.process;
		}

		id remembered = MenzenConnectedApps()[identifier][MenzenConnectedAppProcessKey];
		if (!process && [remembered isKindOfClass:NSString.class] && [remembered length]) process = remembered;
		if (!process) return;

		approvals[identifier] = process;
	} else {
		[approvals removeObjectForKey:identifier];
	}

	if ([approvals isEqualToDictionary:self.approvals] || ![self saveApprovals:approvals]) return;

	[self settingsChanged];
}

- (MenzenClientState)stateForSession:(MenzenConnectedSession *)session {
	if (!MenzenSettingBool(MenzenSettingEnabled, YES) || !MenzenSettingBool(MenzenSettingConnected, NO)) return MenzenClientStateOff;

	NSString *process = self.approvals[session.identifier];

	return process && [process isEqualToString:session.process] ? MenzenClientStateAllowed : MenzenClientStateNotAllowed;
}

- (void)session:(MenzenConnectedSession *)session registerWithIdentifier:(NSString *)identifier name:(NSString *)name {
	name = MenzenConnectedName(name);
	if (!MenzenConnectedIdentifierIsValid(identifier) || !name) return;
	// One app per connection, for as long as it lasts.
	if (session.identifier && ![session.identifier isEqualToString:identifier]) return;
	// Allowed for another process: this one can't take its place.
	NSString *approved = self.approvals[identifier];
	if (approved && ![approved isEqualToString:session.process]) return;
	if (![self rememberApp:identifier name:name process:session.process]) return;

	session.identifier = identifier;
	session.name = name;
	[self updateSession:session];
	[self askToAllowIfNeeded:session];
	[self showLatest];
}

- (void)askToAllowIfNeeded:(MenzenConnectedSession *)session {
	if (session.state != MenzenClientStateNotAllowed) return;

	NSMutableDictionary *apps = [MenzenConnectedApps() mutableCopy];
	NSMutableDictionary *app = [apps[session.identifier] mutableCopy];
	if (!app || [app[MenzenConnectedAppAskedKey] boolValue]) return;

	app[MenzenConnectedAppAskedKey] = @YES;
	apps[session.identifier] = app;
	MenzenWriteSetting(MenzenSettingConnectedApps, apps);
	[self askToAllow:session.identifier name:session.name];
}

- (void)askToAllow:(NSString *)identifier name:(NSString *)name {
	NSDate *now = NSDate.date;
	NSMutableArray *requests = [NSMutableArray array];
	NSArray *saved = MenzenSettingValue(MenzenSettingConnectedRequests);

	for (NSDictionary *request in [saved isKindOfClass:NSArray.class] ? saved : @[]) {
		NSDate *date = [request isKindOfClass:NSDictionary.class] ? request[MenzenConnectedRequestDateKey] : nil;
		if ([date isKindOfClass:NSDate.class] && -date.timeIntervalSinceNow < MenzenConnectedRequestAge) [requests addObject:request];
	}

	[requests addObject:@{MenzenConnectedRequestIdentifierKey: identifier, MenzenConnectedRequestNameKey: name, MenzenConnectedRequestDateKey: now}];
	MenzenWriteSetting(MenzenSettingConnectedRequests, requests);
	MenzenPostDarwinNotification(CFSTR(MenzenConnectedRequestNotification));
}

- (BOOL)rememberApp:(NSString *)identifier name:(NSString *)name process:(NSString *)process {
	NSMutableDictionary *apps = [MenzenConnectedApps() mutableCopy];
	NSMutableDictionary *app = [NSMutableDictionary dictionary];
	app[MenzenConnectedAppNameKey] = name;
	app[MenzenConnectedAppProcessKey] = process;
	app[MenzenConnectedAppAskedKey] = apps[identifier][MenzenConnectedAppAskedKey];
	if ([apps[identifier] isEqualToDictionary:app]) return YES;
	if (!apps[identifier] && apps.count >= MenzenConnectedAppLimit) return NO;

	apps[identifier] = app;
	MenzenWriteSetting(MenzenSettingConnectedApps, apps);
	MenzenPostDarwinNotification(CFSTR(MenzenConnectedAppsChangedNotification));

	return YES;
}

- (void)removeApp:(NSString *)identifier {
	NSMutableDictionary *approvals = [self.approvals mutableCopy];

	if (approvals[identifier]) {
		[approvals removeObjectForKey:identifier];
		if (![self saveApprovals:approvals]) return;
	}

	NSMutableDictionary *apps = [MenzenConnectedApps() mutableCopy];

	if (apps[identifier]) {
		[apps removeObjectForKey:identifier];
		MenzenWriteSetting(MenzenSettingConnectedApps, apps);
		MenzenPostDarwinNotification(CFSTR(MenzenConnectedAppsChangedNotification));
	}

	// Ending the connection would have the client register again right
	// away, so its connection stops counting as the app instead.
	for (MenzenConnectedSession *session in _sessions) {
		if (![session.identifier isEqualToString:identifier]) continue;

		[self updateSession:session];
		session.identifier = nil;
		session.name = nil;
		session.sentActivity = nil;
	}

	[self showLatest];
}

- (void)session:(MenzenConnectedSession *)session setActivity:(NSDictionary *)activity {
	if (!session.identifier) return;

	session.sentActivity = MenzenConnectedFields(activity);
	session.sent = ++_sends;
	[self showLatest];
}

- (void)sessionEnded:(MenzenConnectedSession *)session {
	[_sessions removeObject:session];
	[self showLatest];
}

- (void)updateSession:(MenzenConnectedSession *)session {
	MenzenClientState state = [self stateForSession:session];
	if (session.state == state) return;

	session.state = state;
	[[session.connection remoteObjectProxy] stateChanged:state];
}

- (void)showLatest {
	[self showLatestAgain:NO];
}

- (void)showLatestAgain:(BOOL)again {
	MenzenConnectedSession *latest;

	for (MenzenConnectedSession *session in _sessions) {
		if (session.state != MenzenClientStateAllowed || !session.sentActivity) continue;

		if (!latest || session.sent > latest.sent) latest = session;
	}

	MenzenActivity *activity = latest ? MenzenConnectedActivity(latest.sentActivity, latest.name) : nil;
	if (!again && (activity == _shown || [activity isEquivalentToActivity:_shown])) return;

	_shown = activity;
	[_presence setConnectedActivity:activity];
}

- (void)settingsChanged {
	for (MenzenConnectedSession *session in _sessions) {
		if (!session.identifier) continue;

		[self updateSession:session];
		[self askToAllowIfNeeded:session];
	}

	[self showLatestAgain:YES];
}

@end
