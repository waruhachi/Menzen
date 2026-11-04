#import "../../Shared/MenzenThrottle.h"
#import "MenzenServiceClient.h"

NSNotificationName const MenzenStatusDidChangeNotification = @"MenzenStatusDidChangeNotification";

static NSTimeInterval const MenzenStatusInterval = 0.5;

static void MenzenForwardStatusChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	static MenzenThrottle throttle;
	dispatch_async(dispatch_get_main_queue(), ^{
		MenzenThrottleRun(&throttle, MenzenStatusInterval, ^{
			[NSNotificationCenter.defaultCenter postNotificationName:MenzenStatusDidChangeNotification object:nil];
		});
	});
}

static NSXPCConnection *MenzenConnection(void) {
	static NSXPCConnection *connection;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, MenzenForwardStatusChanged, CFSTR(MenzenStatusChangedNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	});
	if (!connection) {
		connection = [[NSXPCConnection alloc] initWithMachServiceName:MenzenServiceName options:0];
		connection.remoteObjectInterface = MenzenServiceInterface();
		connection.invalidationHandler = ^{
			dispatch_async(dispatch_get_main_queue(), ^{
				connection = nil;
			});
		};
		[connection resume];
	}

	return connection;
}

id<MenzenService> MenzenServiceProxy(void (^errorHandler)(void)) {
	return [MenzenConnection() remoteObjectProxyWithErrorHandler:^(NSError *error) {
		if (errorHandler) dispatch_async(dispatch_get_main_queue(), errorHandler);
	}];
}

void MenzenFetchStatus(void (^completion)(NSDictionary<NSString *, id> *status)) {
	[MenzenServiceProxy(^{
		completion(nil);
	}) statusWithReply:^(NSDictionary<NSString *, id> *status) {
		dispatch_async(dispatch_get_main_queue(), ^{
			completion(status);
		});
	}];
}
