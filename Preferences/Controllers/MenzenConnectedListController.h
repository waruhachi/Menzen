#import <Preferences/PSListController.h>

// Connected Apps (Shared/MenzenConnectedApps.h): the switch for all of them,
// and each app that has registered, opening its page
// (MenzenConnectedAppListController).
@interface MenzenConnectedListController : PSListController
@end

// One Connected App, from the specifier's "connectedApp" property: its switch,
// off until the user allows it, and a button that removes it.
@interface MenzenConnectedAppListController : PSListController
@end
