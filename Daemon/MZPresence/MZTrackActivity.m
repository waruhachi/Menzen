#import "../../Shared/MZCard.h"
#import "../../Shared/MZProviders.h"
#import "../../Shared/MZTrackExtras.h"
#import "../MZApps/MZAppInfo.h"
#import "MZEpisode.h"
#import "MZTrackActivity.h"

// Discord rejects longer URLs.
static NSUInteger const MZMaxURLLength = 256;

static NSString *const MZAppleMusic = @"com.apple.Music";

// Extras are whatever the app put there, so only URLs on the app's own hosts
// are passed on.
static NSString *MZURLOnHosts(NSString *url, NSArray<NSString *> *hosts) {
	if (url.length > MZMaxURLLength) return nil;
	NSURLComponents *components = url ? [NSURLComponents componentsWithString:url] : nil;
	if (![components.scheme isEqualToString:@"https"] || !components.host || components.user || components.password) return nil;
	for (NSString *host in hosts) {
		if ([components.host isEqualToString:host] || [components.host hasSuffix:[@"." stringByAppendingString:host]]) return url;
	}

	return nil;
}

// What the provider hook added; an older hook's plain https asset URL is the cover.
static NSDictionary<NSString *, NSString *> *MZTrackExtras(MZTrack *track) {
	NSDictionary *extras = MZExtrasFromURL(track.assetURL);
	if (extras) return extras;
	return track.assetURL ? @{MZExtrasCoverKey: track.assetURL} : @{};
}

