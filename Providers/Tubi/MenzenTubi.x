#import "../../Shared/MenzenProvider/MenzenProvider.h"
#import "../../Shared/MenzenProvider/MenzenResponses.h"

// The app publishes "Tubi - Now Playing" as the artist, and the stream as the
// asset URL, which carries a token and is replaced here. The content API has
// each video by the published ID. The site has no page for an episode, so
// an episode links to its show.

static NSMutableDictionary<NSString *, NSDictionary *> *videos;
static NSMutableDictionary<NSString *, NSString *> *seriesTitles;

// Series IDs sometimes come zero-padded.
static NSString *MenzenSeriesKey(NSString *ID) {
	NSUInteger zeros = 0;
	while (zeros + 1 < ID.length && [ID characterAtIndex:zeros] == '0') zeros++;
	return [ID substringFromIndex:zeros];
}

static NSString *MenzenCover(NSDictionary *video) {
	NSDictionary *images = [video[@"images"] isKindOfClass:NSDictionary.class] ? video[@"images"] : nil;
	for (NSString *key in @[@"landscape_tb", @"thumbnails"]) {
		id list = images[key] ?: video[key];
		NSString *url = [list isKindOfClass:NSArray.class] ? MenzenString([list firstObject]) : nil;
		if ([url hasPrefix:@"https://"] && url.length <= 300) return url;
	}

	return nil;
}

static void MenzenRemember(NSData *body) {
	MenzenEachDictionary(MenzenJSON(body), ^(NSDictionary *content) {
		NSString *ID = MenzenString(content[@"id"]);
		NSString *type = MenzenString(content[@"type"]);
		NSString *title = MenzenString(content[@"title"]);
		if (!ID || !title) return;
		if ([type isEqualToString:@"s"]) {
			@synchronized(videos) {
				if (seriesTitles.count > 1000) [seriesTitles removeAllObjects];
				seriesTitles[MenzenSeriesKey(ID)] = title;
			}
		} else if ([type isEqualToString:@"v"]) {
			NSMutableDictionary *video = [NSMutableDictionary dictionary];
			video[@"cover"] = MenzenCover(content);
			NSString *seriesID = MenzenString(content[@"series_id"]);
			video[@"series"] = seriesID ? MenzenSeriesKey(seriesID) : nil;
			@synchronized(videos) {
				if (videos.count > 2000) [videos removeAllObjects];
				videos[ID] = video;
			}
		}
	});
}

static NSDictionary *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	NSString *contentID = MenzenString(info[MPNowPlayingInfoPropertyExternalContentIdentifier]);
	NSDictionary *video = nil;
	NSString *show = nil;
	if (contentID) {
		@synchronized(videos) {
			video = videos[contentID];
			show = video[@"series"] ? seriesTitles[video[@"series"]] : nil;
		}
	}

	if (!video || center != MPNowPlayingInfoCenter.defaultCenter || !MenzenString(info[MPMediaItemPropertyTitle])) return nil;
	NSString *seriesID = video[@"series"];
	NSString *page = seriesID ? MenzenLinkURL(@"https://tubitv.com/series/%@", seriesID) : MenzenLinkURL(@"https://tubitv.com/movies/%@", contentID);
	if (show) withExtras[MPMediaItemPropertyArtist] = show;
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	extras[MenzenExtrasCoverKey] = video[@"cover"];
	extras[MenzenExtrasTitleURLKey] = page;
	if (seriesID) extras[MenzenExtrasArtistURLKey] = page;
	return extras;
}

%ctor {
	videos = [NSMutableDictionary dictionary];
	seriesTitles = [NSMutableDictionary dictionary];
	MenzenProviderCheck(@[], @[]);
	MenzenAddExtras(MenzenExtras);
	MenzenObserveResponses(^BOOL(NSURL *url) {
		return [url.host.lowercaseString isEqualToString:@"content-cdn.production-public.tubi.io"] && [url.path hasPrefix:@"/api/"] && [url.path hasSuffix:@"/content"];
	}, ^(NSURL *url, NSData *body) {
		MenzenRemember(body);
	});
}
