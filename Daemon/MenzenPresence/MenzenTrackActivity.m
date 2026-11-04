#import "../../Shared/MenzenCard.h"
#import "../../Shared/MenzenProviders.h"
#import "../../Shared/MenzenTrackExtras.h"
#import "../MenzenApps/MenzenAppInfo.h"
#import "MenzenEpisode.h"
#import "MenzenTrackActivity.h"

// Discord rejects longer URLs.
static NSUInteger const MenzenMaxURLLength = 256;

static NSString *const MenzenAppleMusic = @"com.apple.Music";
static NSString *const MenzenApplePodcasts = @"com.apple.podcasts";

// Extras are whatever the app put there, so only URLs on the app's own hosts
// are passed on.
static NSString *MenzenURLOnHosts(NSString *url, NSArray<NSString *> *hosts) {
	if (url.length > MenzenMaxURLLength) return nil;
	NSURLComponents *components = url ? [NSURLComponents componentsWithString:url] : nil;
	if (![components.scheme isEqualToString:@"https"] || !components.host || components.user || components.password) return nil;
	for (NSString *host in hosts) {
		if ([components.host isEqualToString:host] || [components.host hasSuffix:[@"." stringByAppendingString:host]]) return url;
	}

	return nil;
}

// What the provider hook added; an older hook's plain https asset URL is the cover.
static NSDictionary<NSString *, NSString *> *MenzenTrackExtras(MenzenTrack *track) {
	NSDictionary *extras = MenzenExtrasFromURL(track.assetURL);
	if (extras) return extras;
	return track.assetURL ? @{MenzenExtrasCoverKey: track.assetURL} : @{};
}

