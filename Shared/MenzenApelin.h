#import <Foundation/Foundation.h>

// Apelin, an IDE installed by its jailbreak package, shows as a game. It
// isn't hooked: menzend reads the session files its agent writes.

#define MenzenApelinBundleIdentifier @"wiki.qaq.apelin"
// The key of its art asset on the Discord application.
#define MenzenApelinAsset @"apelin"

// BOOL, default YES: the open session's project name.
#define MenzenSettingApelinProject @"apelin.project"
// BOOL, default YES: what the agent is doing.
#define MenzenSettingApelinAgent @"apelin.agent"
