#import "../../Client/Menzen.h"
#import "../../Shared/MenzenConnectedApps.h"
#import "../../Shared/MenzenCustomActivity.h"
#import "../../Shared/MenzenService.h"
#import "../MenzenDiscord/MenzenDiscord.h"
#import "../MenzenPresence/MenzenPresence.h"
#import "MenzenConnectedListener.h"

// Private, but present on iOS.
@interface NSXPCConnection (MenzenConnectedAuditToken)
@property (nonatomic, readonly) audit_token_t auditToken;
@end

typedef struct __SecTask *SecTaskRef;
extern SecTaskRef SecTaskCreateWithAuditToken(CFAllocatorRef allocator, audit_token_t token);
extern CFStringRef SecTaskCopySigningIdentifier(SecTaskRef task, CFErrorRef *error);

// More at once than any device runs; the rest are turned away.
static NSUInteger const MenzenConnectedConnectionLimit = 64;
static NSUInteger const MenzenConnectedTextLimit = 128;
static NSUInteger const MenzenConnectedURLLimit = 512;

static NSString *MenzenConnectedProcess(NSXPCConnection *connection) {
	SecTaskRef task = SecTaskCreateWithAuditToken(kCFAllocatorDefault, connection.auditToken);
	if (!task) return nil;
	NSString *identifier = CFBridgingRelease(SecTaskCopySigningIdentifier(task, NULL));
	CFRelease(task);
	return identifier;
}

static NSString *MenzenConnectedText(id text) {
	if (![text isKindOfClass:NSString.class]) return nil;
	text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (![text length]) return nil;
	if ([text length] <= MenzenConnectedTextLimit) return text;
	return [text substringToIndex:[text rangeOfComposedCharacterSequenceAtIndex:MenzenConnectedTextLimit - 1].location];
}

static NSString *MenzenConnectedImage(id url) {
	if (![url isKindOfClass:NSString.class] || [url length] > MenzenConnectedURLLimit) return nil;
	return MenzenCustomImageURLIsAllowed(url) ? url : nil;
}

static NSDate *MenzenConnectedDate(id seconds) {
	if (![seconds isKindOfClass:NSNumber.class] || [seconds doubleValue] <= 0) return nil;
	return [NSDate dateWithTimeIntervalSince1970:[seconds doubleValue]];
}

// What a client sent, checked the way custom activities are
// (-[MenzenPresence customActivity]).
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

// One client connection. XPC calls arrive on the connection's queue and are
// handed to the listener on the main queue.
@interface MenzenConnectedSession : NSObject <MenzenConnectedService>
@property (nonatomic, weak) MenzenConnectedListener *listener;
@property (nonatomic, weak) NSXPCConnection *connection;
@property (nonatomic, copy) NSString *process;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSDictionary *sentActivity;
// When the activity was last sent, in sends since menzend started.
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

// On the listener's queue.
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
	__block BOOL full;
	dispatch_sync(dispatch_get_main_queue(), ^{
		full = self->_sessions.count >= MenzenConnectedConnectionLimit;
	});
	if (full) return NO;

	MenzenConnectedSession *session = [MenzenConnectedSession new];
	session.listener = self;
	session.connection = connection;
	session.process = MenzenConnectedProcess(connection);
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

- (MenzenClientState)stateForIdentifier:(NSString *)identifier {
	if (!MenzenSettingBool(MenzenSettingEnabled, YES) || !MenzenSettingBool(MenzenSettingConnected, NO)) return MenzenClientStateOff;
	return [MenzenConnectedAllowed() containsObject:identifier] ? MenzenClientStateAllowed : MenzenClientStateNotAllowed;
}

- (void)session:(MenzenConnectedSession *)session registerWithIdentifier:(NSString *)identifier name:(NSString *)name {
	name = MenzenConnectedName(name);
	if (!MenzenConnectedIdentifierIsValid(identifier) || !name) return;
	// One app per connection, for as long as it lasts.
	if (session.identifier && ![session.identifier isEqualToString:identifier]) return;
	if (![self rememberApp:identifier name:name process:session.process]) return;
	session.identifier = identifier;
	session.name = name;
	[self updateSession:session];
	[self showLatest];
}

// Lists the app in the settings. NO when there's no room for another.
- (BOOL)rememberApp:(NSString *)identifier name:(NSString *)name process:(NSString *)process {
	NSMutableDictionary *apps = [MenzenConnectedApps() mutableCopy];
	NSMutableDictionary *app = [NSMutableDictionary dictionary];
	app[MenzenConnectedAppNameKey] = name;
	app[MenzenConnectedAppProcessKey] = process;
	if ([apps[identifier] isEqualToDictionary:app]) return YES;
	if (!apps[identifier] && apps.count >= MenzenConnectedAppLimit) return NO;
	apps[identifier] = app;
	CFPreferencesSetAppValue((__bridge CFStringRef)MenzenSettingConnectedApps, (__bridge CFDictionaryRef)apps, (__bridge CFStringRef)MenzenSettingsDomain);
	CFPreferencesAppSynchronize((__bridge CFStringRef)MenzenSettingsDomain);
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(MenzenConnectedAppsChangedNotification), NULL, NULL, YES);
	return YES;
}

- (void)session:(MenzenConnectedSession *)session setActivity:(NSDictionary *)activity {
	if (!session.identifier) return;
	session.sentActivity = [activity isKindOfClass:NSDictionary.class] ? activity : nil;
	session.sent = ++_sends;
	[self showLatest];
}

- (void)sessionEnded:(MenzenConnectedSession *)session {
	[_sessions removeObject:session];
	[self showLatest];
}

// Tells the client when whether it shows has changed.
- (void)updateSession:(MenzenConnectedSession *)session {
	MenzenClientState state = [self stateForIdentifier:session.identifier];
	if (session.state == state) return;
	session.state = state;
	[[session.connection remoteObjectProxy] stateChanged:state];
}

- (void)showLatest {
	[self showLatestAgain:NO];
}

// again: even if it's the same activity as before, which shows differently
// when the settings change.
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
		if (session.identifier) [self updateSession:session];
	}

	[self showLatestAgain:YES];
}

@end
