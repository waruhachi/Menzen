#import "../../Shared/MZThrottle.h"
#import "MZServiceClient.h"

NSNotificationName const MZStatusDidChangeNotification = @"MZStatusDidChangeNotification";

static NSTimeInterval const MZStatusInterval = 0.5;

static void MZForwardStatusChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	static MZThrottle throttle;
	dispatch_async(dispatch_get_main_queue(), ^{
		MZThrottleRun(&throttle, MZStatusInterval, ^{
			[NSNotificationCenter.defaultCenter postNotificationName:MZStatusDidChangeNotification object:nil];
		});
	});
}

static NSXPCConnection *MZConnection(void) {
	static NSXPCConnection *connection;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, MZForwardStatusChanged, CFSTR(MZStatusChangedNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	});
	if (!connection) {
		connection = [[NSXPCConnection alloc] initWithMachServiceName:MZServiceName options:0];
		connection.remoteObjectInterface = MZServiceInterface();
		connection.invalidationHandler = ^{
			dispatch_async(dispatch_get_main_queue(), ^{
				connection = nil;
			});
		};
		[connection resume];
	}

	return connection;
}

id<MZService> MZServiceProxy(void (^errorHandler)(void)) {
	return [MZConnection() remoteObjectProxyWithErrorHandler:^(NSError *error) {
		if (errorHandler) dispatch_async(dispatch_get_main_queue(), errorHandler);
	}];
}

void MZFetchStatus(void (^completion)(NSDictionary<NSString *, id> *status)) {
	[MZServiceProxy(^{
		completion(nil);
	}) statusWithReply:^(NSDictionary<NSString *, id> *status) {
		dispatch_async(dispatch_get_main_queue(), ^{
			completion(status);
		});
	}];
}
