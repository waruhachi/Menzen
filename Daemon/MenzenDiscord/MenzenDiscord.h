#import <Foundation/Foundation.h>

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
@property (nonatomic, copy) NSString *name;
// A game has only its name.
@property (nonatomic, copy) NSString *details;
@property (nonatomic, copy) NSString *state;
// Public https URLs, which Discord's media proxy downloads, or the keys of
// the application's art assets (the app logos).
@property (nonatomic, copy) NSString *largeImageURL;
@property (nonatomic, copy) NSString *largeText;
// The artist's picture, in the corner of the large image.
@property (nonatomic, copy) NSString *smallImageURL;
@property (nonatomic, copy) NSString *smallText;
// Links on the details (track), state (artist), large image (album) and
// small image (artist).
@property (nonatomic, copy) NSString *detailsURL;
@property (nonatomic, copy) NSString *stateURL;
@property (nonatomic, copy) NSString *largeURL;
@property (nonatomic, copy) NSString *smallURL;
// [label, link] pairs.
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *buttons;
// "(2 of 4)" after the state; no party when the size is 0, no limit when the
// max is 0.
@property (nonatomic) NSInteger partySize;
@property (nonatomic) NSInteger partyMax;
@property (nonatomic, strong) NSDate *startDate;
@property (nonatomic, strong) NSDate *endDate;

- (BOOL)isEquivalentToActivity:(MenzenActivity *)activity;
@end

// Main queue only.
@interface MenzenDiscord : NSObject
@property (nonatomic, copy) void (^accountStatusChangedHandler)(void);
@property (nonatomic, readonly) NSDictionary<NSString *, id> *accountStatus;

- (instancetype)initWithApplicationId:(uint64_t)applicationId;
- (void)start;
// nil clears the activity.
- (void)setActivity:(MenzenActivity *)activity;
// For the settings' previews (MenzenStatusPreviewKey); pausedDate stops its
// progress bar there.
- (void)setPreviewActivity:(MenzenActivity *)activity pausedDate:(NSDate *)pausedDate;
// Sends the latest activity again shortly, even if Discord should already
// have it.
- (void)republish;

// OAuth authorization code flow with PKCE. The verifier stays here; only the
// authorize URL goes out, and only the redirect comes back.
- (NSURL *)beginSignIn;
- (void)finishSignInWithCallbackURL:(NSURL *)callbackURL completion:(void (^)(NSString *error))completion;
// Sign-in approved on another device (MenzenDeviceSignIn). Starting again drops
// the previous code. error is a message for the user; neither signedIn nor
// an error means the code expired.
- (void)beginDeviceSignInWithCodeHandler:(void (^)(NSURL *verificationURL, NSString *userCode, NSString *error))codeHandler completion:(void (^)(BOOL signedIn, NSString *error))completion;
- (void)cancelDeviceSignIn;
- (void)signOut;

- (void)refreshProfileIfStale;
- (void)refreshProfileWithCompletion:(void (^)(void))completion;
@end

// What Sign Out does, without a running daemon: deletes the stored tokens and
// revokes them, for when the package is removed. Waits at most timeout for
// Discord. NO if the tokens couldn't be deleted.
FOUNDATION_EXPORT BOOL MenzenSignOutStoredAccount(uint64_t applicationId, NSTimeInterval timeout);
