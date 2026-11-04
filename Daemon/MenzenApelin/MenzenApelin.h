#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MenzenApelinSession : NSObject
@property (nonatomic, copy, nullable) NSString *project;
// What the agent is doing; nil once it's done or stopped.
@property (nonatomic, copy, nullable) NSString *agent;
@end

// The session the agent wrote to last, nil when there is none.
FOUNDATION_EXPORT MenzenApelinSession *_Nullable MenzenReadApelinSession(void);

NS_ASSUME_NONNULL_END
