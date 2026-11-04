
#import "../../Shared/MenzenProvider/MenzenProvider.h"
#import "../../Shared/MenzenThrottle.h"

// The info already has the cover and catalog IDs, but not the artist's
// picture, which comes from the app's own store metadata request. The
// publisher hands MediaRemote one item at a time, so the picture goes out as
// a change to the item, the way the app updates its items itself.

@interface MPNowPlayingContentItem : NSObject
- (void *)_mediaRemoteContentItem;
// The block changes an empty MRContentItem; the item applies the change to
// itself and its info center sends it on.
- (void)_postItemChangedNotificationWithDeltaBlock:(void (^)(void *delta))block;
@end

@interface MRContentItemMetadata : NSObject <NSCopying>
@property (nonatomic, copy) NSURL *assetURL;
@end

@interface MRContentItem : NSObject
@property (nonatomic, copy) MRContentItemMetadata *metadata;
@end

@interface MPStoreItemMetadata : NSObject
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSDictionary *effectiveStorePlatformDictionary;
@end

@interface MPStoreItemMetadataResponse : NSObject
- (MPStoreItemMetadata *)storeItemMetadataForItemIdentifier:(NSString *)identifier;
@end

@interface MPStoreItemMetadataRequest : NSObject
@property (nonatomic, copy) NSArray<NSString *> *itemIdentifiers;
@property (nonatomic) NSInteger reason;
@end

@interface MPStoreItemMetadataRequestController : NSObject
+ (instancetype)sharedStoreItemMetadataRequestController;
- (id)getStoreItemMetadataForRequest:(MPStoreItemMetadataRequest *)request responseHandler:(void (^)(MPStoreItemMetadataResponse *response, NSError *error))handler;
@end

static NSTimeInterval const MenzenPostDelay = 1;
// Each refetch asks the store about every artist still held.
static NSTimeInterval const MenzenRefetchInterval = 30;

// NSNull for an artist without a picture.
static NSMutableDictionary<NSString *, id> *artists;
static NSMutableDictionary<NSString *, NSHashTable *> *artistsLoading;
// Items handed out that the app still holds, for a refetch.
static NSHashTable *items;

static void MenzenSetAssetURL(MRContentItem *contentItem, NSURL *url) {
	if (![contentItem respondsToSelector:@selector(metadata)] || ![contentItem respondsToSelector:@selector(setMetadata:)]) return;
	MRContentItemMetadata *metadata = [contentItem.metadata copy] ?: [%c(MRContentItemMetadata) new];
	// The app's own asset URL (a local file) wins.
	if (![metadata respondsToSelector:@selector(setAssetURL:)] || (metadata.assetURL && ![metadata.assetURL.scheme isEqualToString:MenzenExtrasScheme])) return;
	metadata.assetURL = url;
	contentItem.metadata = metadata;
}

// Changing an item as it's handed out doesn't reach MediaRemote; it only
// takes the change the way the app sends its own. Once is enough: the item
// keeps it. Only a different picture (after a refetch) replaces ours, and
// the app's own asset URL is never replaced.
static void MenzenPostAssetURL(MPNowPlayingContentItem *item, NSURL *url) {
	if (![item respondsToSelector:@selector(_postItemChangedNotificationWithDeltaBlock:)]) return;
	MRContentItem *contentItem = (__bridge MRContentItem *)[item _mediaRemoteContentItem];
	NSURL *current = [contentItem respondsToSelector:@selector(metadata)] ? contentItem.metadata.assetURL : nil;
	if (current && (![current.scheme isEqualToString:MenzenExtrasScheme] || [current isEqual:url])) return;
	[item _postItemChangedNotificationWithDeltaBlock:^(void *delta) {
		MenzenSetAssetURL((__bridge MRContentItem *)delta, url);
	}];
	MenzenProviderWorked();
}

static NSURL *MenzenExtrasURLForArtist(id extras) {
	return [extras isKindOfClass:NSDictionary.class] ? MenzenExtrasURL(extras) : nil;
}

static NSString *MenzenArtworkURL(NSDictionary *artist) {
	NSDictionary *artwork = [artist isKindOfClass:NSDictionary.class] ? artist[@"artwork"] : nil;
	NSString *url = [artwork isKindOfClass:NSDictionary.class] ? artwork[@"url"] : nil;
	if (![url isKindOfClass:NSString.class]) return nil;
	url = [url stringByReplacingOccurrencesOfString:@"{w}" withString:@"512"];
	url = [url stringByReplacingOccurrencesOfString:@"{h}" withString:@"512"];
	url = [url stringByReplacingOccurrencesOfString:@"{c}" withString:@"bb"];
	url = [url stringByReplacingOccurrencesOfString:@"{f}" withString:@"jpg"];
	return [url hasPrefix:@"https://"] && ![url containsString:@"{"] ? url : nil;
}

