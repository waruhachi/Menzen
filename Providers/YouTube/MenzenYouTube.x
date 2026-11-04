
#import "../../Shared/MenzenProvider/MenzenProvider.h"

// Without Premium, YouTube publishes nothing, so this publishes from the
// player; with it, only the extras are added.
//
// YouTube Music uses the same player. The player doesn't know the artist or
// album, but the queue's renderer does (the byline, and the menu's "Go to
// album"). The artist's picture is on their page, asked for through the
// app's browse service as the app does when the artist is tapped.

@interface YTIThumbnailDetails_Thumbnail : NSObject
@property (nonatomic, readonly) NSString *URL;
@property (nonatomic, readonly) unsigned width;
@end

@interface YTIThumbnailDetails : NSObject
@property (nonatomic, readonly) NSArray<YTIThumbnailDetails_Thumbnail *> *thumbnailsArray;
@end

@interface YTIVideoDetails : NSObject
@property (nonatomic, readonly) NSString *videoId;
@property (nonatomic, readonly) NSString *title;
@property (nonatomic, readonly) NSString *author;
@property (nonatomic, readonly) NSString *channelId;
@property (nonatomic, readonly) unsigned long long lengthSeconds;
@property (nonatomic, readonly) BOOL isLive;
@property (nonatomic, readonly) BOOL isCrawlable;
@property (nonatomic, readonly) BOOL isPrivate;
@property (nonatomic, readonly) YTIThumbnailDetails *thumbnail;
@end

@interface YTIPlayerResponse : NSObject
@property (nonatomic, readonly) YTIVideoDetails *videoDetails;
@end

@interface YTPlayerResponse : NSObject
@property (nonatomic, readonly) YTIPlayerResponse *playerData;
@end

@interface YTPlaybackData : NSObject
- (YTPlayerResponse *)playerResponse;
@end

@interface YTSingleVideo : NSObject
- (YTPlaybackData *)playbackData;
@end

@interface YTIBrowseEndpoint : NSObject
@property (nonatomic, readonly) NSString *browseId;
@end

@interface YTICommand : NSObject
- (BOOL)hasBrowseEndpoint;
@property (nonatomic, readonly) YTIBrowseEndpoint *browseEndpoint;
@end

@interface YTIFormattedStringRun : NSObject
@property (nonatomic, readonly) NSString *text;
- (BOOL)hasNavigationEndpoint;
@property (nonatomic, readonly) YTICommand *navigationEndpoint;
@end

@interface YTIFormattedString : NSObject
@property (nonatomic, readonly) NSArray<YTIFormattedStringRun *> *runsArray;
@end

@interface YTIMenuNavigationItemRenderer : NSObject
- (BOOL)hasNavigationEndpoint;
@property (nonatomic, readonly) YTICommand *navigationEndpoint;
@end

@interface YTIMenuItemSupportedRenderers : NSObject
- (BOOL)hasMenuNavigationItemRenderer;
@property (nonatomic, readonly) YTIMenuNavigationItemRenderer *menuNavigationItemRenderer;
@end

@interface YTIMenuRenderer : NSObject
@property (nonatomic, readonly) NSArray<YTIMenuItemSupportedRenderers *> *itemsArray;
@end

@interface YTIMenuSupportedRenderers : NSObject
@property (nonatomic, readonly) YTIMenuRenderer *menuRenderer;
@end

@interface YTIPlaylistPanelVideoRenderer : NSObject
@property (nonatomic, readonly) NSString *videoId;
@property (nonatomic, readonly) YTIFormattedString *shortBylineText;
@property (nonatomic, readonly) YTIThumbnailDetails *thumbnail;
@property (nonatomic, readonly) YTIMenuSupportedRenderers *menu;
@end

@interface YTIBrowseRequest : NSObject
+ (instancetype)message;
@property (nonatomic, copy) NSString *browseId;
@end

@interface YTIBrowseResponse : NSObject
// A YTIBrowseHeaderSupportedRenderers; for an artist, an element (EML)
// renderer whose data has the picture's URL.
- (id)header;
@end

@interface YTBrowseServiceImpl : NSObject
- (void)makeRequest:(YTIBrowseRequest *)request refresh:(BOOL)refresh responseBlock:(void (^)(id response))responseBlock errorBlock:(void (^)(NSError *error))errorBlock;
@end

