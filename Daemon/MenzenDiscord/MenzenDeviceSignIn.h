#import <Foundation/Foundation.h>

// For devices whose WebKit can't run Discord's sign-in page (RFC 8628). The
// device code is what polling proves itself with, so it never leaves this
// object.
@interface MenzenDeviceSignIn : NSObject
- (instancetype)initWithApplicationId:(uint64_t)applicationId scopes:(NSString *)scopes;
- (void)startWithCodeHandler:(void (^)(NSURL *verificationURL, NSString *userCode, NSString *error))codeHandler completion:(void (^)(NSString *accessToken, NSString *refreshToken, NSTimeInterval expiresIn, NSString *error))completion;
- (void)cancel;
@end
