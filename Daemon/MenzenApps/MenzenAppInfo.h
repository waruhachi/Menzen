#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *MenzenAppName(NSString *bundleIdentifier);
// What chat apps play is a voice message or a call, not something to show.
FOUNDATION_EXPORT BOOL MenzenIsChatApp(NSString *bundleIdentifier);
// Browsers play whatever page is open, which may be private.
FOUNDATION_EXPORT BOOL MenzenIsBrowserApp(NSString *bundleIdentifier);
FOUNDATION_EXPORT BOOL MenzenIsVideoApp(NSString *bundleIdentifier);
FOUNDATION_EXPORT BOOL MenzenIsGameApp(NSString *bundleIdentifier);
