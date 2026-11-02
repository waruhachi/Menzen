#import <Foundation/Foundation.h>

// Any process can post a Darwin notification, so what one starts runs at
// most once per interval. A post while a run is waiting is folded into it,
// so the last change is never lost. Main queue only.

typedef struct {
	BOOL pending;
	CFAbsoluteTime last;
} MZThrottle;

static inline void MZThrottleRun(MZThrottle *throttle, NSTimeInterval interval, dispatch_block_t block) {
	if (throttle->pending) return;
	throttle->pending = YES;
	NSTimeInterval wait = MAX(0, throttle->last + interval - CFAbsoluteTimeGetCurrent());
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		throttle->pending = NO;
		throttle->last = CFAbsoluteTimeGetCurrent();
		block();
	});
}
