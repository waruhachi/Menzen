#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MZTrack : NSObject
// The app the user would recognise: the parent app when MediaRemote reports
// a helper process (Safari video comes from com.apple.WebKit.GPU).
@property (nonatomic, copy, nullable) NSString *bundleIdentifier;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *artist;
@property (nonatomic, copy, nullable) NSString *album;
@property (nonatomic, copy, nullable) NSString *artworkIdentifier;
@property (nonatomic, copy, nullable) NSString *contentIdentifier;
// Per-app providers put the cover's public URL here, or a menzen: extras
// URL (see Providers/ and Shared/MZTrackExtras.h).
@property (nonatomic, copy, nullable) NSString *assetURL;
// Apple Music's catalog IDs for the song, its album and its artist.
@property (nonatomic, copy, nullable) NSString *storeIdentifier;
@property (nonatomic, copy, nullable) NSString *albumStoreIdentifier;
@property (nonatomic, copy, nullable) NSString *artistStoreIdentifier;
// What the app says is playing: MRMediaRemoteMediaTypeMusic, ...Video and
// so on, or nil.
@property (nonatomic, copy, nullable) NSString *mediaType;
@property (nonatomic) NSTimeInterval duration;
// Elapsed time as of `timestamp`, advancing at `playbackRate`.
@property (nonatomic) NSTimeInterval elapsed;
@property (nonatomic, strong, nullable) NSDate *timestamp;
@property (nonatomic) double playbackRate;
@property (nonatomic) BOOL playing;

- (NSTimeInterval)elapsedAtDate:(NSDate *)date;
@end

// Watches MediaRemote and reports a new snapshot (nil when nothing is
// playing) after each burst of now playing notifications. Main queue only.
@interface MZNowPlaying : NSObject
- (instancetype)initWithHandler:(void (^)(MZTrack *_Nullable track))handler;
- (BOOL)start;
// Reads everything again and reports it, changed or not.
- (void)refresh;
@end

NS_ASSUME_NONNULL_END
