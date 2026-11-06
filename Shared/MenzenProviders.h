#import <Foundation/Foundation.h>

// The apps Menzen knows how to show. Each one can be switched off in
// settings; anything else only shows with the experimental "Other Apps"
// source. Some also have a hook in Providers/<App> for what MediaRemote lacks.

NS_ASSUME_NONNULL_BEGIN

#define MenzenProviderBundleIdentifierKey @"bundleIdentifier"
// What Discord shows: "Listening to <name>", or "Watching <name>" for apps
// with MenzenProviderWatchingKey.
#define MenzenProviderNameKey @"name"
#define MenzenProviderWatchingKey @"watching"
// BOOL: listening or watching by what's playing, when the app says (see
// MenzenTrack.mediaType), else by MenzenProviderWatchingKey.
#define MenzenProviderKindByMediaTypeKey @"kindByMediaType"
// BOOL: everything it plays is a podcast, whatever it says (most podcast apps
// report plain audio).
#define MenzenProviderPodcastKey @"podcast"
// Image hosts the app's cover URLs may come from.
#define MenzenProviderArtworkHostsKey @"artworkHosts"
// Hosts the app's links (track, artist, album) may point at.
#define MenzenProviderLinkHostsKey @"linkHosts"

static inline NSArray<NSDictionary<NSString *, id> *> *MenzenProviders(void) {
	static NSArray *providers;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		providers = @[
			// Listening
			@{
				MenzenProviderBundleIdentifierKey: @"com.amazon.mp3.AmazonCloudPlayer",
				MenzenProviderNameKey: @"Amazon Music",
				MenzenProviderArtworkHostsKey: @[@"m.media-amazon.com"],
				MenzenProviderLinkHostsKey: @[@"music.amazon.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.apple.Music",
				MenzenProviderNameKey: @"Apple Music",
				MenzenProviderArtworkHostsKey: @[@"mzstatic.com"],
				MenzenProviderLinkHostsKey: @[@"music.apple.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.apple.podcasts",
				MenzenProviderNameKey: @"Apple Podcasts",
				MenzenProviderPodcastKey: @YES,
				MenzenProviderArtworkHostsKey: @[@"mzstatic.com"],
				MenzenProviderLinkHostsKey: @[@"podcasts.apple.com"],
				// Video podcasts show as watching.
				MenzenProviderKindByMediaTypeKey: @YES,
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.audiomack.iphone",
				MenzenProviderNameKey: @"Audiomack",
				MenzenProviderArtworkHostsKey: @[@"audiomack.com"],
				MenzenProviderLinkHostsKey: @[@"audiomack.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"co.supertop.Castro-2",
				MenzenProviderNameKey: @"Castro",
				MenzenProviderPodcastKey: @YES,
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.deezer.Deezer",
				MenzenProviderNameKey: @"Deezer",
				MenzenProviderArtworkHostsKey: @[@"cdn-images.dzcdn.net"],
				MenzenProviderLinkHostsKey: @[@"www.deezer.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"fm.overcast.overcast",
				MenzenProviderNameKey: @"Overcast",
				MenzenProviderPodcastKey: @YES,
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.pandora",
				MenzenProviderNameKey: @"Pandora",
				MenzenProviderArtworkHostsKey: @[@"content-images.p-cdn.com"],
				MenzenProviderLinkHostsKey: @[@"www.pandora.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"au.com.shiftyjelly.podcasts",
				MenzenProviderNameKey: @"Pocket Casts",
				MenzenProviderPodcastKey: @YES,
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.qobuz.music",
				MenzenProviderNameKey: @"Qobuz",
				MenzenProviderArtworkHostsKey: @[@"static.qobuz.com"],
				MenzenProviderLinkHostsKey: @[@"open.qobuz.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.soundcloud.TouchApp",
				MenzenProviderNameKey: @"SoundCloud",
				MenzenProviderArtworkHostsKey: @[@"sndcdn.com"],
				MenzenProviderLinkHostsKey: @[@"soundcloud.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.spotify.client",
				MenzenProviderNameKey: @"Spotify",
				MenzenProviderArtworkHostsKey: @[@"i.scdn.co", @"spotifycdn.com"],
				MenzenProviderLinkHostsKey: @[@"open.spotify.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.aspiro.TIDAL",
				MenzenProviderNameKey: @"TIDAL",
				MenzenProviderArtworkHostsKey: @[@"resources.tidal.com"],
				MenzenProviderLinkHostsKey: @[@"tidal.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.google.ios.youtubemusic",
				MenzenProviderNameKey: @"YouTube Music",
				MenzenProviderArtworkHostsKey: @[@"googleusercontent.com", @"i.ytimg.com"],
				MenzenProviderLinkHostsKey: @[@"music.youtube.com"],
			},
			// Watching
			@{
				MenzenProviderBundleIdentifierKey: @"com.apple.tv",
				MenzenProviderNameKey: @"Apple TV",
				MenzenProviderWatchingKey: @YES,
				MenzenProviderArtworkHostsKey: @[@"mzstatic.com"],
				MenzenProviderLinkHostsKey: @[@"tv.apple.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.crunchyroll.iphone",
				MenzenProviderNameKey: @"Crunchyroll",
				MenzenProviderWatchingKey: @YES,
				MenzenProviderArtworkHostsKey: @[@"imgsrv.crunchyroll.com"],
				MenzenProviderLinkHostsKey: @[@"www.crunchyroll.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.disney.disneyplus",
				MenzenProviderNameKey: @"Disney+",
				MenzenProviderWatchingKey: @YES,
				MenzenProviderArtworkHostsKey: @[@"disney.images.edge.bamgrid.com"],
				MenzenProviderLinkHostsKey: @[@"www.disneyplus.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.wbd.stream",
				MenzenProviderNameKey: @"HBO Max",
				MenzenProviderWatchingKey: @YES,
				MenzenProviderArtworkHostsKey: @[@"discomax.com", @"hbomax.com", @"max.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.hulu.plus",
				MenzenProviderNameKey: @"Hulu",
				MenzenProviderWatchingKey: @YES,
				MenzenProviderArtworkHostsKey: @[@"hulu.com"],
				MenzenProviderLinkHostsKey: @[@"www.hulu.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.kick.mobile",
				MenzenProviderNameKey: @"Kick",
				MenzenProviderWatchingKey: @YES,
				MenzenProviderArtworkHostsKey: @[@"images.kick.com"],
				MenzenProviderLinkHostsKey: @[@"kick.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.netflix.Netflix",
				MenzenProviderNameKey: @"Netflix",
				MenzenProviderWatchingKey: @YES,
				MenzenProviderArtworkHostsKey: @[@"nflxso.net"],
				MenzenProviderLinkHostsKey: @[@"www.netflix.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.cbsvideo.app",
				MenzenProviderNameKey: @"Paramount+",
				MenzenProviderWatchingKey: @YES,
				MenzenProviderArtworkHostsKey: @[@"thumbnails.cbsig.net", @"pplusstatic.com"],
				MenzenProviderLinkHostsKey: @[@"paramountplus.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.peacocktv.peacock",
				MenzenProviderNameKey: @"Peacock",
				MenzenProviderWatchingKey: @YES,
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.plexapp.plex",
				MenzenProviderNameKey: @"Plex",
				MenzenProviderWatchingKey: @YES,
				MenzenProviderArtworkHostsKey: @[@"plex.tv"],
				MenzenProviderLinkHostsKey: @[@"watch.plex.tv"],
				// Plex plays music too.
				MenzenProviderKindByMediaTypeKey: @YES,
			},
			@{
				MenzenProviderBundleIdentifierKey: @"tv.pluto.ios",
				MenzenProviderNameKey: @"Pluto TV",
				MenzenProviderWatchingKey: @YES,
				MenzenProviderArtworkHostsKey: @[@"thumbnails.cbsig.net", @"wwwimage-us.plutostatic.tv"],
				MenzenProviderLinkHostsKey: @[@"pluto.tv"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.amazon.aiv.AIVApp",
				MenzenProviderNameKey: @"Prime Video",
				MenzenProviderWatchingKey: @YES,
				MenzenProviderArtworkHostsKey: @[@"m.media-amazon.com", @"ssl-images-amazon.com"],
				MenzenProviderLinkHostsKey: @[@"www.primevideo.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.adrise.tubitv",
				MenzenProviderNameKey: @"Tubi",
				MenzenProviderWatchingKey: @YES,
				MenzenProviderArtworkHostsKey: @[@"tubitv.com"],
				MenzenProviderLinkHostsKey: @[@"tubitv.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"tv.twitch",
				MenzenProviderNameKey: @"Twitch",
				MenzenProviderWatchingKey: @YES,
				MenzenProviderArtworkHostsKey: @[@"static-cdn.jtvnw.net"],
				MenzenProviderLinkHostsKey: @[@"www.twitch.tv"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.google.ios.youtube",
				MenzenProviderNameKey: @"YouTube",
				MenzenProviderWatchingKey: @YES,
				MenzenProviderArtworkHostsKey: @[@"i.ytimg.com", @"yt3.ggpht.com"],
				MenzenProviderLinkHostsKey: @[@"www.youtube.com"],
			},
			@{
				MenzenProviderBundleIdentifierKey: @"com.google.ios.youtubeunplugged",
				MenzenProviderNameKey: @"YouTube TV",
				MenzenProviderWatchingKey: @YES,
				MenzenProviderArtworkHostsKey: @[@"ggpht.com"],
				MenzenProviderLinkHostsKey: @[@"tv.youtube.com"],
			},
		];
	});
	return providers;
}

static inline NSDictionary<NSString *, id> *_Nullable MenzenProviderForBundleIdentifier(NSString *_Nullable bundleIdentifier) {
	for (NSDictionary *provider in MenzenProviders()) {
		if ([provider[MenzenProviderBundleIdentifierKey] isEqualToString:bundleIdentifier]) return provider;
	}
	return nil;
}

NS_ASSUME_NONNULL_END