// A song with a music video has a renderer for each.
@interface YTQueueItem : NSObject
- (YTIPlaylistPanelVideoRenderer *)videoRenderer;
- (YTIPlaylistPanelVideoRenderer *)audioModeRenderer;
- (YTIPlaylistPanelVideoRenderer *)videoModeRenderer;
@end

@interface YTSingleVideoController : NSObject
- (YTSingleVideo *)singleVideo;
- (YTSingleVideo *)videoData;
- (NSInteger)mediaState;
- (BOOL)isMuted;
@end

@interface YTPlayerViewController : UIViewController
- (NSString *)contentVideoID;
- (YTPlayerResponse *)contentPlayerResponse;
- (double)contentVideoMediaTime;
- (YTSingleVideoController *)activeVideo;
- (BOOL)isPlayingAd;
@end

static NSInteger const MenzenMediaStatePlaying = 3;

static __weak YTPlayerViewController *player;
// Premium: YouTube publishes the info itself.
static BOOL appPublishes;
static BOOL publishing;
static BOOL music;
static NSHashTable<YTQueueItem *> *queueItems;
// Main thread only, except artistPictures, which is guarded by itself.
// NSNull for an artist without a picture.
static __weak YTBrowseServiceImpl *browseService;
static NSMutableDictionary<NSString *, id> *artistPictures;
static NSMutableSet<NSString *> *artistPicturesLoading;
// Video ID to whether it's public, from the player's details.
static MenzenCache<NSString *, NSNumber *> *publicVideos;

static YTIVideoDetails *MenzenDetails(YTPlayerResponse *response) {
	YTIPlayerResponse *data = [response respondsToSelector:@selector(playerData)] ? response.playerData : nil;
	YTIVideoDetails *details = [data respondsToSelector:@selector(videoDetails)] ? data.videoDetails : nil;
	return [details respondsToSelector:@selector(title)] && [details respondsToSelector:@selector(author)] ? details : nil;
}

// Older versions (YouTube 20.38.3, YouTube Music 9.09.3) have no
// contentPlayerResponse. The active video can be an ad, so its response only
// counts when it is the content video.
static YTPlayerResponse *MenzenActiveVideoResponse(YTPlayerViewController *controller) {
	YTSingleVideoController *active = [controller respondsToSelector:@selector(activeVideo)] ? controller.activeVideo : nil;
	YTSingleVideo *video = nil;
	if ([active respondsToSelector:@selector(singleVideo)]) video = active.singleVideo;
	else if ([active respondsToSelector:@selector(videoData)]) video = active.videoData;
	YTPlaybackData *playback = [video respondsToSelector:@selector(playbackData)] ? video.playbackData : nil;
	YTPlayerResponse *response = [playback respondsToSelector:@selector(playerResponse)] ? playback.playerResponse : nil;

	YTIVideoDetails *details = MenzenDetails(response);
	NSString *contentID = [controller respondsToSelector:@selector(contentVideoID)] ? controller.contentVideoID : nil;
	BOOL isContent = [details respondsToSelector:@selector(videoId)] && contentID && [details.videoId isEqualToString:contentID];
	return isContent ? response : nil;
}

static YTIVideoDetails *MenzenVideoDetails(YTPlayerViewController *controller) {
	if ([controller respondsToSelector:@selector(contentPlayerResponse)]) return MenzenDetails(controller.contentPlayerResponse);
	return MenzenDetails(MenzenActiveVideoResponse(controller));
}

static NSString *MenzenVideoID(YTPlayerViewController *controller) {
	NSString *videoID = [controller respondsToSelector:@selector(contentVideoID)] ? controller.contentVideoID : nil;
	NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_"].invertedSet;
	return [videoID isKindOfClass:NSString.class] && videoID.length == 11 && [videoID rangeOfCharacterFromSet:invalid].location == NSNotFound ? videoID : nil;
}

// Unlisted videos aren't crawlable. Only a video the player says is
// crawlable and not private is linked; one it hasn't seen isn't.
static NSString *MenzenPublicVideoID(NSString *videoID, YTIVideoDetails *details) {
	if (!videoID) return nil;
	if ([details respondsToSelector:@selector(videoId)] && [details.videoId isEqualToString:videoID] && [details respondsToSelector:@selector(isCrawlable)]) {
		BOOL isPrivate = [details respondsToSelector:@selector(isPrivate)] && details.isPrivate;
		publicVideos[videoID] = @(details.isCrawlable && !isPrivate);
	}

	return [publicVideos[videoID] boolValue] ? videoID : nil;
}

