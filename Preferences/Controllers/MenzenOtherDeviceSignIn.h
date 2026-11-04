#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Sign-in for when Discord's page won't run here (older WebKit): menzend gets
// a code from Discord, shown here as a QR code and as text, the user approves
// it on another device, and menzend finishes on its own.
@interface MenzenOtherDeviceSignInController : UIViewController
// Runs once the sheet closes, signed in or cancelled.
@property (nonatomic, copy, nullable) void (^completion)(void);
@end

NS_ASSUME_NONNULL_END
