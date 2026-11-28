#import <Foundation/Foundation.h>

// Keychain items in an access group only menzend is entitled to, such as the
// Discord tokens. Readable after the first unlock, never synced or backed up
// to another device. Root can still read them: nothing on a jailbroken device
// is out of root's reach.
#define MenzenTokensAccessTokenKey @"accessToken"
#define MenzenTokensRefreshTokenKey @"refreshToken"
#define MenzenTokensExpiresAtKey @"expiresAt"

// nil on error too, such as errSecInteractionNotAllowed before the first
// unlock.
FOUNDATION_EXPORT NSDictionary *MenzenKeychainLoadTokens(OSStatus *status);
FOUNDATION_EXPORT OSStatus MenzenKeychainSaveTokens(NSDictionary *tokens);
FOUNDATION_EXPORT OSStatus MenzenKeychainDeleteTokens(void);

// Any property list. nil when there's none or it can't be read yet.
FOUNDATION_EXPORT id MenzenKeychainLoadItem(NSString *account, OSStatus *status);
FOUNDATION_EXPORT OSStatus MenzenKeychainSaveItem(NSString *account, id value);
FOUNDATION_EXPORT OSStatus MenzenKeychainDeleteItem(NSString *account);
