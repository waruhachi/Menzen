#import "../../Shared/MZProvider/MZProvider.h"
#import "../../Shared/MZProvider/MZResponses.h"

// Pluto TV and Paramount+ share Paramount's API. Both publish an episode's
// title with its show as the album, but no season or episode; the API has
// them by the published contentId.
//
// Live TV: a Pluto channel plays as a video of its own, published as both
// title and album; Paramount+ channels and games play as the listing's
// video, and several games can be on at once. The listing on now for the
// video is published instead, with its time slot.

static BOOL pluto;
static NSString *site;
// Resizes pictures at thumbnails/photos/w<width>-q<quality>/<path without
// "files/">.
static NSString *imageServer;

// Guarded by @synchronized(videos). Listings are by the video they play,
// then by listing ID.
static NSMutableDictionary<NSString *, NSDictionary *> *videos;
static NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSDictionary *> *> *listings;
static NSMutableDictionary<NSString *, NSString *> *channelNames;

static NSString *MZNumber(id value) {
	NSInteger number = MZString(value).integerValue;
	return number > 0 ? @(number).stringValue : nil;
}

static NSDate *MZDate(id milliseconds) {
	return [milliseconds isKindOfClass:NSNumber.class] && [milliseconds doubleValue] > 0 ? [NSDate dateWithTimeIntervalSince1970:[milliseconds doubleValue] / 1000] : nil;
}

static NSString *MZPageURL(id value) {
	NSString *page = MZString(value);
	if (!page || [page containsString:@".."] || [page containsString:@"?"] || page.length > 300) return nil;
	if ([page hasPrefix:@"https://"]) return page;
	if ([page hasPrefix:@"//"] || [page containsString:@"://"]) return nil;
	return [page hasPrefix:@"/"] ? [site stringByAppendingString:page] : [NSString stringWithFormat:@"%@/%@", site, page];
}

static void MZRememberVideo(NSDictionary *video, NSString *contentID) {
	NSMutableDictionary *kept = [NSMutableDictionary dictionary];
	for (NSString *key in @[@"seriesTitle", @"seasonNum", @"episodeNum", @"thumbnail", @"mediaType", @"videoPageUrl", @"showPageUrl"]) {
		kept[key] = MZString(video[key]);
	}

	@synchronized(videos) {
		if (videos.count > 2000) [videos removeAllObjects];
		videos[contentID] = kept;
	}
}

static void MZRememberListing(NSDictionary *listing, NSString *contentID) {
	NSString *listingID = MZString(listing[@"id"]);
	NSDate *end = MZDate(listing[@"endTimestamp"]);
	if (!listingID || !end || end.timeIntervalSinceNow < 0) return;
	NSMutableDictionary *kept = [NSMutableDictionary dictionary];
	for (NSString *key in @[@"title", @"episodeTitle", @"filePathThumb", @"filepathMovieThumbnail", @"seasonNumber", @"showEpisodeNumber", @"channelSlug"]) {
		kept[key] = MZString(listing[key]);
	}

	kept[@"startTimestamp"] = listing[@"startTimestamp"];
	kept[@"endTimestamp"] = listing[@"endTimestamp"];
	@synchronized(videos) {
		NSMutableDictionary *forVideo = listings[contentID];
		if (!forVideo) {
			if (listings.count > 2000) [listings removeAllObjects];
			forVideo = listings[contentID] = [NSMutableDictionary dictionary];
		}
		// Drop the ones that are over.
		for (NSString *otherID in forVideo.allKeys) {
			if (MZDate(forVideo[otherID][@"endTimestamp"]).timeIntervalSinceNow < 0) [forVideo removeObjectForKey:otherID];
		}
		if (forVideo.count < 200) forVideo[listingID] = kept;
	}
}

static void MZRemember(NSData *body) {
	MZEachDictionary(MZJSON(body), ^(NSDictionary *dictionary) {
		NSString *contentID = MZString(dictionary[@"contentId"]);
		NSString *videoContentID = MZString(dictionary[@"videoContentId"]);
		if (contentID && MZString(dictionary[@"mediaType"])) MZRememberVideo(dictionary, contentID);
		else if (videoContentID && dictionary[@"startTimestamp"] && MZString(dictionary[@"title"])) MZRememberListing(dictionary, videoContentID);
		NSString *slug = MZString(dictionary[@"slug"]);
		NSString *channelName = MZString(dictionary[@"channelName"]);
		if (slug && channelName && [dictionary[@"currentListing"] isKindOfClass:NSArray.class]) {
			@synchronized(videos) {
				if (channelNames.count > 2000) [channelNames removeAllObjects];
				channelNames[slug] = channelName;
			}
		}
	});
}

