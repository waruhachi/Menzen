#import <Foundation/Foundation.h>

@interface MenzenTrack : NSObject
// The app the user would recognise: the parent app when MediaRemote reports
// a helper process (Safari video comes from com.apple.WebKit.GPU).
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, copy) NSString *artworkIdentifier;
@property (nonatomic, copy) NSString *contentIdentifier;
@property (nonatomic, copy) NSString *assetURL;
@property (nonatomic, copy) NSString *storeIdentifier;
@property (nonatomic, copy) NSString *albumStoreIdentifier;
@property (nonatomic, copy) NSString *artistStoreIdentifier;
@property (nonatomic, copy) NSString *mediaType;
@property (nonatomic) NSTimeInterval duration;
@property (nonatomic) NSTimeInterval elapsed;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic) double playbackRate;
@property (nonatomic) BOOL playing;

- (NSTimeInterval)elapsedAtDate:(NSDate *)date;
@end

@interface MenzenNowPlaying : NSObject
- (instancetype)initWithHandler:(void (^)(MenzenTrack *track))handler;
- (BOOL)start;
- (void)refresh;
@end
