#import <Foundation/Foundation.h>

@class MenzenPresence;

@interface MenzenConnectedListener : NSObject
- (instancetype)initWithPresence:(MenzenPresence *)presence;
- (void)start;
- (void)settingsChanged;
// Its open connections stop counting as it, so it comes back once it connects
// again.
- (void)removeApp:(NSString *)identifier;
@end
