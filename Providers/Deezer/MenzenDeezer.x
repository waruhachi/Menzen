#import "../../Shared/MZProvider/MZProvider.h"

// The app publishes no IDs; +[DZRAudioPlayer sharedAudioPlayer].currentTrack
// has them, and the cover and artist picture hashes (coverSeed).

// Uploads and other local tracks have none.
static NSString *MZCatalogID(id value) {
	NSString *ID = MZString(value);
	NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
	return ID && ID.length <= 20 && [ID rangeOfCharacterFromSet:digits.invertedSet].location == NSNotFound && ![ID isEqualToString:@"0"] ? ID : nil;
}

static NSString *MZSeed(id value) {
	NSString *seed = MZString(value);
	NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
	return seed.length == 32 && [seed rangeOfCharacterFromSet:hex.invertedSet].location == NSNotFound ? seed : nil;
}

static NSDictionary *MZExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	if (withExtras[MPNowPlayingInfoPropertyAssetURL]) return nil;
	id track = MZGet(MZGet(%c(DZRAudioPlayer), @"sharedAudioPlayer"), @"currentTrack");
	Class trackClass = %c(DeezerTrack);
	if (!trackClass || ![track isKindOfClass:trackClass]) return nil;

	// Only the playing track's.
	NSString *title = MZString(MZGet(track, @"title"));
	if (!title || ![title isEqualToString:MZString(info[MPMediaItemPropertyTitle])]) return nil;
	NSString *trackID = MZCatalogID(MZGet(track, @"deezerId"));
	// Catalog tracks have uploadId "0".
	if (!trackID || MZCatalogID(MZGet(track, @"uploadId"))) return nil;

	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	NSString *cover = MZSeed(MZGet(track, @"coverSeed"));
	if (cover) extras[MZExtrasCoverKey] = [NSString stringWithFormat:@"https://cdn-images.dzcdn.net/images/cover/%@/750x750-000000-80-0-0.jpg", cover];
	extras[MZExtrasTitleURLKey] = MZLinkURL(@"https://www.deezer.com/track/%@", trackID);
	extras[MZExtrasAlbumURLKey] = MZLinkURL(@"https://www.deezer.com/album/%@", MZCatalogID(MZGet(track, @"albumId")));

	id artist = MZGet(track, @"artist");
	NSString *artistID = MZCatalogID(MZGet(artist, @"deezerId"));
	if (artistID) {
		extras[MZExtrasArtistURLKey] = MZLinkURL(@"https://www.deezer.com/artist/%@", artistID);
		extras[MZExtrasArtistNameKey] = MZString(MZGet(artist, @"name"));
		NSString *picture = MZSeed(MZGet(artist, @"coverSeed"));
		if (picture) extras[MZExtrasArtistImageKey] = [NSString stringWithFormat:@"https://cdn-images.dzcdn.net/images/artist/%@/500x500-000000-80-0-0.jpg", picture];
	}

	return extras;
}

%ctor {
	MZProviderCheck(@[
		@"DZRAudioPlayer +sharedAudioPlayer",
		@"DZRAudioPlayer -currentTrack",
		@"DeezerTrack -title",
		@"DeezerTrack -deezerId",
		@"DeezerTrack -uploadId",
	], @[
		@"DeezerTrack -coverSeed",
		@"DeezerTrack -albumId",
		@"DeezerTrack -artist",
	]);
	MZAddExtras(MZExtras);
}