// Video thumbnails have the video ID in their path, so they'd give away an
// unlisted video's link too. Album art (googleusercontent) doesn't.
static BOOL MenzenIsVideoThumbnail(NSURLComponents *thumbnail) {
	return [thumbnail.host isEqualToString:@"ytimg.com"] || [thumbnail.host hasSuffix:@".ytimg.com"];
}

// The widest thumbnail, as a JPEG without the resizing query (the image host
// serves both).
static NSURLComponents *MenzenWidestThumbnail(YTIThumbnailDetails *thumbnail) {
	NSArray *thumbnails = [thumbnail respondsToSelector:@selector(thumbnailsArray)] ? thumbnail.thumbnailsArray : nil;
	YTIThumbnailDetails_Thumbnail *widest;
	for (YTIThumbnailDetails_Thumbnail *candidate in thumbnails) {
		if (![candidate respondsToSelector:@selector(URL)] || ![candidate respondsToSelector:@selector(width)]) continue;
		if (!widest || candidate.width > widest.width) widest = candidate;
	}

	NSURLComponents *components = widest ? [NSURLComponents componentsWithString:widest.URL] : nil;
	// YouTube Music's covers, as they are.
	if (music && [components.scheme isEqualToString:@"https"] && [components.host hasSuffix:@".googleusercontent.com"] && widest.URL.length <= 256) return components;
	if (![components.scheme isEqualToString:@"https"] || ![components.host isEqualToString:@"i.ytimg.com"]) return nil;
	components.query = nil;
	components.path = [components.path stringByReplacingOccurrencesOfString:@"/vi_webp/" withString:@"/vi/"];
	if ([components.path.pathExtension isEqualToString:@"webp"]) components.path = [components.path.stringByDeletingPathExtension stringByAppendingPathExtension:@"jpg"];
	return components;
}

static NSURLComponents *MenzenThumbnail(YTIVideoDetails *details) {
	return MenzenWidestThumbnail([details respondsToSelector:@selector(thumbnail)] ? details.thumbnail : nil);
}

// The same video's 4:3 thumbnail: the whole frame with bars above and below,
// which keeps the most of it when Discord crops the cover to a square.
static NSString *MenzenWholeThumbnailURL(NSURLComponents *thumbnail) {
	// /vi/<video ID>/<size>.jpg; live streams' are <size>_live.jpg.
	NSArray<NSString *> *parts = thumbnail.path.pathComponents;
	if (parts.count != 4 || ![parts[1] isEqualToString:@"vi"]) return nil;
	NSURLComponents *components = [thumbnail copy];
	NSString *name = [parts[3] containsString:@"_live"] ? @"hqdefault_live.jpg" : @"hqdefault.jpg";
	components.path = [NSString stringWithFormat:@"/vi/%@/%@", parts[2], name];
	return components.URL.absoluteString;
}

static NSString *MenzenBrowseID(YTICommand *command, NSString *prefix) {
	if (![command respondsToSelector:@selector(hasBrowseEndpoint)] || !command.hasBrowseEndpoint) return nil;
	NSString *browseID = [command.browseEndpoint respondsToSelector:@selector(browseId)] ? command.browseEndpoint.browseId : nil;
	return [browseID hasPrefix:prefix] ? MenzenLinkURL(@"%@", browseID) : nil;
}

static YTIPlaylistPanelVideoRenderer *MenzenQueueRenderer(NSString *videoID) {
	NSArray<YTQueueItem *> *items;
	@synchronized(queueItems) {
		items = queueItems.allObjects;
	}

	Class rendererClass = %c(YTIPlaylistPanelVideoRenderer);
	for (YTQueueItem *item in items) {
		NSMutableArray *renderers = [NSMutableArray array];
		if ([item respondsToSelector:@selector(videoRenderer)]) [renderers addObject:item.videoRenderer ?: NSNull.null];
		if ([item respondsToSelector:@selector(audioModeRenderer)]) [renderers addObject:item.audioModeRenderer ?: NSNull.null];
		if ([item respondsToSelector:@selector(videoModeRenderer)]) [renderers addObject:item.videoModeRenderer ?: NSNull.null];
		for (YTIPlaylistPanelVideoRenderer *renderer in renderers) {
			if (![renderer isKindOfClass:rendererClass] || ![renderer respondsToSelector:@selector(videoId)]) continue;
			if ([renderer.videoId isEqualToString:videoID]) return renderer;
		}
	}

	return nil;
}

