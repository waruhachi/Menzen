#import <Foundation/Foundation.h>

@class MZAppChecker;
@class MZDiscord;
@class MZAppCatalog;

NS_ASSUME_NONNULL_BEGIN

// Serves MZService (Shared/MZService.h) to the apps that host the settings
// pane, Settings and TweakSettings, and only to them: any other process is
// turned away.
@interface MZServiceListener : NSObject
- (instancetype)initWithDiscord:(MZDiscord *)discord;
// Runs on the main queue when the pane asks for a refresh, before the profile
// is fetched.
@property (nonatomic, copy, nullable) void (^refreshHandler)(void);
@property (nonatomic, strong, nullable) MZAppChecker *appChecker;
@property (nonatomic, strong, nullable) MZAppCatalog *appCatalog;
- (void)start;
@end

NS_ASSUME_NONNULL_END
