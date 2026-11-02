#import <Foundation/Foundation.h>

// The apps Menzen knows how to show. Each one can be switched off in
// settings; anything else only shows with the experimental "Other Apps"
// source. Some also have a hook in Providers/<App> for what MediaRemote lacks.

NS_ASSUME_NONNULL_BEGIN

#define MZProviderBundleIdentifierKey @"bundleIdentifier"
// What Discord shows: "Listening to <name>", or "Watching <name>" for apps
// with MZProviderWatchingKey.
#define MZProviderNameKey @"name"
#define MZProviderWatchingKey @"watching"
// BOOL: listening or watching by what's playing, when the app says (see
// MZTrack.mediaType), else by MZProviderWatchingKey.
#define MZProviderKindByMediaTypeKey @"kindByMediaType"
// Image hosts the app's cover URLs may come from.
#define MZProviderArtworkHostsKey @"artworkHosts"
// Hosts the app's links (track, artist, album) may point at.
#define MZProviderLinkHostsKey @"linkHosts"

static inline NSArray<NSDictionary<NSString *, id> *> *MZProviders(void) {
	static NSArray *providers;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		providers = @[
			// Listening
			@{
				MZProviderBundleIdentifierKey: @"com.amazon.mp3.AmazonCloudPlayer",
				MZProviderNameKey: @"Amazon Music",
				MZProviderArtworkHostsKey: @[@"m.media-amazon.com"],
				MZProviderLinkHostsKey: @[@"music.amazon.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.apple.Music",
				MZProviderNameKey: @"Apple Music",
				MZProviderArtworkHostsKey: @[@"mzstatic.com"],
				MZProviderLinkHostsKey: @[@"music.apple.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.audiomack.iphone",
				MZProviderNameKey: @"Audiomack",
				MZProviderArtworkHostsKey: @[@"audiomack.com"],
				MZProviderLinkHostsKey: @[@"audiomack.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.deezer.Deezer",
				MZProviderNameKey: @"Deezer",
				MZProviderArtworkHostsKey: @[@"cdn-images.dzcdn.net"],
				MZProviderLinkHostsKey: @[@"www.deezer.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.pandora",
				MZProviderNameKey: @"Pandora",
				MZProviderArtworkHostsKey: @[@"content-images.p-cdn.com"],
				MZProviderLinkHostsKey: @[@"www.pandora.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.qobuz.music",
				MZProviderNameKey: @"Qobuz",
				MZProviderArtworkHostsKey: @[@"static.qobuz.com"],
				MZProviderLinkHostsKey: @[@"open.qobuz.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.spotify.client",
				MZProviderNameKey: @"Spotify",
				MZProviderArtworkHostsKey: @[@"i.scdn.co", @"spotifycdn.com"],
				MZProviderLinkHostsKey: @[@"open.spotify.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.aspiro.TIDAL",
				MZProviderNameKey: @"TIDAL",
				MZProviderArtworkHostsKey: @[@"resources.tidal.com"],
				MZProviderLinkHostsKey: @[@"tidal.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.google.ios.youtubemusic",
				MZProviderNameKey: @"YouTube Music",
				MZProviderArtworkHostsKey: @[@"googleusercontent.com", @"i.ytimg.com"],
				MZProviderLinkHostsKey: @[@"music.youtube.com"],
			},
			// Watching
			@{
				MZProviderBundleIdentifierKey: @"com.apple.tv",
				MZProviderNameKey: @"Apple TV",
				MZProviderWatchingKey: @YES,
				MZProviderArtworkHostsKey: @[@"mzstatic.com"],
				MZProviderLinkHostsKey: @[@"tv.apple.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.crunchyroll.iphone",
				MZProviderNameKey: @"Crunchyroll",
				MZProviderWatchingKey: @YES,
				MZProviderArtworkHostsKey: @[@"imgsrv.crunchyroll.com"],
				MZProviderLinkHostsKey: @[@"www.crunchyroll.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.disney.disneyplus",
				MZProviderNameKey: @"Disney+",
				MZProviderWatchingKey: @YES,
				MZProviderArtworkHostsKey: @[@"disney.images.edge.bamgrid.com"],
				MZProviderLinkHostsKey: @[@"www.disneyplus.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.wbd.stream",
				MZProviderNameKey: @"HBO Max",
				MZProviderWatchingKey: @YES,
				MZProviderArtworkHostsKey: @[@"discomax.com", @"hbomax.com", @"max.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.hulu.plus",
				MZProviderNameKey: @"Hulu",
				MZProviderWatchingKey: @YES,
				MZProviderArtworkHostsKey: @[@"hulu.com"],
				MZProviderLinkHostsKey: @[@"www.hulu.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.kick.mobile",
				MZProviderNameKey: @"Kick",
				MZProviderWatchingKey: @YES,
				MZProviderArtworkHostsKey: @[@"images.kick.com"],
				MZProviderLinkHostsKey: @[@"kick.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.netflix.Netflix",
				MZProviderNameKey: @"Netflix",
				MZProviderWatchingKey: @YES,
				MZProviderArtworkHostsKey: @[@"nflxso.net"],
				MZProviderLinkHostsKey: @[@"www.netflix.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.cbsvideo.app",
				MZProviderNameKey: @"Paramount+",
				MZProviderWatchingKey: @YES,
				MZProviderArtworkHostsKey: @[@"thumbnails.cbsig.net", @"pplusstatic.com"],
				MZProviderLinkHostsKey: @[@"paramountplus.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.peacocktv.peacock",
				MZProviderNameKey: @"Peacock",
				MZProviderWatchingKey: @YES,
			},
			@{
				MZProviderBundleIdentifierKey: @"com.plexapp.plex",
				MZProviderNameKey: @"Plex",
				MZProviderWatchingKey: @YES,
				MZProviderArtworkHostsKey: @[@"plex.tv"],
				MZProviderLinkHostsKey: @[@"watch.plex.tv"],
				// Plex plays music too.
				MZProviderKindByMediaTypeKey: @YES,
			},
			@{
				MZProviderBundleIdentifierKey: @"tv.pluto.ios",
				MZProviderNameKey: @"Pluto TV",
				MZProviderWatchingKey: @YES,
				MZProviderArtworkHostsKey: @[@"thumbnails.cbsig.net", @"wwwimage-us.plutostatic.tv"],
				MZProviderLinkHostsKey: @[@"pluto.tv"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.amazon.aiv.AIVApp",
				MZProviderNameKey: @"Prime Video",
				MZProviderWatchingKey: @YES,
				MZProviderArtworkHostsKey: @[@"m.media-amazon.com", @"ssl-images-amazon.com"],
				MZProviderLinkHostsKey: @[@"www.primevideo.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.adrise.tubitv",
				MZProviderNameKey: @"Tubi",
				MZProviderWatchingKey: @YES,
				MZProviderArtworkHostsKey: @[@"tubitv.com"],
				MZProviderLinkHostsKey: @[@"tubitv.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"tv.twitch",
				MZProviderNameKey: @"Twitch",
				MZProviderWatchingKey: @YES,
				MZProviderArtworkHostsKey: @[@"static-cdn.jtvnw.net"],
				MZProviderLinkHostsKey: @[@"www.twitch.tv"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.google.ios.youtube",
				MZProviderNameKey: @"YouTube",
				MZProviderWatchingKey: @YES,
				MZProviderArtworkHostsKey: @[@"i.ytimg.com"],
				MZProviderLinkHostsKey: @[@"www.youtube.com"],
			},
			@{
				MZProviderBundleIdentifierKey: @"com.google.ios.youtubeunplugged",
				MZProviderNameKey: @"YouTube TV",
				MZProviderWatchingKey: @YES,
				MZProviderArtworkHostsKey: @[@"ggpht.com"],
				MZProviderLinkHostsKey: @[@"tv.youtube.com"],
			},
		];
	});
	return providers;
}

static inline NSDictionary<NSString *, id> *_Nullable MZProviderForBundleIdentifier(NSString *_Nullable bundleIdentifier) {
	for (NSDictionary *provider in MZProviders()) {
		if ([provider[MZProviderBundleIdentifierKey] isEqualToString:bundleIdentifier]) return provider;
	}
	return nil;
}

NS_ASSUME_NONNULL_END
