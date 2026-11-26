#import <Foundation/Foundation.h>

// Whether Do Not Disturb or any Focus is on. Main queue only.
@interface MenzenDoNotDisturb : NSObject
@property (nonatomic, readonly, getter=isActive) BOOL active;
- (instancetype)initWithHandler:(void (^)(BOOL active))handler;
- (void)start;
@end
