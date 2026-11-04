#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// What the system says about an app, for the apps without a provider
// (Shared/MenzenProviders.h). Main queue only.

// The provider's name, else the name on the home screen.
FOUNDATION_EXPORT NSString *MenzenAppName(NSString *bundleIdentifier);
// What chat apps play is a voice message or a call, not something to show.
FOUNDATION_EXPORT BOOL MenzenIsChatApp(NSString *bundleIdentifier);
// Browsers play whatever page is open, which may be private.
FOUNDATION_EXPORT BOOL MenzenIsBrowserApp(NSString *bundleIdentifier);
// On the system's list of video streaming apps (like Peacock or Sling), or in
// a video App Store category.
FOUNDATION_EXPORT BOOL MenzenIsVideoApp(NSString *bundleIdentifier);
// In the Games App Store category or one of its subcategories.
FOUNDATION_EXPORT BOOL MenzenIsGameApp(NSString *bundleIdentifier);

NS_ASSUME_NONNULL_END
