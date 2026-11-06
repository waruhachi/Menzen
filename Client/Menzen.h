// Menzen API: show an activity on the user's Discord profile from your own
// tweak or jailbreak app. See docs/API.md for setup and examples.
//
// Nothing shows until the user turns on Connected Apps in Menzen's settings
// and allows your app there. Your app appears in that list the first time it
// creates a MenzenClient.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define MENZEN_API_VERSION 1

// Whether what you send shows.
typedef NS_ENUM(NSInteger, MenzenClientState) {
	// Menzen isn't installed or can't be reached from this process yet.
	MenzenClientStateUnavailable = 0,
	// The user has Menzen or Connected Apps turned off.
	MenzenClientStateOff = 1,
	// Registered, but the user hasn't allowed your app (or has turned it off).
	MenzenClientStateNotAllowed = 2,
	// Your activity shows when nothing the user put first has one.
	MenzenClientStateAllowed = 3,
};

// The verb on the profile: "Playing <name>", "Listening to <name>",
// "Watching <name>".
typedef NS_ENUM(NSInteger, MenzenClientActivityType) {
	MenzenClientActivityTypePlaying = 0,
	MenzenClientActivityTypeListening = 1,
	MenzenClientActivityTypeWatching = 2,
};

// Which line shows next to the user's name in member lists.
typedef NS_ENUM(NSInteger, MenzenClientStatusDisplay) {
	MenzenClientStatusDisplayName = 0,
	MenzenClientStatusDisplayDetails = 1,
	MenzenClientStatusDisplayState = 2,
};

// What to show. Texts are trimmed and cut to 128 characters; empty ones are
// left out. Images must be public https links with nothing in them like a
// token or key, since everyone who sees the profile can open them. Discord
// shows the large text and the small image only with a large image.
//
// With Privacy Mode on, only the type, name and large image are shown.
@interface MenzenClientActivity : NSObject <NSCopying>
@property (nonatomic) MenzenClientActivityType type;
@property (nonatomic) MenzenClientStatusDisplay statusDisplay;
// The heading. Your app's name when nil.
@property (nonatomic, copy, nullable) NSString *name;
// The first and second lines.
@property (nonatomic, copy, nullable) NSString *details;
@property (nonatomic, copy, nullable) NSString *state;
@property (nonatomic, copy, nullable) NSURL *largeImageURL;
// Shown when the large image is hovered or tapped.
@property (nonatomic, copy, nullable) NSString *largeText;
// The badge in the corner of the large image.
@property (nonatomic, copy, nullable) NSURL *smallImageURL;
@property (nonatomic, copy, nullable) NSString *smallText;
// Time elapsed since startDate; with endDate too, a progress bar.
@property (nonatomic, strong, nullable) NSDate *startDate;
@property (nonatomic, strong, nullable) NSDate *endDate;
@end

// Your app's connection to Menzen. Keep it for as long as you want to show
// an activity: the activity is cleared when the client is deallocated or
// your process exits. Safe to use from any thread.
@interface MenzenClient : NSObject
// identifier: reverse DNS, unique to your app (com.example.mytweak), up to
// 128 letters, digits, dots, dashes and underscores. name: what the user sees
// in Menzen's settings, up to 64 characters. Returns nil if either isn't
// valid.
- (nullable instancetype)initWithIdentifier:(NSString *)identifier name:(NSString *)name NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) MenzenClientState state;
// Called on the main queue whenever state changes.
@property (nonatomic, copy, nullable) void (^stateChangedHandler)(MenzenClientState state);

// What to show; nil clears it. Kept and sent again if Menzen restarts, and
// sent even while not allowed, so it shows as soon as the user allows it.
@property (nonatomic, copy, nullable) MenzenClientActivity *activity;
@end

NS_ASSUME_NONNULL_END