static NSDictionary *MZLiveExtras(NSString *contentID, NSMutableDictionary *withExtras) {
	NSDate *now = NSDate.date;
	NSDictionary *listing = nil;
	NSString *channelName = nil;
	@synchronized(videos) {
		for (NSDictionary *candidate in listings[contentID].allValues) {
			NSDate *start = MZDate(candidate[@"startTimestamp"]);
			NSDate *end = MZDate(candidate[@"endTimestamp"]);
			if (start && end && [start compare:now] != NSOrderedDescending && [now compare:end] == NSOrderedAscending) {
				listing = candidate;
				break;
			}
		}
		channelName = listing[@"channelSlug"] ? channelNames[listing[@"channelSlug"]] : nil;
	}

	NSString *title = listing[@"title"];
	if (!title) return nil;

	NSString *episodeTitle = listing[@"episodeTitle"];
	NSString *artist = channelName;
	// An episode's title is its show's.
	if (episodeTitle && ![episodeTitle isEqualToString:title]) {
		artist = title;
		title = episodeTitle;
	}

	withExtras[MPMediaItemPropertyTitle] = title;
	if (artist) {
		withExtras[MPMediaItemPropertyArtist] = artist;
		// An album that's the artist again is taken as none.
		withExtras[MPMediaItemPropertyAlbumTitle] = artist;
	}

	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	NSDate *start = MZDate(listing[@"startTimestamp"]);
	NSDate *end = MZDate(listing[@"endTimestamp"]);
	withExtras[MPMediaItemPropertyPlaybackDuration] = @([end timeIntervalSinceDate:start]);
	withExtras[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @([now timeIntervalSinceDate:start]);
	// For Paramount+, which marks the info as a live stream.
	extras[MZExtrasStartKey] = @((long long)start.timeIntervalSince1970).stringValue;
	extras[MZExtrasEndKey] = @((long long)end.timeIntervalSince1970).stringValue;

	NSString *picture = listing[@"filePathThumb"] ?: listing[@"filepathMovieThumbnail"];
	if ([picture hasPrefix:@"files/"] && ![picture containsString:@".."] && ![picture containsString:@"?"]) extras[MZExtrasCoverKey] = [imageServer stringByAppendingString:[picture substringFromIndex:@"files/".length]];
	extras[MZExtrasSeasonKey] = MZNumber(listing[@"seasonNumber"]);
	extras[MZExtrasEpisodeKey] = MZNumber(listing[@"showEpisodeNumber"]);
	// The video is the channel.
	if (pluto && contentID.length == 24) extras[MZExtrasTitleURLKey] = MZLinkURL(@"https://pluto.tv/live-tv/%@", contentID);
	return extras;
}

static NSDictionary *MZVideoExtras(NSDictionary *video, NSMutableDictionary *withExtras) {
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	if ([video[@"thumbnail"] hasPrefix:@"https://"]) extras[MZExtrasCoverKey] = video[@"thumbnail"];
	extras[MZExtrasSeasonKey] = MZNumber(video[@"seasonNum"]);
	extras[MZExtrasEpisodeKey] = MZNumber(video[@"episodeNum"]);
	extras[MZExtrasTitleURLKey] = MZPageURL(video[@"videoPageUrl"]);
	extras[MZExtrasArtistURLKey] = MZPageURL(video[@"showPageUrl"]);
	// The album stays the show, which menzend takes as no album.
	if (video[@"seriesTitle"]) withExtras[MPMediaItemPropertyArtist] = video[@"seriesTitle"];
	return extras;
}

static NSDictionary *MZExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	NSString *contentID = MZString(info[MPNowPlayingInfoPropertyExternalContentIdentifier]);
	if (center != MPNowPlayingInfoCenter.defaultCenter || !contentID || !MZString(info[MPMediaItemPropertyTitle])) return nil;
	NSDictionary *video;
	@synchronized(videos) {
		video = videos[contentID];
	}

	return video && ![video[@"mediaType"] isEqualToString:@"Live"] ? MZVideoExtras(video, withExtras) : MZLiveExtras(contentID, withExtras);
}

%ctor {
	pluto = [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"tv.pluto.ios"];
	site = pluto ? @"https://pluto.tv" : @"https://www.paramountplus.com";
	imageServer = pluto ? @"https://wwwimage-us.plutostatic.tv/thumbnails/photos/w512-q80/" : @"https://wwwimage-us.pplusstatic.com/thumbnails/photos/w512-q80/";
	videos = [NSMutableDictionary dictionary];
	listings = [NSMutableDictionary dictionary];
	channelNames = [NSMutableDictionary dictionary];
	NSString *host = pluto ? @"pluto.tv" : @"www.paramountplus.com";
	MZProviderCheck(@[], @[]);
	MZAddExtras(MZExtras);
	MZObserveResponses(^BOOL(NSURL *url) {
		// The API's JSON, not its streams' and sessions' (which carry tokens).
		NSString *path = url.path;
		return [url.host.lowercaseString isEqualToString:host] && [path hasPrefix:@"/apps-api/"] && [path hasSuffix:@".json"] && ![path containsString:@"streaming-url"] && ![path containsString:@"session"] && ![path containsString:@"token"];
	}, ^(NSURL *url, NSData *body) {
		MZRemember(body);
	});
}