// The first picture on yt3.googleusercontent.com in an artist page's header,
// as a square.
static NSString *MenzenHeaderPicture(YTIBrowseResponse *response) {
	id header = [response respondsToSelector:@selector(header)] ? response.header : nil;
	NSData *data = [header respondsToSelector:@selector(data)] ? [header data] : nil;
	if (![data isKindOfClass:NSData.class]) return nil;
	NSData *prefix = [@"https://yt3.googleusercontent.com/" dataUsingEncoding:NSUTF8StringEncoding];
	NSRange found = [data rangeOfData:prefix options:0 range:NSMakeRange(0, data.length)];
	if (found.location == NSNotFound) return nil;
	// The image's ID, up to its options ("=l90-rj").
	const char *bytes = data.bytes;
	NSUInteger end = NSMaxRange(found);
	while (end < data.length && end - NSMaxRange(found) < 200 && (isalnum((unsigned char)bytes[end]) || bytes[end] == '-' || bytes[end] == '_' || bytes[end] == '/')) end++;
	if (end == NSMaxRange(found)) return nil;
	NSString *ID = [[NSString alloc] initWithBytes:bytes + NSMaxRange(found) length:end - NSMaxRange(found) encoding:NSASCIIStringEncoding];
	return ID ? [NSString stringWithFormat:@"https://yt3.googleusercontent.com/%@=w544-h544-p-l90-rj", ID] : nil;
}

static void MenzenPublish(YTPlayerViewController *controller);

static void MenzenRepublishPlayer(void) {
	YTPlayerViewController *controller = player;
	if (controller) MenzenPublish(controller);
}

static void MenzenLoadArtistPicture(NSString *artistID) {
	YTBrowseServiceImpl *service = browseService;
	Class requestClass = %c(YTIBrowseRequest);
	if (!service || [artistPicturesLoading containsObject:artistID] || ![service respondsToSelector:@selector(makeRequest:refresh:responseBlock:errorBlock:)] || ![requestClass respondsToSelector:@selector(message)]) return;
	YTIBrowseRequest *request = [requestClass message];
	if (![request respondsToSelector:@selector(setBrowseId:)]) return;
	request.browseId = artistID;
	[artistPicturesLoading addObject:artistID];
	[service makeRequest:request refresh:NO responseBlock:^(id response) {
		NSString *picture = MenzenHeaderPicture(response);
		dispatch_async(dispatch_get_main_queue(), ^{
			[artistPicturesLoading removeObject:artistID];
			@synchronized(artistPictures) {
				if (artistPictures.count > 1000) [artistPictures removeAllObjects];
				artistPictures[artistID] = picture ?: (id)NSNull.null;
			}
			if (picture) MenzenRepublishPlayer();
		});
	} errorBlock:^(NSError *error) {
		// A later update asks again.
		dispatch_async(dispatch_get_main_queue(), ^{
			[artistPicturesLoading removeObject:artistID];
		});
	}];
}

static NSString *MenzenArtistPicture(NSString *artistID) {
	id picture;
	@synchronized(artistPictures) {
		picture = artistPictures[artistID];
	}

	if (!picture) {
		dispatch_async(dispatch_get_main_queue(), ^{
			MenzenLoadArtistPicture(artistID);
		});
	}

	return [picture isKindOfClass:NSString.class] ? picture : nil;
}

