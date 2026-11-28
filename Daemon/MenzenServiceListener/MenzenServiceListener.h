#import <Foundation/Foundation.h>

@class MenzenAppChecker;
@class MenzenDiscord;
@class MenzenAppCatalog;

@interface MenzenServiceListener : NSObject
- (instancetype)initWithDiscord:(MenzenDiscord *)discord;
@property (nonatomic, copy) void (^refreshHandler)(void);
@property (nonatomic, copy) void (^setConnectedAppHandler)(NSString *identifier, BOOL allowed);
@property (nonatomic, copy) void (^removeConnectedAppHandler)(NSString *identifier);
@property (nonatomic, strong) MenzenAppChecker *appChecker;
@property (nonatomic, strong) MenzenAppCatalog *appCatalog;
- (void)start;
@end
