#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Menzen's lists of apps and their App Store icons: games.json, audio.json
// and video.json on the repository's catalog branch, which its workflows keep
// current (.github/scripts/catalog.py). Kept on disk, and checked again every
// few hours with their ETags, so most checks download nothing; only the
// installed and supported apps' entries are read from them. Main queue only.
@interface MZAppCatalog : NSObject
@property (nonatomic, copy, nullable) void (^changedHandler)(void);
- (void)start;
// Checks now unless it checked in the last few minutes: the settings pane
// shows the games, and may be back from requesting an icon.
- (void)checkIfStale;
// The app's default icon, 512 px on Apple's servers, or for a built-in game
// the key of its art asset; nil when the lists don't have it.
- (nullable NSString *)iconURLForApp:(NSString *)bundleIdentifier;
- (nullable NSString *)storeURLForApp:(NSString *)bundleIdentifier;
// In games.json, built in, or a game by its App Store category.
- (BOOL)isGame:(NSString *)bundleIdentifier;
- (NSArray<NSString *> *)installedGames;
// Each supported app's icon, installed or not.
- (NSDictionary<NSString *, NSString *> *)providerIcons;
@end

NS_ASSUME_NONNULL_END