// details are the player's for the video, when it has them (YouTube Music
// with Premium publishes the info itself, off the main thread, so the queue
// alone has to do).
static NSDictionary *MenzenMusicExtras(NSString *videoID, YTIVideoDetails *details) {
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	YTIPlaylistPanelVideoRenderer *renderer = videoID ? MenzenQueueRenderer(videoID) : nil;
	NSURLComponents *thumbnail = MenzenThumbnail(details) ?: MenzenWidestThumbnail([renderer respondsToSelector:@selector(thumbnail)] ? renderer.thumbnail : nil);
	NSString *publicID = MenzenPublicVideoID(videoID, details);
	if (!publicID && MenzenIsVideoThumbnail(thumbnail)) thumbnail = nil;
	// Music videos have YouTube's thumbnails.
	extras[MenzenExtrasCoverKey] = ([thumbnail.host isEqualToString:@"i.ytimg.com"] ? MenzenWholeThumbnailURL(thumbnail) : nil) ?: thumbnail.URL.absoluteString;
	if (publicID) extras[MenzenExtrasTitleURLKey] = [@"https://music.youtube.com/watch?v=" stringByAppendingString:publicID];
	NSString *channelID = [details respondsToSelector:@selector(channelId)] ? MenzenLinkURL(@"%@", details.channelId) : nil;
	if ([channelID hasPrefix:@"UC"]) extras[MenzenExtrasArtistURLKey] = [@"https://music.youtube.com/channel/" stringByAppendingString:channelID];

	// The first credited artist with a page.
	YTIFormattedString *byline = [renderer respondsToSelector:@selector(shortBylineText)] ? renderer.shortBylineText : nil;
	NSArray *runs = [byline respondsToSelector:@selector(runsArray)] ? byline.runsArray : nil;
	for (YTIFormattedStringRun *run in runs) {
		if (![run respondsToSelector:@selector(hasNavigationEndpoint)] || !run.hasNavigationEndpoint) continue;
		NSString *artistID = MenzenBrowseID(run.navigationEndpoint, @"UC");
		if (!artistID) continue;
		extras[MenzenExtrasArtistURLKey] = [@"https://music.youtube.com/channel/" stringByAppendingString:artistID];
		if (run.text.length) extras[MenzenExtrasArtistNameKey] = run.text;
		extras[MenzenExtrasArtistImageKey] = MenzenArtistPicture(artistID);
		break;
	}

	// "Go to album".
	YTIMenuSupportedRenderers *menu = [renderer respondsToSelector:@selector(menu)] ? renderer.menu : nil;
	YTIMenuRenderer *menuRenderer = [menu respondsToSelector:@selector(menuRenderer)] ? menu.menuRenderer : nil;
	NSArray *menuItems = [menuRenderer respondsToSelector:@selector(itemsArray)] ? menuRenderer.itemsArray : nil;
	for (YTIMenuItemSupportedRenderers *item in menuItems) {
		if (![item respondsToSelector:@selector(hasMenuNavigationItemRenderer)] || !item.hasMenuNavigationItemRenderer) continue;
		YTIMenuNavigationItemRenderer *navigation = item.menuNavigationItemRenderer;
		if (![navigation respondsToSelector:@selector(hasNavigationEndpoint)] || !navigation.hasNavigationEndpoint) continue;
		NSString *albumID = MenzenBrowseID(navigation.navigationEndpoint, @"MPRE");
		if (!albumID) continue;
		extras[MenzenExtrasAlbumURLKey] = [@"https://music.youtube.com/browse/" stringByAppendingString:albumID];
		break;
	}

	return extras;
}

static NSDictionary *MenzenExtras(YTPlayerViewController *controller, YTIVideoDetails *details) {
	if (music) return MenzenMusicExtras(MenzenVideoID(controller), details);
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	NSString *videoID = MenzenPublicVideoID(MenzenVideoID(controller), details);
	NSURLComponents *thumbnail = videoID || !MenzenIsVideoThumbnail(MenzenThumbnail(details)) ? MenzenThumbnail(details) : nil;
	extras[MenzenExtrasCoverKey] = (thumbnail ? MenzenWholeThumbnailURL(thumbnail) : nil) ?: thumbnail.URL.absoluteString;
	if (videoID) extras[MenzenExtrasTitleURLKey] = [@"https://www.youtube.com/watch?v=" stringByAppendingString:videoID];
	NSString *channelID = [details respondsToSelector:@selector(channelId)] ? details.channelId : nil;
	if ([channelID hasPrefix:@"UC"] && [channelID rangeOfCharacterFromSet:NSCharacterSet.URLPathAllowedCharacterSet.invertedSet].location == NSNotFound) {
		extras[MenzenExtrasArtistURLKey] = [@"https://www.youtube.com/channel/" stringByAppendingString:channelID];
	}

	return extras;
}

