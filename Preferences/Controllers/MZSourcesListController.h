#import <Preferences/PSListController.h>

// The apps that show on the profile, each opening its page
// (MZSourceListController). Then the installed games, which need no
// provider: the one on screen shows. Each opens its page (MZGameListController).
@interface MZSourcesListController : PSListController
@end

// One app: its switch and how well Menzen supports it, from the specifier's
// "provider" property (Shared/MZProviders.h).
@interface MZSourceListController : PSListController
@end

// One game: its switch and whether Menzen's game list has its icon, with a
// way to request it, from the specifier's "game" property (MZGame*Key).
@interface MZGameListController : PSListController
@end

// The supported apps that aren't installed, from the specifier's "providers"
// property, with their logos.
@interface MZMoreAppsListController : PSListController
@end
