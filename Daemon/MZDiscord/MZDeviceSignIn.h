#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Discord's device authorization (RFC 8628), for devices whose WebKit can't
// run Discord's sign-in page: menzend gets a short code, the user approves it
// on another device at discord.com/activate, and menzend polls for the tokens.
// The device code is what polling proves itself with, so it never leaves this
// object. Everything runs on the main queue.
@interface MZDeviceSignIn : NSObject
- (instancetype)initWithApplicationId:(uint64_t)applicationId scopes:(NSString *)scopes;
// codeHandler runs once: the activate page with the code filled in and the
// code itself, or a message for the user. completion runs once the code is
// approved (tokens), declined or failed (a message) or expired (neither);
// never after cancel or another start.
- (void)startWithCodeHandler:(void (^)(NSURL *_Nullable verificationURL, NSString *_Nullable userCode, NSString *_Nullable error))codeHandler completion:(void (^)(NSString *_Nullable accessToken, NSString *_Nullable refreshToken, NSTimeInterval expiresIn, NSString *_Nullable error))completion;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