// The video the user is watching: not an ad, and not a muted preview in a
// feed.
static BOOL MenzenWatching(YTPlayerViewController *controller) {
	YTSingleVideoController *video = [controller respondsToSelector:@selector(activeVideo)] ? controller.activeVideo : nil;
	if ([video respondsToSelector:@selector(isMuted)] && video.isMuted) return NO;
	return ![controller respondsToSelector:@selector(isPlayingAd)] || !controller.isPlayingAd;
}

static NSDictionary *MenzenPlayerInfo(YTPlayerViewController *controller) {
	YTIVideoDetails *details = MenzenVideoDetails(controller);
	if (!details.title.length || !MenzenVideoID(controller)) return nil;
	YTSingleVideoController *video = controller.activeVideo;
	BOOL playing = [video respondsToSelector:@selector(mediaState)] && video.mediaState == MenzenMediaStatePlaying;

	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	info[MPMediaItemPropertyTitle] = details.title;
	// Channels YouTube makes for an artist's music are "<artist> - Topic".
	NSString *author = [details.author hasSuffix:@" - Topic"] ? [details.author substringToIndex:details.author.length - @" - Topic".length] : details.author;
	if (author.length) info[MPMediaItemPropertyArtist] = author;
	if (![details respondsToSelector:@selector(isLive)] || !details.isLive) {
		if ([details respondsToSelector:@selector(lengthSeconds)] && details.lengthSeconds) info[MPMediaItemPropertyPlaybackDuration] = @(details.lengthSeconds);
		if ([controller respondsToSelector:@selector(contentVideoMediaTime)]) info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(MAX(controller.contentVideoMediaTime, 0));
	} else {
		info[MPNowPlayingInfoPropertyIsLiveStream] = @YES;
	}

	info[MPNowPlayingInfoPropertyPlaybackRate] = @(playing ? 1 : 0);
	info[MPNowPlayingInfoPropertyMediaType] = @(music ? MPNowPlayingInfoMediaTypeAudio : MPNowPlayingInfoMediaTypeVideo);
	NSURL *url = MenzenExtrasURL(MenzenExtras(controller, details));
	if (url) info[MPNowPlayingInfoPropertyAssetURL] = url;
	MenzenProviderWorked();
	return info;
}

static void MenzenPublish(YTPlayerViewController *controller) {
	if (!MenzenWatching(controller)) return;
	player = controller;
	MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
	if (appPublishes) {
		// Again, so the extras follow the player.
		if (center.nowPlayingInfo) center.nowPlayingInfo = center.nowPlayingInfo;
		return;
	}

	NSDictionary *info = MenzenPlayerInfo(controller);
	if (!info) return;
	publishing = YES;
	center.nowPlayingInfo = info;
	publishing = NO;
}

// After an ad, the player settles on the video a moment later.
static void MenzenPublishSoon(YTPlayerViewController *controller) {
	__weak YTPlayerViewController *weakController = controller;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		YTPlayerViewController *strongController = weakController;
		if (strongController) MenzenPublish(strongController);
	});
}

// YouTube's own info, with the extras when the player is on the same video.
static NSDictionary *MenzenInfoWithExtras(NSDictionary *info) {
	NSURL *assetURL = info[MPNowPlayingInfoPropertyAssetURL];
	if ([assetURL isKindOfClass:NSURL.class] && ![assetURL.scheme isEqualToString:MenzenExtrasScheme]) return info;
	NSMutableDictionary *withExtras = [info mutableCopy];
	[withExtras removeObjectForKey:MPNowPlayingInfoPropertyAssetURL];
	NSURL *url = nil;
	NSString *videoID = info[MPNowPlayingInfoPropertyExternalContentIdentifier];
	if (music && [videoID isKindOfClass:NSString.class] && MenzenLinkURL(@"%@", videoID)) {
		// YouTube Music says which video; the player may be elsewhere by now.
		YTPlayerViewController *controller = NSThread.isMainThread ? player : nil;
		YTIVideoDetails *details = [MenzenVideoID(controller) isEqualToString:videoID] ? MenzenVideoDetails(controller) : nil;
		url = MenzenExtrasURL(MenzenMusicExtras(videoID, details));
	} else {
		YTPlayerViewController *controller = player;
		YTIVideoDetails *details = MenzenVideoDetails(controller);
		if (!details || ![info[MPMediaItemPropertyTitle] isEqual:details.title]) return withExtras;
		url = MenzenExtrasURL(MenzenExtras(controller, details));
	}

	if (url) {
		withExtras[MPNowPlayingInfoPropertyAssetURL] = url;
		MenzenProviderWorked();
	}

	return withExtras;
}

