#import "../../Shared/MenzenProvider/MenzenProvider.h"
#import "../../Shared/MenzenProvider/MenzenResponses.h"

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

static NSString *MenzenNumber(id value) {
	NSInteger number = MenzenString(value).integerValue;
	return number > 0 ? @(number).stringValue : nil;
}

static NSDate *MenzenDate(id milliseconds) {
	return [milliseconds isKindOfClass:NSNumber.class] && [milliseconds doubleValue] > 0 ? [NSDate dateWithTimeIntervalSince1970:[milliseconds doubleValue] / 1000] : nil;
}

static NSString *MenzenPageURL(id value) {
	NSString *page = MenzenString(value);
	if (!page || [page containsString:@".."] || [page containsString:@"?"] || page.length > 300) return nil;
	if ([page hasPrefix:@"https://"]) return page;
	if ([page hasPrefix:@"//"] || [page containsString:@"://"]) return nil;
	return [page hasPrefix:@"/"] ? [site stringByAppendingString:page] : [NSString stringWithFormat:@"%@/%@", site, page];
}

static void MenzenRememberVideo(NSDictionary *video, NSString *contentID) {
	NSMutableDictionary *kept = [NSMutableDictionary dictionary];
	for (NSString *key in @[@"seriesTitle", @"seasonNum", @"episodeNum", @"thumbnail", @"mediaType", @"videoPageUrl", @"showPageUrl"]) {
		kept[key] = MenzenString(video[key]);
	}

	@synchronized(videos) {
		if (videos.count > 2000) [videos removeAllObjects];
		videos[contentID] = kept;
	}
}

static void MenzenRememberListing(NSDictionary *listing, NSString *contentID) {
	NSString *listingID = MenzenString(listing[@"id"]);
	NSDate *end = MenzenDate(listing[@"endTimestamp"]);
	if (!listingID || !end || end.timeIntervalSinceNow < 0) return;
	NSMutableDictionary *kept = [NSMutableDictionary dictionary];
	for (NSString *key in @[@"title", @"episodeTitle", @"filePathThumb", @"filepathMovieThumbnail", @"seasonNumber", @"showEpisodeNumber", @"channelSlug"]) {
		kept[key] = MenzenString(listing[key]);
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
			if (MenzenDate(forVideo[otherID][@"endTimestamp"]).timeIntervalSinceNow < 0) [forVideo removeObjectForKey:otherID];
		}
		if (forVideo.count < 200) forVideo[listingID] = kept;
	}
}

static void MenzenRemember(NSData *body) {
	MenzenEachDictionary(MenzenJSON(body), ^(NSDictionary *dictionary) {
		NSString *contentID = MenzenString(dictionary[@"contentId"]);
		NSString *videoContentID = MenzenString(dictionary[@"videoContentId"]);
		if (contentID && MenzenString(dictionary[@"mediaType"])) MenzenRememberVideo(dictionary, contentID);
		else if (videoContentID && dictionary[@"startTimestamp"] && MenzenString(dictionary[@"title"])) MenzenRememberListing(dictionary, videoContentID);
		NSString *slug = MenzenString(dictionary[@"slug"]);
		NSString *channelName = MenzenString(dictionary[@"channelName"]);
		if (slug && channelName && [dictionary[@"currentListing"] isKindOfClass:NSArray.class]) {
			@synchronized(videos) {
				if (channelNames.count > 2000) [channelNames removeAllObjects];
				channelNames[slug] = channelName;
			}
		}
	});
}

