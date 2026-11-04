#import <UIKit/UIKit.h>

#import "../../Shared/MenzenProvider/MenzenProvider.h"

// The player (React Native) has the stream's URL, whose path has the
// channel's login; only the login is taken from it. The playing view owns
// the media session, or (on versions that don't set that) isn't paused and is
// on screen. Views the app moves aren't found that way, so for a live stream
// an ASCII display name is taken as the login.
//
// The preview's URL stays the same while the channel is live, so a timestamp
// keeps Discord from showing a stale copy.

@interface TwitchIVSPlayerView : UIView
@property (nonatomic, copy) NSString *streamUrl;
@property (nonatomic) BOOL ownsMediaSession;
@property (nonatomic) BOOL paused;
@end

static NSHashTable<TwitchIVSPlayerView *> *playerViews;

static NSString *MenzenValidLogin(NSString *name) {
	NSString *login = [name isKindOfClass:NSString.class] ? name.lowercaseString : nil;
	static NSCharacterSet *invalid;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		invalid = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_"].invertedSet;
	});
	return login.length && login.length <= 25 && [login rangeOfCharacterFromSet:invalid].location == NSNotFound ? login : nil;
}

static NSString *MenzenLogin(NSString *streamURL) {
	NSURL *url = [streamURL isKindOfClass:NSString.class] ? [NSURL URLWithString:streamURL] : nil;
	if (![url.host isEqualToString:@"usher.ttvnw.net"]) return nil;
	NSMutableArray<NSString *> *parts = [url.path.pathComponents mutableCopy];
	// "/", "api", ["v2",] "channel", "hls", "<login>.m3u8"
	if (parts.count == 6 && [parts[2] isEqualToString:@"v2"]) [parts removeObjectAtIndex:2];
	if (parts.count != 5 || ![parts[1] isEqualToString:@"api"] || ![parts[2] isEqualToString:@"channel"] || ![parts[3] isEqualToString:@"hls"] || ![parts[4].pathExtension isEqualToString:@"m3u8"]) return nil;
	return MenzenValidLogin(parts[4].stringByDeletingPathExtension);
}

static NSDictionary *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	if (withExtras[MPNowPlayingInfoPropertyAssetURL]) return nil;
	NSArray *views;
	@synchronized(playerViews) {
		views = playerViews.allObjects;
	}

	TwitchIVSPlayerView *playing;
	NSString *login;
	for (TwitchIVSPlayerView *view in views) {
		NSString *viewLogin = MenzenLogin(view.streamUrl);
		if (!viewLogin) continue;
		if (view.ownsMediaSession || (!playing && !view.paused && view.window)) {
			playing = view;
			login = viewLogin;
		}
		if (view.ownsMediaSession) break;
	}

	if (!playing && [info[MPNowPlayingInfoPropertyIsLiveStream] boolValue]) login = MenzenValidLogin(info[MPMediaItemPropertyArtist]);
	if (!login) return nil;
	static NSString *seenLogin;
	static long long seen;
	long long loaded;
	@synchronized(playerViews) {
		if (![login isEqualToString:seenLogin]) {
			seenLogin = login;
			seen = (long long)NSDate.date.timeIntervalSince1970;
		}
		loaded = seen;
	}

	NSString *page = [@"https://www.twitch.tv/" stringByAppendingString:login];
	return @{
		MenzenExtrasCoverKey: [NSString stringWithFormat:@"https://static-cdn.jtvnw.net/previews-ttv/live_user_%@-640x360.jpg?t=%lld", login, loaded],
		MenzenExtrasTitleURLKey: page,
		MenzenExtrasArtistURLKey: page,
	};
}

%hook TwitchIVSPlayerView

- (void)setStreamUrl:(NSString *)streamUrl {
	%orig;
	@synchronized(playerViews) {
		[playerViews addObject:self];
	}
}

%end

%ctor {
	playerViews = [NSHashTable weakObjectsHashTable];
	MenzenProviderCheck(@[@"TwitchIVSPlayerView -setStreamUrl:", @"TwitchIVSPlayerView -streamUrl", @"TwitchIVSPlayerView -paused"], @[@"TwitchIVSPlayerView -ownsMediaSession"]);
	MenzenAddExtras(MenzenExtras);
	%init;
}
