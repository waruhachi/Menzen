#import "../../Shared/MZProvider/MZProvider.h"
#import "../../Shared/MZProvider/MZResponses.h"

// The app publishes "Tubi - Now Playing" as the artist, and the stream as the
// asset URL, which carries a token and is replaced here. The content API has
// each video by the published ID. The site has no page for an episode, so
// an episode links to its show.

static NSMutableDictionary<NSString *, NSDictionary *> *videos;
static NSMutableDictionary<NSString *, NSString *> *seriesTitles;

// Series IDs sometimes come zero-padded.
static NSString *MZSeriesKey(NSString *ID) {
	NSUInteger zeros = 0;
	while (zeros + 1 < ID.length && [ID characterAtIndex:zeros] == '0') zeros++;
	return [ID substringFromIndex:zeros];
}

static NSString *MZCover(NSDictionary *video) {
	NSDictionary *images = [video[@"images"] isKindOfClass:NSDictionary.class] ? video[@"images"] : nil;
	for (NSString *key in @[@"landscape_tb", @"thumbnails"]) {
		id list = images[key] ?: video[key];
		NSString *url = [list isKindOfClass:NSArray.class] ? MZString([list firstObject]) : nil;
		if ([url hasPrefix:@"https://"] && url.length <= 300) return url;
	}

	return nil;
}

static void MZRemember(NSData *body) {
	MZEachDictionary(MZJSON(body), ^(NSDictionary *content) {
		NSString *ID = MZString(content[@"id"]);
		NSString *type = MZString(content[@"type"]);
		NSString *title = MZString(content[@"title"]);
		if (!ID || !title) return;
		if ([type isEqualToString:@"s"]) {
			@synchronized(videos) {
				if (seriesTitles.count > 1000) [seriesTitles removeAllObjects];
				seriesTitles[MZSeriesKey(ID)] = title;
			}
		} else if ([type isEqualToString:@"v"]) {
			NSMutableDictionary *video = [NSMutableDictionary dictionary];
			video[@"cover"] = MZCover(content);
			NSString *seriesID = MZString(content[@"series_id"]);
			video[@"series"] = seriesID ? MZSeriesKey(seriesID) : nil;
			@synchronized(videos) {
				if (videos.count > 2000) [videos removeAllObjects];
				videos[ID] = video;
			}
		}
	});
}

static NSDictionary *MZExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	NSString *contentID = MZString(info[MPNowPlayingInfoPropertyExternalContentIdentifier]);
	NSDictionary *video = nil;
	NSString *show = nil;
	if (contentID) {
		@synchronized(videos) {
			video = videos[contentID];
			show = video[@"series"] ? seriesTitles[video[@"series"]] : nil;
		}
	}

	if (!video || center != MPNowPlayingInfoCenter.defaultCenter || !MZString(info[MPMediaItemPropertyTitle])) return nil;
	NSString *seriesID = video[@"series"];
	NSString *page = seriesID ? MZLinkURL(@"https://tubitv.com/series/%@", seriesID) : MZLinkURL(@"https://tubitv.com/movies/%@", contentID);
	if (show) withExtras[MPMediaItemPropertyArtist] = show;
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	extras[MZExtrasCoverKey] = video[@"cover"];
	extras[MZExtrasTitleURLKey] = page;
	if (seriesID) extras[MZExtrasArtistURLKey] = page;
	return extras;
}

%ctor {
	videos = [NSMutableDictionary dictionary];
	seriesTitles = [NSMutableDictionary dictionary];
	MZProviderCheck(@[], @[]);
	MZAddExtras(MZExtras);
	MZObserveResponses(^BOOL(NSURL *url) {
		return [url.host.lowercaseString isEqualToString:@"content-cdn.production-public.tubi.io"] && [url.path hasPrefix:@"/api/"] && [url.path hasSuffix:@"/content"];
	}, ^(NSURL *url, NSData *body) {
		MZRemember(body);
	});
}
