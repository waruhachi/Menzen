#import <dlfcn.h>
#import <roothide.h>

#import "../Shared/MenzenConnectedApps.h"
#import "../Shared/MenzenService.h"
#import "Menzen.h"

// Sandboxed processes (App Store apps, most daemons) can't look the service
// up on their own; libSandy's profile lets them. Loaded rather than linked,
// so processes that don't need it work without it. Once per process.
static void MenzenApplySandyProfile(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		void *sandy = dlopen(jbroot("/usr/lib/libsandy.dylib"), RTLD_LAZY);
		if (!sandy) return;
		int (*applyProfile)(const char *) = dlsym(sandy, "libSandy_applyProfile");
		if (applyProfile) applyProfile(MenzenConnectedSandyProfile);
	});
}

static NSString *MenzenClientText(NSString *text) {
	text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (!text.length) return nil;
	if (text.length <= 128) return text;
	return [text substringToIndex:[text rangeOfComposedCharacterSequenceAtIndex:127].location];
}

@interface MenzenClientActivity ()
- (NSDictionary<NSString *, id> *)menzenDictionary;
@end

@implementation MenzenClientActivity

- (id)copyWithZone:(NSZone *)zone {
	MenzenClientActivity *copy = [MenzenClientActivity new];
	copy.type = self.type;
	copy.statusDisplay = self.statusDisplay;
	copy.name = self.name;
	copy.details = self.details;
	copy.state = self.state;
	copy.largeImageURL = self.largeImageURL;
	copy.largeText = self.largeText;
	copy.smallImageURL = self.smallImageURL;
	copy.smallText = self.smallText;
	copy.startDate = self.startDate;
	copy.endDate = self.endDate;
	return copy;
}

- (NSDictionary<NSString *, id> *)menzenDictionary {
	NSMutableDictionary *activity = [NSMutableDictionary dictionary];
	switch (self.type) {
		case MenzenClientActivityTypeListening: activity[MenzenActivityKindKey] = @"listening"; break;
		case MenzenClientActivityTypeWatching: activity[MenzenActivityKindKey] = @"watching"; break;
		default: activity[MenzenActivityKindKey] = @"playing"; break;
	}

	switch (self.statusDisplay) {
		case MenzenClientStatusDisplayDetails: activity[MenzenActivityStatusDisplayKey] = @"details"; break;
		case MenzenClientStatusDisplayState: activity[MenzenActivityStatusDisplayKey] = @"state"; break;
		default: activity[MenzenActivityStatusDisplayKey] = @"name"; break;
	}

	activity[MenzenActivityNameKey] = MenzenClientText(self.name);
	activity[MenzenActivityDetailsKey] = MenzenClientText(self.details);
	activity[MenzenActivityStateKey] = MenzenClientText(self.state);
	activity[MenzenActivityImageURLKey] = self.largeImageURL.absoluteString;
	activity[MenzenActivityLargeTextKey] = MenzenClientText(self.largeText);
	activity[MenzenActivitySmallImageURLKey] = self.smallImageURL.absoluteString;
	activity[MenzenActivitySmallTextKey] = MenzenClientText(self.smallText);
	if (self.startDate) activity[MenzenActivityStartKey] = @(self.startDate.timeIntervalSince1970);
	if (self.endDate) activity[MenzenActivityEndKey] = @(self.endDate.timeIntervalSince1970);
	return activity;
}

@end

// The connection keeps what it exports; this keeps the client weakly, so the
// client can still go away.
@interface MenzenClientReceiver : NSObject <MenzenConnectedClient>
@property (nonatomic, weak) MenzenClient *client;
@end

@interface MenzenClient ()
- (void)receiveState:(NSInteger)state;
@end

@implementation MenzenClientReceiver

- (void)stateChanged:(NSInteger)state {
	[self.client receiveState:state];
}

@end

