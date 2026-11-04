#import <Preferences/PSListController.h>

// The apps that show on the profile, each opening its page
// (MenzenSourceListController). Then the installed games, which need no
// provider: the one on screen shows. Each opens its page (MenzenGameListController).
@interface MenzenSourcesListController : PSListController
@end

// One app: its switch and how well Menzen supports it, from the specifier's
// "provider" property (Shared/MenzenProviders.h).
@interface MenzenSourceListController : PSListController
@end

// One game: its switch and whether Menzen's game list has its icon, with a
// way to request it, from the specifier's "game" property (MenzenGame*Key).
@interface MenzenGameListController : PSListController
@end

// The supported apps that aren't installed, from the specifier's "providers"
// property, with their logos.
@interface MenzenMoreAppsListController : PSListController
@end
