#import <Foundation/Foundation.h>

// Checked with their ETags, so most checks download nothing.
@interface MenzenAppCatalog : NSObject
@property (nonatomic, copy) void (^changedHandler)(void);
- (void)start;
// Checks now unless it checked in the last few minutes: the settings pane
// shows the games, and may be back from requesting an icon.
- (void)checkIfStale;
- (NSString *)iconURLForApp:(NSString *)bundleIdentifier;
- (NSString *)storeURLForApp:(NSString *)bundleIdentifier;
- (BOOL)isGame:(NSString *)bundleIdentifier;
- (NSArray<NSString *> *)installedGames;
- (NSDictionary<NSString *, NSString *> *)providerIcons;
@end