// Apple Music's and Apple Podcasts' artwork identifiers point at Apple's image
// CDN, so the URL needs no lookup. They come in two forms:
//   library items: a path, "Music211/v4/c5/9f/69/<uuid>/<name>.jpg"
//   streamed items: a template, "https://is1-ssl.mzstatic.com/image/thumb/<path>/{w}x{h}bb.{f}"
static NSString *MenzenAppleArtworkURL(NSString *identifier) {
	if (!identifier.length || [identifier containsString:@".."]) return nil;

	if ([identifier hasPrefix:@"https://"]) {
		NSURLComponents *components = [NSURLComponents componentsWithString:identifier];
		if (!components) {
			NSString *escaped = [identifier stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLFragmentAllowedCharacterSet];
			components = [NSURLComponents componentsWithString:escaped];
		}
		if (![components.host isEqualToString:@"mzstatic.com"] && ![components.host hasSuffix:@".mzstatic.com"]) return nil;
		NSString *url = identifier;
		url = [url stringByReplacingOccurrencesOfString:@"{w}" withString:@"512"];
		url = [url stringByReplacingOccurrencesOfString:@"{h}" withString:@"512"];
		url = [url stringByReplacingOccurrencesOfString:@"{c}" withString:@"bb"];
		url = [url stringByReplacingOccurrencesOfString:@"{f}" withString:@"jpg"];
		return [url containsString:@"{"] ? nil : url;
	}

	if ([identifier hasPrefix:@"/"] || ![identifier containsString:@"/"]) return nil;
	NSString *path = [identifier stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
	if (!path) return nil;
	return [NSString stringWithFormat:@"https://is1-ssl.mzstatic.com/image/thumb/%@/512x512bb.jpg", path];
}

static NSString *MenzenArtworkURL(MenzenTrack *track, NSDictionary *extras) {
	if ([track.bundleIdentifier isEqualToString:MenzenAppleMusic] || [track.bundleIdentifier isEqualToString:MenzenApplePodcasts]) return MenzenAppleArtworkURL(track.artworkIdentifier);
	return MenzenURLOnHosts(extras[MenzenExtrasCoverKey], MenzenProviderForBundleIdentifier(track.bundleIdentifier)[MenzenProviderArtworkHostsKey]);
}

// Apple Music's catalog links redirect to the visitor's own storefront.
static NSString *MenzenAppleMusicURL(NSString *type, NSString *identifier) {
	return identifier ? [NSString stringWithFormat:@"https://music.apple.com/%@/%@", type, identifier] : nil;
}

// Apple Podcasts reports the episode's store ID and its show's as the album's.
static NSString *MenzenApplePodcastsURL(NSString *show, NSString *episode) {
	if (!show) return nil;
	NSString *url = [NSString stringWithFormat:@"https://podcasts.apple.com/podcast/id%@", show];
	return episode ? [url stringByAppendingFormat:@"?i=%@", episode] : url;
}

// Most podcast apps report plain audio, so a podcast is known by the app, the
// media type, or for Spotify the item's ID.
static BOOL MenzenTrackIsPodcast(MenzenTrack *track, NSDictionary *provider) {
	return [provider[MenzenProviderPodcastKey] boolValue] || [track.mediaType containsString:@"Podcast"] || [track.contentIdentifier hasPrefix:@"spotify:episode:"];
}

static BOOL MenzenSameText(NSString *a, NSString *b) {
	return a && b && [a caseInsensitiveCompare:b] == NSOrderedSame;
}

// A start (counting up) and, for the progress bar, an end.
static void MenzenSetTime(MenzenActivity *activity, MenzenTrack *track, NSTimeInterval elapsed, NSDate *now) {
	activity.startDate = [now dateByAddingTimeInterval:-elapsed];
	if ([MenzenPart(MenzenPartTime) isEqualToString:@"progress"] && track.duration > 0) activity.endDate = [activity.startDate dateByAddingTimeInterval:track.duration];
}

static MenzenActivityKind MenzenActivityKindForTrack(MenzenTrack *track, NSDictionary *provider) {
	if (!provider || [provider[MenzenProviderKindByMediaTypeKey] boolValue]) {
		if ([track.mediaType containsString:@"Video"]) return MenzenActivityKindWatching;
		if ([track.mediaType containsString:@"Music"] || [track.mediaType containsString:@"Audio"] || [track.mediaType containsString:@"Podcast"]) return MenzenActivityKindListening;
	}

	if (provider) return [provider[MenzenProviderWatchingKey] boolValue] ? MenzenActivityKindWatching : MenzenActivityKindListening;
	// Most apps don't say, so it's by what the app is. Browsers can't be told
	// apart: listening.
	return MenzenIsVideoApp(track.bundleIdentifier) ? MenzenActivityKindWatching : MenzenActivityKindListening;
}

static BOOL MenzenShowsAlbum(void) {
	if ([MenzenPart(MenzenPartHeading) isEqualToString:@"album"] || [MenzenPart(MenzenPartFirstLine) isEqualToString:@"album"] || [MenzenPart(MenzenPartSecondLine) isEqualToString:@"album"]) return YES;
	return [MenzenPart(MenzenPartThirdLine) isEqualToString:@"album"] && ![MenzenPart(MenzenPartBigPicture) isEqualToString:@"none"];
}

// Something watched has no album (or only its show again, like Pluto TV's),
// so its season and episode take the album's place, from the hook or the
// title. They leave the title only when the card shows them.
static void MenzenUseEpisodeAsAlbum(MenzenTrack *track, NSDictionary *extras, NSString **title, NSString **album) {
	NSInteger season = 0, episode = 0;
	NSString *rest = *title;
	BOOL inTitle = MenzenFindEpisode(*title, &season, &episode, &rest);
	if (extras[MenzenExtrasSeasonKey] || extras[MenzenExtrasEpisodeKey]) {
		season = [extras[MenzenExtrasSeasonKey] integerValue];
		episode = [extras[MenzenExtrasEpisodeKey] integerValue];
	}

	*album = MenzenEpisodeText(season, episode);
	if (*album && inTitle && MenzenShowsAlbum()) *title = rest;
}

static NSDictionary<NSString *, NSString *> *MenzenLinks(MenzenTrack *track, NSDictionary *extras, NSArray<NSString *> *hosts) {
	if (!MenzenSettingBool(MenzenSettingLinks, YES)) return @{};
	NSString *titleURL = extras[MenzenExtrasTitleURLKey];
	NSString *artistURL = extras[MenzenExtrasArtistURLKey];
	NSString *albumURL = extras[MenzenExtrasAlbumURLKey];
	if ([track.bundleIdentifier isEqualToString:MenzenAppleMusic]) {
		titleURL = titleURL ?: MenzenAppleMusicURL(@"song", track.storeIdentifier);
		artistURL = artistURL ?: MenzenAppleMusicURL(@"artist", track.artistStoreIdentifier);
		albumURL = albumURL ?: MenzenAppleMusicURL(@"album", track.albumStoreIdentifier);
	}
	if ([track.bundleIdentifier isEqualToString:MenzenApplePodcasts]) {
		titleURL = titleURL ?: MenzenApplePodcastsURL(track.albumStoreIdentifier, track.storeIdentifier);
		artistURL = artistURL ?: MenzenApplePodcastsURL(track.albumStoreIdentifier, nil);
	}

	titleURL = MenzenURLOnHosts(titleURL, hosts);
	artistURL = MenzenURLOnHosts(artistURL, hosts);
	albumURL = MenzenURLOnHosts(albumURL, hosts);

	NSMutableDictionary *links = [NSMutableDictionary dictionary];
	links[@"title"] = titleURL;
	links[@"artist"] = artistURL;
	links[@"album"] = albumURL ?: titleURL;
	links[@"cover"] = albumURL ?: titleURL;
	links[@"artistImage"] = artistURL;
	return links;
}

BOOL MenzenTrackIsShowable(MenzenTrack *track) {
	return track.title.length && ![track.contentIdentifier hasPrefix:@"spotify:ad:"];
}

MenzenActivity *MenzenActivityForTrack(MenzenTrack *track, NSString *logo) {
	if (!MenzenTrackIsShowable(track)) return nil;

	NSDictionary *provider = MenzenProviderForBundleIdentifier(track.bundleIdentifier);
	if (MenzenSettingBool(MenzenSettingPrivacy, NO)) {
		MenzenActivity *activity = [MenzenActivity new];
		activity.kind = MenzenActivityKindForTrack(track, provider);
		activity.statusDisplay = MenzenStatusDisplayName;
		activity.name = MenzenAppName(track.bundleIdentifier);
		activity.largeImageURL = logo;
		return activity;
	}

	NSDictionary *extras = provider ? MenzenTrackExtras(track) : @{};
	NSString *appName = MenzenAppName(track.bundleIdentifier);
	NSString *artistName = extras[MenzenExtrasArtistNameKey] ?: track.artist;

	MenzenActivity *activity = [MenzenActivity new];
	activity.kind = MenzenActivityKindForTrack(track, provider);

	NSString *title = track.title;
	// Podcast apps each put something else in the album (the show again, a
	// date, a season and episode), so there's none. The artist is the show.
	NSString *album = MenzenTrackIsPodcast(track, provider) ? nil : track.album;
	if (activity.kind == MenzenActivityKindWatching && (!album.length || MenzenSameText(album, track.artist))) MenzenUseEpisodeAsAlbum(track, extras, &title, &album);

	NSDictionary<NSString *, NSString *> *texts = @{
		@"title": title,
		@"artist": track.artist ?: @"",
		@"album": album ?: @"",
	};
	NSDictionary<NSString *, NSString *> *images = @{
		@"cover": MenzenArtworkURL(track, extras) ?: @"",
		@"artistImage": MenzenURLOnHosts(extras[MenzenExtrasArtistImageKey], provider[MenzenProviderArtworkHostsKey]) ?: @"",
		@"logo": logo ?: @"",
	};
	NSDictionary<NSString *, NSString *> *links = MenzenLinks(track, extras, provider[MenzenProviderLinkHostsKey]);

	// Discord needs a first line; the title stands in for a missing album.
	NSString *firstLine = MenzenPart(MenzenPartFirstLine);
	if (![texts[firstLine] length]) firstLine = @"title";
	activity.details = texts[firstLine];
	activity.detailsURL = links[firstLine];

	// Lines repeating one above aren't shown, like singles named after
	// their album.
	NSString *secondLine = MenzenPart(MenzenPartSecondLine);
	NSString *state = texts[secondLine];
	if (state.length && !MenzenSameText(state, activity.details)) {
		activity.state = state;
		activity.stateURL = links[secondLine];
	}

	// Without a name, Discord uses the application's: "Menzen".
	NSString *heading = MenzenPart(MenzenPartHeading);
	NSString *headingText = [MenzenSettingString(MenzenSettingHeadingText, @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if ([heading isEqualToString:@"custom"]) activity.name = headingText.length ? headingText : nil;
	else if ([heading isEqualToString:@"app"]) activity.name = appName;
	else if (![heading isEqualToString:@"menzen"]) activity.name = [texts[heading] length] ? texts[heading] : appName;

	NSString *bigPicture = MenzenPart(MenzenPartBigPicture);
	if (![bigPicture isEqualToString:@"none"]) {
		// A cover or artist picture the app doesn't have: its logo.
		if (![images[bigPicture] length]) bigPicture = @"logo";
		activity.largeImageURL = [images[bigPicture] length] ? images[bigPicture] : nil;
	}

	if (activity.largeImageURL) {
		activity.largeURL = links[bigPicture];
		NSString *thirdLine = texts[MenzenPart(MenzenPartThirdLine)];
		if (thirdLine.length && !MenzenSameText(thirdLine, activity.details) && !MenzenSameText(thirdLine, activity.state)) activity.largeText = thirdLine;

		// Discord only shows a small picture over a big one.
		NSString *smallPicture = MenzenPart(MenzenPartSmallPicture);
		NSString *smallImageURL = images[smallPicture];
		if (smallImageURL.length && ![smallImageURL isEqualToString:activity.largeImageURL]) {
			activity.smallImageURL = smallImageURL;
			activity.smallURL = links[smallPicture];
			NSString *smallText = MenzenPart(MenzenPartSmallPictureText);
			if ([smallText isEqualToString:@"artist"]) activity.smallText = artistName;
			if ([smallText isEqualToString:@"app"]) activity.smallText = appName;
		}
	}

	// The first line when the choice isn't on the card (or its line was left out).
	NSString *memberList = MenzenMemberListDisplay();
	if ([memberList isEqualToString:@"state"] && activity.state) activity.statusDisplay = MenzenStatusDisplayState;
	if ([memberList isEqualToString:@"name"]) activity.statusDisplay = MenzenStatusDisplayName;

	if (track.playing) {
		NSDate *now = NSDate.date;
		MenzenSetTime(activity, track, [track elapsedAtDate:now], now);
	}

	return activity;
}

MenzenActivity *MenzenPreviewForTrack(MenzenTrack *track, NSString *logo, NSDate *stoppedDate, NSDate **pausedDate) {
	MenzenActivity *activity = MenzenActivityForTrack(track, logo);
	*pausedDate = nil;
	if (!activity || (track.playing && !stoppedDate) || MenzenSettingBool(MenzenSettingPrivacy, NO)) return activity;
	NSDate *now = NSDate.date;
	NSTimeInterval elapsed = MAX([track elapsedAtDate:stoppedDate ?: now], 0);
	if (track.duration > 0) elapsed = MIN(elapsed, track.duration);
	MenzenSetTime(activity, track, elapsed, now);
	if (activity.startDate) *pausedDate = now;
	return activity;
}
