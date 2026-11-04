#import <Foundation/Foundation.h>

@class MenzenAppChecker;
@class MenzenDiscord;
@class MenzenAppCatalog;

NS_ASSUME_NONNULL_BEGIN

// Serves MenzenService (Shared/MenzenService.h) to the apps that host the settings
// pane, Settings and TweakSettings, and only to them: any other process is
// turned away.
@interface MenzenServiceListener : NSObject
- (instancetype)initWithDiscord:(MenzenDiscord *)discord;
// Runs on the main queue when the pane asks for a refresh, before the profile
// is fetched.
@property (nonatomic, copy, nullable) void (^refreshHandler)(void);
@property (nonatomic, strong, nullable) MenzenAppChecker *appChecker;
@property (nonatomic, strong, nullable) MenzenAppCatalog *appCatalog;
- (void)start;
@end

NS_ASSUME_NONNULL_END