static void MenzenLoadArtist(NSString *artistID) {
	MPStoreItemMetadataRequest *request = [%c(MPStoreItemMetadataRequest) new];
	request.itemIdentifiers = @[artistID];
	[[%c(MPStoreItemMetadataRequestController) sharedStoreItemMetadataRequestController] getStoreItemMetadataForRequest:request responseHandler:^(MPStoreItemMetadataResponse *response, NSError *error) {
		MPStoreItemMetadata *metadata = [response respondsToSelector:@selector(storeItemMetadataForItemIdentifier:)] ? [response storeItemMetadataForItemIdentifier:artistID] : nil;
		NSString *picture = [metadata respondsToSelector:@selector(effectiveStorePlatformDictionary)] ? MenzenArtworkURL(metadata.effectiveStorePlatformDictionary) : nil;
		NSMutableDictionary *extras = [NSMutableDictionary dictionary];
		extras[MenzenExtrasArtistImageKey] = picture;
		extras[MenzenExtrasArtistNameKey] = [metadata respondsToSelector:@selector(name)] && [metadata.name isKindOfClass:NSString.class] ? metadata.name : nil;

		NSArray *waiting;
		@synchronized(artists) {
			// The handler can run more than once, as better answers come in:
			// one without a picture (a cached one) doesn't stop a later one.
			if (!artistsLoading[artistID]) return;
			if (!picture) {
				// Offline: try again on a later item.
				if (!metadata && !artists[artistID]) [artistsLoading removeObjectForKey:artistID];
				else if (metadata) artists[artistID] = NSNull.null;
				return;
			}
			waiting = artistsLoading[artistID].allObjects;
			[artistsLoading removeObjectForKey:artistID];
			artists[artistID] = extras;
		}
		NSURL *url = MenzenExtrasURLForArtist(artists[artistID]);
		if (!url) return;
		dispatch_async(dispatch_get_main_queue(), ^{
			for (MPNowPlayingContentItem *item in waiting) MenzenPostAssetURL(item, url);
		});
	}];
}

static void MenzenAddArtistPicture(MPNowPlayingContentItem *item) {
	if (![item respondsToSelector:@selector(_mediaRemoteContentItem)]) return;
	id artistID = [item valueForKey:@"storeArtistID"];
	if (![artistID respondsToSelector:@selector(longLongValue)] || [artistID longLongValue] <= 0) return;
	NSString *identifier = @([artistID longLongValue]).stringValue;

	id extras;
	@synchronized(artists) {
		[items addObject:item];
		extras = artists[identifier];
		// No picture yet, but a better answer may still come in.
		if (extras == NSNull.null && artistsLoading[identifier]) [artistsLoading[identifier] addObject:item];
		if (!extras) {
			BOOL loading = !!artistsLoading[identifier];
			if (!loading) artistsLoading[identifier] = [NSHashTable weakObjectsHashTable];
			[artistsLoading[identifier] addObject:item];
			if (!loading) dispatch_async(dispatch_get_main_queue(), ^{
				MenzenLoadArtist(identifier);
			});
			return;
		}
	}

	NSURL *url = MenzenExtrasURLForArtist(extras);
	// After the item is out: a change posted before MediaRemote has the item
	// is lost (a new song by a known artist comes straight here).
	if (url) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MenzenPostDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		MenzenPostAssetURL(item, url);
	});
}

// Forgets every artist and looks up the ones still playing or queued again.
static void MenzenRefetch(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	static MenzenThrottle throttle;
	dispatch_async(dispatch_get_main_queue(), ^{
		MenzenThrottleRun(&throttle, MenzenRefetchInterval, ^{
			NSArray *held;
			@synchronized(artists) {
				[artists removeAllObjects];
				[artistsLoading removeAllObjects];
				held = items.allObjects;
			}
			for (MPNowPlayingContentItem *item in held) MenzenAddArtistPicture(item);
		});
	});
}

%hook MenzenPublisher

- (id)nowPlayingInfoCenter:(MPNowPlayingInfoCenter *)center contentItemForID:(NSString *)identifier {
	id item = %orig;
	if ([item isKindOfClass:%c(MPNowPlayingContentItem)]) MenzenAddArtistPicture(item);
	return item;
}

%end

%ctor {
	MenzenProviderCheck(@[
		@"_MPCMediaRemotePublisher -nowPlayingInfoCenter:contentItemForID:",
		@"MPNowPlayingContentItem -_mediaRemoteContentItem",
		@"MPNowPlayingContentItem -_postItemChangedNotificationWithDeltaBlock:",
		@"MRContentItem -setMetadata:",
		@"MRContentItemMetadata -setAssetURL:",
		@"MPStoreItemMetadataRequestController +sharedStoreItemMetadataRequestController",
		@"MPStoreItemMetadataRequestController -getStoreItemMetadataForRequest:responseHandler:",
		@"MPStoreItemMetadataResponse -storeItemMetadataForItemIdentifier:",
		@"MPStoreItemMetadata -effectiveStorePlatformDictionary",
	], @[]);
	Class publisher = %c(_MPCMediaRemotePublisher);
	if (!publisher || !%c(MPStoreItemMetadataRequestController)) return;
	artists = [NSMutableDictionary dictionary];
	artistsLoading = [NSMutableDictionary dictionary];
	items = [NSHashTable weakObjectsHashTable];
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, MenzenRefetch, CFSTR(MenzenRefetchNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	%init(MenzenPublisher = publisher);
}
