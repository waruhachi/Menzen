#import <Preferences/PSSpecifier.h>

NS_ASSUME_NONNULL_BEGIN

// The app's home screen icon on its row. One that isn't installed gets
// iOS's blank app icon.
FOUNDATION_EXPORT void MenzenSetAppIcon(PSSpecifier *specifier, NSString *bundleIdentifier);

NS_ASSUME_NONNULL_END
