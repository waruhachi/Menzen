#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MenzenActivityKind) {
	MenzenActivityKindListening,
	MenzenActivityKindWatching,
	MenzenActivityKindPlaying,
};

// Which line shows next to the name in member lists.
typedef NS_ENUM(NSInteger, MenzenStatusDisplay) {
	MenzenStatusDisplayDetails,
	MenzenStatusDisplayState,
	MenzenStatusDisplayName,
};

@interface MenzenActivity : NSObject <NSCopying>
@property (nonatomic) MenzenActivityKind kind;
@property (nonatomic) MenzenStatusDisplay statusDisplay;
// The app playing, for "Listening to <name>", or the game.
@property (nonatomic, copy, nullable) NSString *name;
// A game has only its name.
@property (nonatomic, copy, nullable) NSString *details;
@property (nonatomic, copy, nullable) NSString *state;
// Public https URLs, which Discord's media proxy downloads, or the keys of
// the application's art assets (the app logos).
@property (nonatomic, copy, nullable) NSString *largeImageURL;
@property (nonatomic, copy, nullable) NSString *largeText;
// The artist's picture, in the corner of the large image.
@property (nonatomic, copy, nullable) NSString *smallImageURL;
@property (nonatomic, copy, nullable) NSString *smallText;
// Links on the details (track), state (artist), large image (album) and
// small image (artist).
@property (nonatomic, copy, nullable) NSString *detailsURL;
@property (nonatomic, copy, nullable) NSString *stateURL;
@property (nonatomic, copy, nullable) NSString *largeURL;
@property (nonatomic, copy, nullable) NSString *smallURL;
@property (nonatomic, strong, nullable) NSDate *startDate;
@property (nonatomic, strong, nullable) NSDate *endDate;

- (BOOL)isEquivalentToActivity:(nullable MenzenActivity *)activity;
@end

// Owns the Social SDK client: signs in, keeps the OAuth tokens refreshed,
// connects, and publishes the latest activity once connected. Main queue only.
@interface MenzenDiscord : NSObject
@property (nonatomic, copy, nullable) void (^accountStatusChangedHandler)(void);
// MenzenService status: MenzenStatus*Key (Shared/MenzenService.h).
@property (nonatomic, readonly) NSDictionary<NSString *, id> *accountStatus;

- (instancetype)initWithApplicationId:(uint64_t)applicationId;
- (void)start;
// nil clears the activity.
- (void)setActivity:(nullable MenzenActivity *)activity;
// For the settings' previews (MenzenStatusPreviewKey); pausedDate stops its
// progress bar there.
- (void)setPreviewActivity:(nullable MenzenActivity *)activity pausedDate:(nullable NSDate *)pausedDate;
// Sends the latest activity again shortly, even if Discord should already
// have it.
- (void)republish;

// OAuth authorization code flow with PKCE. The verifier stays here; only the
// authorize URL goes out, and only the redirect comes back.
- (nullable NSURL *)beginSignIn;
- (void)finishSignInWithCallbackURL:(NSURL *)callbackURL completion:(void (^)(NSString *_Nullable error))completion;
// Sign-in approved on another device (MenzenDeviceSignIn). Starting again drops
// the previous code. error is a message for the user; neither signedIn nor
// an error means the code expired.
- (void)beginDeviceSignInWithCodeHandler:(void (^)(NSURL *_Nullable verificationURL, NSString *_Nullable userCode, NSString *_Nullable error))codeHandler completion:(void (^)(BOOL signedIn, NSString *_Nullable error))completion;
- (void)cancelDeviceSignIn;
- (void)signOut;

// Fetches the profile again if it's a few minutes old.
- (void)refreshProfileIfStale;
- (void)refreshProfileWithCompletion:(void (^)(void))completion;
@end

// What Sign Out does, without a running daemon: deletes the stored tokens and
// revokes them, for when the package is removed. Waits at most timeout for
// Discord. NO if the tokens couldn't be deleted.
FOUNDATION_EXPORT BOOL MenzenSignOutStoredAccount(uint64_t applicationId, NSTimeInterval timeout);

NS_ASSUME_NONNULL_END