@implementation MenzenClient {
	dispatch_queue_t _queue;
	NSXPCConnection *_connection;
	MenzenClientState _state;
	MenzenClientActivity *_activity;
	void (^_stateChangedHandler)(MenzenClientState state);
}

- (instancetype)initWithIdentifier:(NSString *)identifier name:(NSString *)name {
	name = MenzenConnectedName(name);
	if (!MenzenConnectedIdentifierIsValid(identifier) || !name || !(self = [super init])) return nil;
	_identifier = [identifier copy];
	_name = [name copy];
	_queue = dispatch_queue_create("moe.waru.menzen.client", DISPATCH_QUEUE_SERIAL);
	dispatch_async(_queue, ^{
		[self connect];
	});
	return self;
}

- (void)dealloc {
	[_connection invalidate];
}

// On the queue.
- (void)connect {
	MenzenApplySandyProfile();
	NSXPCConnection *connection = [[NSXPCConnection alloc] initWithMachServiceName:MenzenConnectedServiceName options:0];
	connection.remoteObjectInterface = MenzenConnectedServiceInterface();
	connection.exportedInterface = MenzenConnectedClientInterface();
	MenzenClientReceiver *receiver = [MenzenClientReceiver new];
	receiver.client = self;
	connection.exportedObject = receiver;

	__weak typeof(self) weakSelf = self;
	__weak NSXPCConnection *weakConnection = connection;
	// menzend restarted: the next message reaches the new one, which knows
	// nothing of this client yet.
	connection.interruptionHandler = ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		dispatch_async(strongSelf->_queue, ^{
			if (strongSelf->_connection != weakConnection) return;
			[strongSelf setStateOnQueue:MenzenClientStateUnavailable];
			[strongSelf sendAll];
		});
	};
	// Menzen isn't there, or this process may not reach it: try again with
	// the next activity.
	connection.invalidationHandler = ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		dispatch_async(strongSelf->_queue, ^{
			if (strongSelf->_connection != weakConnection) return;
			strongSelf->_connection = nil;
			[strongSelf setStateOnQueue:MenzenClientStateUnavailable];
		});
	};

	_connection = connection;
	[connection resume];
	[self sendAll];
}

// On the queue.
- (void)sendAll {
	id<MenzenConnectedService> service = _connection.remoteObjectProxy;
	[service registerWithIdentifier:_identifier name:_name];
	[service setActivity:[_activity menzenDictionary]];
}

- (void)receiveState:(NSInteger)state {
	dispatch_async(_queue, ^{
		[self setStateOnQueue:state >= MenzenClientStateUnavailable && state <= MenzenClientStateAllowed ? (MenzenClientState)state : MenzenClientStateUnavailable];
	});
}

// On the queue.
- (void)setStateOnQueue:(MenzenClientState)state {
	if (_state == state) return;
	_state = state;
	void (^handler)(MenzenClientState) = _stateChangedHandler;
	if (!handler) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		handler(state);
	});
}

- (MenzenClientState)state {
	__block MenzenClientState state;
	dispatch_sync(_queue, ^{
		state = _state;
	});
	return state;
}

- (void (^)(MenzenClientState))stateChangedHandler {
	__block void (^handler)(MenzenClientState);
	dispatch_sync(_queue, ^{
		handler = _stateChangedHandler;
	});
	return handler;
}

- (void)setStateChangedHandler:(void (^)(MenzenClientState))handler {
	handler = [handler copy];
	dispatch_async(_queue, ^{
		self->_stateChangedHandler = handler;
	});
}

- (MenzenClientActivity *)activity {
	__block MenzenClientActivity *activity;
	dispatch_sync(_queue, ^{
		activity = [_activity copy];
	});
	return activity;
}

- (void)setActivity:(MenzenClientActivity *)activity {
	activity = [activity copy];
	dispatch_async(_queue, ^{
		self->_activity = activity;
		if (!self->_connection) [self connect];
		else [self->_connection.remoteObjectProxy setActivity:[activity menzenDictionary]];
	});
}

@end