static NSDictionary *MenzenLiveExtras(NSString *contentID, NSMutableDictionary *withExtras) {
	NSDate *now = NSDate.date;
	NSDictionary *listing = nil;
	NSString *channelName = nil;
	@synchronized(videos) {
		for (NSDictionary *candidate in listings[contentID].allValues) {
			NSDate *start = MenzenDate(candidate[@"startTimestamp"]);
			NSDate *end = MenzenDate(candidate[@"endTimestamp"]);
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
	NSDate *start = MenzenDate(listing[@"startTimestamp"]);
	NSDate *end = MenzenDate(listing[@"endTimestamp"]);
	withExtras[MPMediaItemPropertyPlaybackDuration] = @([end timeIntervalSinceDate:start]);
	withExtras[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @([now timeIntervalSinceDate:start]);
	// For Paramount+, which marks the info as a live stream.
	extras[MenzenExtrasStartKey] = @((long long)start.timeIntervalSince1970).stringValue;
	extras[MenzenExtrasEndKey] = @((long long)end.timeIntervalSince1970).stringValue;

	NSString *picture = listing[@"filePathThumb"] ?: listing[@"filepathMovieThumbnail"];
	if ([picture hasPrefix:@"files/"] && ![picture containsString:@".."] && ![picture containsString:@"?"]) extras[MenzenExtrasCoverKey] = [imageServer stringByAppendingString:[picture substringFromIndex:@"files/".length]];
	extras[MenzenExtrasSeasonKey] = MenzenNumber(listing[@"seasonNumber"]);
	extras[MenzenExtrasEpisodeKey] = MenzenNumber(listing[@"showEpisodeNumber"]);
	// The video is the channel.
	if (pluto && contentID.length == 24) extras[MenzenExtrasTitleURLKey] = MenzenLinkURL(@"https://pluto.tv/live-tv/%@", contentID);
	return extras;
}

static NSDictionary *MenzenVideoExtras(NSDictionary *video, NSMutableDictionary *withExtras) {
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	if ([video[@"thumbnail"] hasPrefix:@"https://"]) extras[MenzenExtrasCoverKey] = video[@"thumbnail"];
	extras[MenzenExtrasSeasonKey] = MenzenNumber(video[@"seasonNum"]);
	extras[MenzenExtrasEpisodeKey] = MenzenNumber(video[@"episodeNum"]);
	extras[MenzenExtrasTitleURLKey] = MenzenPageURL(video[@"videoPageUrl"]);
	extras[MenzenExtrasArtistURLKey] = MenzenPageURL(video[@"showPageUrl"]);
	// The album stays the show, which menzend takes as no album.
	if (video[@"seriesTitle"]) withExtras[MPMediaItemPropertyArtist] = video[@"seriesTitle"];
	return extras;
}

static NSDictionary *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	NSString *contentID = MenzenString(info[MPNowPlayingInfoPropertyExternalContentIdentifier]);
	if (center != MPNowPlayingInfoCenter.defaultCenter || !contentID || !MenzenString(info[MPMediaItemPropertyTitle])) return nil;
	NSDictionary *video;
	@synchronized(videos) {
		video = videos[contentID];
	}

	return video && ![video[@"mediaType"] isEqualToString:@"Live"] ? MenzenVideoExtras(video, withExtras) : MenzenLiveExtras(contentID, withExtras);
}

%ctor {
	pluto = [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"tv.pluto.ios"];
	site = pluto ? @"https://pluto.tv" : @"https://www.paramountplus.com";
	imageServer = pluto ? @"https://wwwimage-us.plutostatic.tv/thumbnails/photos/w512-q80/" : @"https://wwwimage-us.pplusstatic.com/thumbnails/photos/w512-q80/";
	videos = [NSMutableDictionary dictionary];
	listings = [NSMutableDictionary dictionary];
	channelNames = [NSMutableDictionary dictionary];
	NSString *host = pluto ? @"pluto.tv" : @"www.paramountplus.com";
	MenzenProviderCheck(@[], @[]);
	MenzenAddExtras(MenzenExtras);
	MenzenObserveResponses(^BOOL(NSURL *url) {
		// The API's JSON, not its streams' and sessions' (which carry tokens).
		NSString *path = url.path;
		return [url.host.lowercaseString isEqualToString:host] && [path hasPrefix:@"/apps-api/"] && [path hasSuffix:@".json"] && ![path containsString:@"streaming-url"] && ![path containsString:@"session"] && ![path containsString:@"token"];
	}, ^(NSURL *url, NSData *body) {
		MenzenRemember(body);
	});
}
