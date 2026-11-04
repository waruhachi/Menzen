#import "../../Shared/MenzenProvider/MenzenProvider.h"

// The app publishes no IDs; +[DZRAudioPlayer sharedAudioPlayer].currentTrack
// has them, and the cover and artist picture hashes (coverSeed).

// Uploads and other local tracks have none.
static NSString *MenzenCatalogID(id value) {
	NSString *ID = MenzenString(value);
	NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
	return ID && ID.length <= 20 && [ID rangeOfCharacterFromSet:digits.invertedSet].location == NSNotFound && ![ID isEqualToString:@"0"] ? ID : nil;
}

static NSString *MenzenSeed(id value) {
	NSString *seed = MenzenString(value);
	NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
	return seed.length == 32 && [seed rangeOfCharacterFromSet:hex.invertedSet].location == NSNotFound ? seed : nil;
}

static NSDictionary *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	if (withExtras[MPNowPlayingInfoPropertyAssetURL]) return nil;
	id track = MenzenGet(MenzenGet(%c(DZRAudioPlayer), @"sharedAudioPlayer"), @"currentTrack");
	Class trackClass = %c(DeezerTrack);
	if (!trackClass || ![track isKindOfClass:trackClass]) return nil;

	// Only the playing track's.
	NSString *title = MenzenString(MenzenGet(track, @"title"));
	if (!title || ![title isEqualToString:MenzenString(info[MPMediaItemPropertyTitle])]) return nil;
	NSString *trackID = MenzenCatalogID(MenzenGet(track, @"deezerId"));
	// Catalog tracks have uploadId "0".
	if (!trackID || MenzenCatalogID(MenzenGet(track, @"uploadId"))) return nil;

	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	NSString *cover = MenzenSeed(MenzenGet(track, @"coverSeed"));
	if (cover) extras[MenzenExtrasCoverKey] = [NSString stringWithFormat:@"https://cdn-images.dzcdn.net/images/cover/%@/750x750-000000-80-0-0.jpg", cover];
	extras[MenzenExtrasTitleURLKey] = MenzenLinkURL(@"https://www.deezer.com/track/%@", trackID);
	extras[MenzenExtrasAlbumURLKey] = MenzenLinkURL(@"https://www.deezer.com/album/%@", MenzenCatalogID(MenzenGet(track, @"albumId")));

	id artist = MenzenGet(track, @"artist");
	NSString *artistID = MenzenCatalogID(MenzenGet(artist, @"deezerId"));
	if (artistID) {
		extras[MenzenExtrasArtistURLKey] = MenzenLinkURL(@"https://www.deezer.com/artist/%@", artistID);
		extras[MenzenExtrasArtistNameKey] = MenzenString(MenzenGet(artist, @"name"));
		NSString *picture = MenzenSeed(MenzenGet(artist, @"coverSeed"));
		if (picture) extras[MenzenExtrasArtistImageKey] = [NSString stringWithFormat:@"https://cdn-images.dzcdn.net/images/artist/%@/500x500-000000-80-0-0.jpg", picture];
	}

	return extras;
}

%ctor {
	MenzenProviderCheck(@[
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
	MenzenAddExtras(MenzenExtras);
}
