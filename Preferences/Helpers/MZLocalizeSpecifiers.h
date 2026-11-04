#import <Preferences/PSSpecifier.h>

// Specifiers from a plist carry their English text and, next to it, the
// key to look it up by: labelKey, footerTextKey, validTitlesKeys.
FOUNDATION_EXPORT void MZLocalizeSpecifiers(NSArray<PSSpecifier *> *specifiers);
