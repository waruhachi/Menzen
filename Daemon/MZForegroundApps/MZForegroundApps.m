#import <dlfcn.h>

#import "MZForegroundApps.h"

// Unchanged from iOS 14 through 26.
@interface RBSProcessPredicate : NSObject
+ (instancetype)predicateMatchingLaunchServicesProcesses;
@end

@interface RBSProcessStateDescriptor : NSObject
+ (instancetype)descriptor;
@property (nonatomic) NSUInteger values;
@property (nonatomic, copy) NSArray<NSString *> *endowmentNamespaces;
@end

@interface RBSProcessIdentity : NSObject
@property (nonatomic, readonly) BOOL isApplication;
@property (nonatomic, readonly, nullable) NSString *embeddedApplicationIdentifier;
@end

@interface RBSProcessHandle : NSObject
@property (nonatomic, readonly) RBSProcessIdentity *identity;
@end

@interface RBSProcessState : NSObject
@property (nonatomic, readonly) NSSet<NSString *> *endowmentNamespaces;
@end

@interface RBSProcessStateUpdate : NSObject
@property (nonatomic, readonly, nullable) RBSProcessState *state;
@end

@protocol MZProcessMonitorConfiguring
- (void)setPredicates:(NSArray<RBSProcessPredicate *> *)predicates;
- (void)setStateDescriptor:(RBSProcessStateDescriptor *)descriptor;
- (void)setUpdateHandler:(void (^)(id monitor, RBSProcessHandle *process, RBSProcessStateUpdate *update))handler;
@end

@interface RBSProcessMonitor : NSObject
+ (instancetype)monitorWithConfiguration:(void (^)(id<MZProcessMonitorConfiguring> configuration))block;
- (void)invalidate;
@end

static NSString *const MZVisibilityEndowment = @"com.apple.frontboard.visibility";
// RBSProcessStateValueTaskState: the endowments come with the task state.
static NSUInteger const MZTaskStateValue = 1;

@implementation MZForegroundApps {
	void (^_handler)(NSArray<NSString *> *);
	RBSProcessMonitor *_monitor;
	NSMutableArray<NSString *> *_visible;
}

- (instancetype)initWithHandler:(void (^)(NSArray<NSString *> *))handler {
	if ((self = [super init])) {
		_handler = [handler copy];
		_visible = [NSMutableArray array];
	}

	return self;
}

- (BOOL)start {
	dlopen("/System/Library/PrivateFrameworks/RunningBoardServices.framework/RunningBoardServices", RTLD_LAZY);
	Class monitorClass = NSClassFromString(@"RBSProcessMonitor");
	Class predicateClass = NSClassFromString(@"RBSProcessPredicate");
	Class descriptorClass = NSClassFromString(@"RBSProcessStateDescriptor");
	if (![monitorClass respondsToSelector:@selector(monitorWithConfiguration:)] || ![predicateClass respondsToSelector:@selector(predicateMatchingLaunchServicesProcesses)] || ![descriptorClass respondsToSelector:@selector(descriptor)]) return NO;

	__weak typeof(self) weakSelf = self;
	_monitor = [monitorClass monitorWithConfiguration:^(id<MZProcessMonitorConfiguring> configuration) {
		[configuration setPredicates:@[[predicateClass predicateMatchingLaunchServicesProcesses]]];
		RBSProcessStateDescriptor *descriptor = [descriptorClass descriptor];
		descriptor.values = MZTaskStateValue;
		descriptor.endowmentNamespaces = @[MZVisibilityEndowment];
		[configuration setStateDescriptor:descriptor];
		// Runs on RunningBoard's queue.
		[configuration setUpdateHandler:^(id monitor, RBSProcessHandle *process, RBSProcessStateUpdate *update) {
			RBSProcessIdentity *identity = process.identity;
			// Widgets and other extensions have an identity too.
			if (!identity.isApplication) return;
			NSString *bundleIdentifier = identity.embeddedApplicationIdentifier;
			if (!bundleIdentifier.length) return;
			BOOL visible = [update.state.endowmentNamespaces containsObject:MZVisibilityEndowment];
			dispatch_async(dispatch_get_main_queue(), ^{
				[weakSelf app:bundleIdentifier visible:visible];
			});
		}];
	}];
	return _monitor != nil;
}

- (void)app:(NSString *)bundleIdentifier visible:(BOOL)visible {
	NSUInteger index = [_visible indexOfObject:bundleIdentifier];
	if (visible == (index != NSNotFound)) return;
	if (visible) [_visible insertObject:bundleIdentifier atIndex:0];
	else [_visible removeObjectAtIndex:index];
	_handler([_visible copy]);
}

- (void)dealloc {
	[_monitor invalidate];
}

@end
