#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The Discord tokens, as one Keychain item in an access group only menzend
// is entitled to. Readable after the first unlock, never synced or backed up
// to another device. Root can still read it: nothing on a jailbroken device
// is out of root's reach.
#define MZTokensAccessTokenKey @"accessToken"
#define MZTokensRefreshTokenKey @"refreshToken"
#define MZTokensExpiresAtKey @"expiresAt"

// nil on error too, such as errSecInteractionNotAllowed before the first
// unlock.
FOUNDATION_EXPORT NSDictionary *_Nullable MZKeychainLoadTokens(OSStatus *_Nullable status);
FOUNDATION_EXPORT OSStatus MZKeychainSaveTokens(NSDictionary *tokens);
FOUNDATION_EXPORT OSStatus MZKeychainDeleteTokens(void);

NS_ASSUME_NONNULL_END