// Apple Music's artwork identifier points at its image CDN, so the URL needs
// no lookup. It comes in two forms:
//   library items: a path, "Music211/v4/c5/9f/69/<uuid>/<name>.jpg"
//   streamed items: a template, "https://is1-ssl.mzstatic.com/image/thumb/<path>/{w}x{h}bb.{f}"
static NSString *MZAppleMusicArtworkURL(NSString *identifier) {
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

static NSString *MZArtworkURL(MZTrack *track, NSDictionary *extras) {
	if ([track.bundleIdentifier isEqualToString:MZAppleMusic]) return MZAppleMusicArtworkURL(track.artworkIdentifier);
	return MZURLOnHosts(extras[MZExtrasCoverKey], MZProviderForBundleIdentifier(track.bundleIdentifier)[MZProviderArtworkHostsKey]);
}

// Apple Music's catalog links redirect to the visitor's own storefront.
static NSString *MZAppleMusicURL(NSString *type, NSString *identifier) {
	return identifier ? [NSString stringWithFormat:@"https://music.apple.com/%@/%@", type, identifier] : nil;
}

static BOOL MZSameText(NSString *a, NSString *b) {
	return a && b && [a caseInsensitiveCompare:b] == NSOrderedSame;
}

// A start (counting up) and, for the progress bar, an end.
static void MZSetTime(MZActivity *activity, MZTrack *track, NSTimeInterval elapsed, NSDate *now) {
	activity.startDate = [now dateByAddingTimeInterval:-elapsed];
	if ([MZPart(MZPartTime) isEqualToString:@"progress"] && track.duration > 0) activity.endDate = [activity.startDate dateByAddingTimeInterval:track.duration];
}

static MZActivityKind MZActivityKindForTrack(MZTrack *track, NSDictionary *provider) {
	if (!provider || [provider[MZProviderKindByMediaTypeKey] boolValue]) {
		if ([track.mediaType containsString:@"Video"]) return MZActivityKindWatching;
		if ([track.mediaType containsString:@"Music"] || [track.mediaType containsString:@"Audio"] || [track.mediaType containsString:@"Podcast"]) return MZActivityKindListening;
	}

	if (provider) return [provider[MZProviderWatchingKey] boolValue] ? MZActivityKindWatching : MZActivityKindListening;
	// Most apps don't say, so it's by what the app is. Browsers can't be told
	// apart: listening.
	return MZIsVideoApp(track.bundleIdentifier) ? MZActivityKindWatching : MZActivityKindListening;
}

static BOOL MZShowsAlbum(void) {
	if ([MZPart(MZPartHeading) isEqualToString:@"album"] || [MZPart(MZPartFirstLine) isEqualToString:@"album"] || [MZPart(MZPartSecondLine) isEqualToString:@"album"]) return YES;
	return [MZPart(MZPartThirdLine) isEqualToString:@"album"] && ![MZPart(MZPartBigPicture) isEqualToString:@"none"];
}

// Something watched has no album (or only its show again, like Pluto TV's),
// so its season and episode take the album's place, from the hook or the
// title. They leave the title only when the card shows them.
static void MZUseEpisodeAsAlbum(MZTrack *track, NSDictionary *extras, NSString **title, NSString **album) {
	NSInteger season = 0, episode = 0;
	NSString *rest = *title;
	BOOL inTitle = MZFindEpisode(*title, &season, &episode, &rest);
	if (extras[MZExtrasSeasonKey] || extras[MZExtrasEpisodeKey]) {
		season = [extras[MZExtrasSeasonKey] integerValue];
		episode = [extras[MZExtrasEpisodeKey] integerValue];
	}

	*album = MZEpisodeText(season, episode);
	if (*album && inTitle && MZShowsAlbum()) *title = rest;
}

static NSDictionary<NSString *, NSString *> *MZLinks(MZTrack *track, NSDictionary *extras, NSArray<NSString *> *hosts) {
	if (!MZSettingBool(MZSettingLinks, YES)) return @{};
	NSString *titleURL = extras[MZExtrasTitleURLKey];
	NSString *artistURL = extras[MZExtrasArtistURLKey];
	NSString *albumURL = extras[MZExtrasAlbumURLKey];
	if ([track.bundleIdentifier isEqualToString:MZAppleMusic]) {
		titleURL = titleURL ?: MZAppleMusicURL(@"song", track.storeIdentifier);
		artistURL = artistURL ?: MZAppleMusicURL(@"artist", track.artistStoreIdentifier);
		albumURL = albumURL ?: MZAppleMusicURL(@"album", track.albumStoreIdentifier);
	}

	titleURL = MZURLOnHosts(titleURL, hosts);
	artistURL = MZURLOnHosts(artistURL, hosts);
	albumURL = MZURLOnHosts(albumURL, hosts);

	NSMutableDictionary *links = [NSMutableDictionary dictionary];
	links[@"title"] = titleURL;
	links[@"artist"] = artistURL;
	links[@"album"] = albumURL ?: titleURL;
	links[@"cover"] = albumURL ?: titleURL;
	links[@"artistImage"] = artistURL;
	return links;
}

BOOL MZTrackIsShowable(MZTrack *track) {
	return track.title.length && ![track.contentIdentifier hasPrefix:@"spotify:ad:"];
}

MZActivity *MZActivityForTrack(MZTrack *track, NSString *logo) {
	if (!MZTrackIsShowable(track)) return nil;

	NSDictionary *provider = MZProviderForBundleIdentifier(track.bundleIdentifier);
	if (MZSettingBool(MZSettingPrivacy, NO)) {
		MZActivity *activity = [MZActivity new];
		activity.kind = MZActivityKindForTrack(track, provider);
		activity.statusDisplay = MZStatusDisplayName;
		activity.name = MZAppName(track.bundleIdentifier);
		activity.largeImageURL = logo;
		return activity;
	}

	NSDictionary *extras = provider ? MZTrackExtras(track) : @{};
	NSString *appName = MZAppName(track.bundleIdentifier);
	NSString *artistName = extras[MZExtrasArtistNameKey] ?: track.artist;

	MZActivity *activity = [MZActivity new];
	activity.kind = MZActivityKindForTrack(track, provider);

	NSString *title = track.title;
	NSString *album = track.album;
	if (activity.kind == MZActivityKindWatching && (!album.length || MZSameText(album, track.artist))) MZUseEpisodeAsAlbum(track, extras, &title, &album);

	NSDictionary<NSString *, NSString *> *texts = @{
		@"title": title,
		@"artist": track.artist ?: @"",
		@"album": album ?: @"",
	};
	NSDictionary<NSString *, NSString *> *images = @{
		@"cover": MZArtworkURL(track, extras) ?: @"",
		@"artistImage": MZURLOnHosts(extras[MZExtrasArtistImageKey], provider[MZProviderArtworkHostsKey]) ?: @"",
		@"logo": logo ?: @"",
	};
	NSDictionary<NSString *, NSString *> *links = MZLinks(track, extras, provider[MZProviderLinkHostsKey]);

	// Discord needs a first line; the title stands in for a missing album.
	NSString *firstLine = MZPart(MZPartFirstLine);
	if (![texts[firstLine] length]) firstLine = @"title";
	activity.details = texts[firstLine];
	activity.detailsURL = links[firstLine];

	// Lines repeating one above aren't shown, like singles named after
	// their album.
	NSString *secondLine = MZPart(MZPartSecondLine);
	NSString *state = texts[secondLine];
	if (state.length && !MZSameText(state, activity.details)) {
		activity.state = state;
		activity.stateURL = links[secondLine];
	}

	// Without a name, Discord uses the application's: "Menzen".
	NSString *heading = MZPart(MZPartHeading);
	NSString *headingText = [MZSettingString(MZSettingHeadingText, @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if ([heading isEqualToString:@"custom"]) activity.name = headingText.length ? headingText : nil;
	else if ([heading isEqualToString:@"app"]) activity.name = appName;
	else if (![heading isEqualToString:@"menzen"]) activity.name = [texts[heading] length] ? texts[heading] : appName;

	NSString *bigPicture = MZPart(MZPartBigPicture);
	if (![bigPicture isEqualToString:@"none"]) {
		// A cover or artist picture the app doesn't have: its logo.
		if (![images[bigPicture] length]) bigPicture = @"logo";
		activity.largeImageURL = [images[bigPicture] length] ? images[bigPicture] : nil;
	}

	if (activity.largeImageURL) {
		activity.largeURL = links[bigPicture];
		NSString *thirdLine = texts[MZPart(MZPartThirdLine)];
		if (thirdLine.length && !MZSameText(thirdLine, activity.details) && !MZSameText(thirdLine, activity.state)) activity.largeText = thirdLine;

		// Discord only shows a small picture over a big one.
		NSString *smallPicture = MZPart(MZPartSmallPicture);
		NSString *smallImageURL = images[smallPicture];
		if (smallImageURL.length && ![smallImageURL isEqualToString:activity.largeImageURL]) {
			activity.smallImageURL = smallImageURL;
			activity.smallURL = links[smallPicture];
			NSString *smallText = MZPart(MZPartSmallPictureText);
			if ([smallText isEqualToString:@"artist"]) activity.smallText = artistName;
			if ([smallText isEqualToString:@"app"]) activity.smallText = appName;
		}
	}

	// The first line when the choice isn't on the card (or its line was left out).
	NSString *memberList = MZMemberListDisplay();
	if ([memberList isEqualToString:@"state"] && activity.state) activity.statusDisplay = MZStatusDisplayState;
	if ([memberList isEqualToString:@"name"]) activity.statusDisplay = MZStatusDisplayName;

	if (track.playing) {
		NSDate *now = NSDate.date;
		MZSetTime(activity, track, [track elapsedAtDate:now], now);
	}

	return activity;
}

MZActivity *MZPreviewForTrack(MZTrack *track, NSString *logo, NSDate *stoppedDate, NSDate **pausedDate) {
	MZActivity *activity = MZActivityForTrack(track, logo);
	*pausedDate = nil;
	if (!activity || (track.playing && !stoppedDate) || MZSettingBool(MZSettingPrivacy, NO)) return activity;
	NSDate *now = NSDate.date;
	NSTimeInterval elapsed = MAX([track elapsedAtDate:stoppedDate ?: now], 0);
	if (track.duration > 0) elapsed = MIN(elapsed, track.duration);
	MZSetTime(activity, track, elapsed, now);
	if (activity.startDate) *pausedDate = now;
	return activity;
}
