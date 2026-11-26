#import "MenzenDoNotDisturb.h"

@interface DNDState : NSObject
@property (nonatomic, readonly, getter=isActive) BOOL active;
@end

@interface DNDStateUpdate : NSObject
@property (nonatomic, readonly) DNDState *state;
@end

@protocol DNDStateUpdateListener <NSObject>
- (void)stateService:(id)stateService didReceiveDoNotDisturbStateUpdate:(DNDStateUpdate *)update;
@end

@interface DNDStateService : NSObject
+ (instancetype)serviceForClientIdentifier:(NSString *)clientIdentifier;
- (DNDState *)queryCurrentStateWithError:(NSError **)error;
- (BOOL)addStateUpdateListener:(id<DNDStateUpdateListener>)listener error:(NSError **)error;
@end

// Has to be in the entitlements' donotdisturb client identifiers.
static NSString *const MenzenDoNotDisturbClient = @"moe.waru.menzend";

@interface MenzenDoNotDisturb () <DNDStateUpdateListener>
@end

@implementation MenzenDoNotDisturb {
	void (^_handler)(BOOL);
	DNDStateService *_service;
}

- (instancetype)initWithHandler:(void (^)(BOOL))handler {
	if ((self = [super init])) _handler = [handler copy];
	return self;
}

- (void)start {
	_service = [DNDStateService serviceForClientIdentifier:MenzenDoNotDisturbClient];
	[_service addStateUpdateListener:self error:NULL];
	[self setActive:[_service queryCurrentStateWithError:NULL].active];
}

- (void)setActive:(BOOL)active {
	if (active == _active) return;
	_active = active;
	_handler(active);
}

- (void)stateService:(id)stateService didReceiveDoNotDisturbStateUpdate:(DNDStateUpdate *)update {
	BOOL active = update.state.active;
	dispatch_async(dispatch_get_main_queue(), ^{
		[self setActive:active];
	});
}

@end
