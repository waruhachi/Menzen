#import "../../Shared/MenzenProvider/MenzenProvider.h"

// An episode is published as its show alone, through AVKit's
// AVNowPlayingInfoController with a MediaRemote dictionary, not
// MPNowPlayingInfoCenter. The TVPlayback media item playing has the rest.

static NSString *const MenzenInfoTitle = @"kMRMediaRemoteNowPlayingInfoTitle";
static NSString *const MenzenInfoArtist = @"kMRMediaRemoteNowPlayingInfoArtist";
static NSString *const MenzenInfoAssetURL = @"kMRMediaRemoteNowPlayingInfoAssetURL";
static NSString *const MenzenInfoExternalContentIdentifier = @"kMRMediaRemoteNowPlayingInfoExternalContentIdentifier";

@interface MenzenTVMediaItem : NSObject
- (id)mediaItemMetadataForProperty:(NSString *)property;
@end

@interface NSObject (MenzenTVPlayback)
+ (id)sharedInstance;
- (id)mainPlayer;
- (id)currentMediaItem;
@end

static NSString *MenzenMetadataString(MenzenTVMediaItem *item, NSString *property) {
	id value = [item mediaItemMetadataForProperty:[@"TVPMediaItemMetadata" stringByAppendingString:property]];
	if ([value isKindOfClass:NSNumber.class]) return [value integerValue] > 0 ? [value stringValue] : nil;
	return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

static NSString *MenzenPage(MenzenTVMediaItem *item, NSString *property, NSString *kind) {
	NSString *ID = MenzenMetadataString(item, property);
	return [ID hasPrefix:@"umc."] ? MenzenLinkURL([NSString stringWithFormat:@"https://tv.apple.com/%@/%%@", kind], ID) : nil;
}

static MenzenTVMediaItem *MenzenCurrentMediaItem(void) {
	Class manager = %c(VUIPlaybackManager);
	if (![manager respondsToSelector:@selector(sharedInstance)] || ![manager instancesRespondToSelector:@selector(mainPlayer)]) return nil;
	id player = [[manager sharedInstance] mainPlayer];
	id item = [player respondsToSelector:@selector(currentMediaItem)] ? [player currentMediaItem] : nil;
	return [item respondsToSelector:@selector(mediaItemMetadataForProperty:)] ? item : nil;
}

%hook AVNowPlayingInfoController

- (void)_updateNowPlayingInfo:(NSDictionary *)info commandsAndStates:(id)commandsAndStates {
	MenzenTVMediaItem *item = [info isKindOfClass:NSDictionary.class] && [info[MenzenInfoTitle] length] ? MenzenCurrentMediaItem() : nil;
	// Only the item's own info.
	NSString *identifier = MenzenMetadataString(item, @"ExternalIdentifier");
	if (!identifier || ![info[MenzenInfoExternalContentIdentifier] isEqual:identifier]) {
		%orig;
		return;
	}

	NSMutableDictionary *withExtras = [info mutableCopy];
	NSString *title = MenzenMetadataString(item, @"Title");
	NSString *series = MenzenMetadataString(item, @"SeriesTitle");
	if (title) withExtras[MenzenInfoTitle] = title;
	if (series && ![series isEqualToString:title]) withExtras[MenzenInfoArtist] = series;

	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	NSString *cover = MenzenMetadataString(item, @"ArtworkURLFormat");
	cover = [cover stringByReplacingOccurrencesOfString:@"{w}" withString:@"600"];
	cover = [cover stringByReplacingOccurrencesOfString:@"{h}" withString:@"338"];
	cover = [cover stringByReplacingOccurrencesOfString:@"{f}" withString:@"jpg"];
	// Movies only have a sized picture, which the CDN also has as a JPEG.
	if (!cover) {
		NSURLComponents *picture = [NSURLComponents componentsWithString:MenzenMetadataString(item, @"ArtworkURLString") ?: @""];
		if (picture.path.pathExtension.length && ![picture.path.pathExtension isEqualToString:@"jpg"]) {
			picture.path = [picture.path.stringByDeletingPathExtension stringByAppendingPathExtension:@"jpg"];
			cover = picture.string;
		}
	}

	if ([cover hasPrefix:@"https://"] && ![cover containsString:@"{"]) extras[MenzenExtrasCoverKey] = cover;
	if (series) {
		extras[MenzenExtrasSeasonKey] = MenzenMetadataString(item, @"SeasonNumber");
		extras[MenzenExtrasEpisodeKey] = MenzenMetadataString(item, @"EpisodeNumber");
		extras[MenzenExtrasTitleURLKey] = MenzenPage(item, @"CanonicalID", @"episode");
		extras[MenzenExtrasArtistURLKey] = MenzenPage(item, @"ShowCanonicalID", @"show");
	} else {
		extras[MenzenExtrasTitleURLKey] = MenzenPage(item, @"CanonicalID", @"movie");
	}

	NSURL *extrasURL = MenzenExtrasURL(extras);
	if (extrasURL) {
		withExtras[MenzenInfoAssetURL] = extrasURL;
		MenzenProviderWorked();
	}

	%orig(withExtras, commandsAndStates);
}

%end

%ctor {
	MenzenProviderCheck(@[
		@"AVNowPlayingInfoController -_updateNowPlayingInfo:commandsAndStates:",
		@"VUIPlaybackManager +sharedInstance",
		@"VUIPlaybackManager -mainPlayer",
	], @[]);
	%init;
}
