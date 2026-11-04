#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The Discord tokens, as one Keychain item in an access group only menzend
// is entitled to. Readable after the first unlock, never synced or backed up
// to another device. Root can still read it: nothing on a jailbroken device
// is out of root's reach.
#define MenzenTokensAccessTokenKey @"accessToken"
#define MenzenTokensRefreshTokenKey @"refreshToken"
#define MenzenTokensExpiresAtKey @"expiresAt"

// nil on error too, such as errSecInteractionNotAllowed before the first
// unlock.
FOUNDATION_EXPORT NSDictionary *_Nullable MenzenKeychainLoadTokens(OSStatus *_Nullable status);
FOUNDATION_EXPORT OSStatus MenzenKeychainSaveTokens(NSDictionary *tokens);
FOUNDATION_EXPORT OSStatus MenzenKeychainDeleteTokens(void);

NS_ASSUME_NONNULL_END
