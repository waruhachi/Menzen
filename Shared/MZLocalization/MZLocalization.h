#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Text people see, from <jbroot>/Library/Tweak Support/Menzen/Localization/
// <language>.lproj/Localizable.strings. The fallback is the English text,
// used when no language has the key.
FOUNDATION_EXPORT NSString *MZLocalizedString(NSString *key, NSString *fallback);

NS_ASSUME_NONNULL_END