%hook MPNowPlayingInfoCenter

- (void)setNowPlayingInfo:(NSDictionary *)info {
	if (publishing || self != MPNowPlayingInfoCenter.defaultCenter) {
		%orig;
		return;
	}

	if ([info isKindOfClass:NSDictionary.class] && [info[MPMediaItemPropertyTitle] length]) {
		appPublishes = YES;
		%orig(MenzenInfoWithExtras(info));
		return;
	}

	// YouTube clearing the info it never filled; keep ours while watching.
	YTPlayerViewController *controller = player;
	NSDictionary *ours = !appPublishes && controller && MenzenWatching(controller) ? MenzenPlayerInfo(controller) : nil;
	%orig(ours ?: info);
}

%end

%hook YTPlayerViewController

- (void)potentiallyMutatedSingleVideo:(id)video mediaStateDidChangeFromState:(NSInteger)fromState toState:(NSInteger)toState stoppageReason:(int)reason {
	%orig;
	MenzenPublish(self);
}

- (void)playbackController:(id)controller didActivateVideo:(id)video withPlaybackData:(id)data {
	%orig;
	MenzenPublish(self);
}

- (void)notifyDidEndScrubbingAtTime:(id)time {
	%orig;
	MenzenPublish(self);
}

- (void)playbackController:(id)controller didFinishPlayingAd:(id)ad completeType:(NSInteger)completeType {
	%orig;
	MenzenPublishSoon(self);
}

- (void)eventCenter:(id)eventCenter didActivateContentVideo:(id)video {
	%orig;
	MenzenPublishSoon(self);
}

%end

%group Music

%hook YTMBrowseServiceImpl

- (void)makeRequest:(id)request refresh:(BOOL)refresh responseBlock:(id)responseBlock errorBlock:(id)errorBlock {
	browseService = (YTBrowseServiceImpl *)self;
	%orig;
}

%end

%hook YTQueueItem

- (YTIPlaylistPanelVideoRenderer *)videoRenderer {
	@synchronized(queueItems) {
		[queueItems addObject:self];
	}

	return %orig;
}

%end

%end

%ctor {
	music = [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtubemusic"];
	NSArray *musicParts = @[
		@"YTQueueItem -videoRenderer",
		@"YTIPlaylistPanelVideoRenderer -videoId",
		@"YTIPlaylistPanelVideoRenderer -shortBylineText",
		@"YTIPlaylistPanelVideoRenderer -menu",
		@"YTMBrowseServiceImpl -makeRequest:refresh:responseBlock:errorBlock:",
		@"YTIBrowseRequest +message",
	];
	MenzenProviderCheck(@[
		@"YTPlayerViewController -contentVideoID",
		@"YTPlayerViewController -contentPlayerResponse | YTPlaybackData -playerResponse",
		@"YTPlayerViewController -activeVideo",
		@"YTPlayerViewController -potentiallyMutatedSingleVideo:mediaStateDidChangeFromState:toState:stoppageReason:",
		@"YTPlayerResponse -playerData",
		@"YTIPlayerResponse -videoDetails",
		@"YTIVideoDetails -title",
		@"YTIVideoDetails -author",
	], [@[
		@"YTPlayerViewController -contentVideoMediaTime",
		@"YTPlayerViewController -isPlayingAd",
		@"YTPlayerViewController -playbackController:didActivateVideo:withPlaybackData:",
		@"YTSingleVideoController -mediaState",
		@"YTSingleVideoController -isMuted",
		@"YTIVideoDetails -channelId",
		@"YTIVideoDetails -isCrawlable",
		@"YTIVideoDetails -thumbnail",
		@"YTIThumbnailDetails -thumbnailsArray",
	] arrayByAddingObjectsFromArray:music ? musicParts : @[]]);
	if (!%c(YTPlayerViewController)) return;
	publicVideos = [[MenzenCache alloc] initWithLimit:64];
	%init;
	if (music && %c(YTQueueItem)) {
		queueItems = [NSHashTable weakObjectsHashTable];
		artistPictures = [NSMutableDictionary dictionary];
		artistPicturesLoading = [NSMutableSet set];
		%init(Music);
	}
}
