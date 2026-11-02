#import "../../Shared/MZProvider/MZProvider.h"

// An episode is published as its show alone, through AVKit's
// AVNowPlayingInfoController with a MediaRemote dictionary, not
// MPNowPlayingInfoCenter. The TVPlayback media item playing has the rest.

static NSString *const MZInfoTitle = @"kMRMediaRemoteNowPlayingInfoTitle";
static NSString *const MZInfoArtist = @"kMRMediaRemoteNowPlayingInfoArtist";
static NSString *const MZInfoAssetURL = @"kMRMediaRemoteNowPlayingInfoAssetURL";
static NSString *const MZInfoExternalContentIdentifier = @"kMRMediaRemoteNowPlayingInfoExternalContentIdentifier";

@interface MZTVMediaItem : NSObject
- (id)mediaItemMetadataForProperty:(NSString *)property;
@end

@interface NSObject (MZTVPlayback)
+ (id)sharedInstance;
- (id)mainPlayer;
- (id)currentMediaItem;
@end

static NSString *MZMetadataString(MZTVMediaItem *item, NSString *property) {
	id value = [item mediaItemMetadataForProperty:[@"TVPMediaItemMetadata" stringByAppendingString:property]];
	if ([value isKindOfClass:NSNumber.class]) return [value integerValue] > 0 ? [value stringValue] : nil;
	return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

static NSString *MZPage(MZTVMediaItem *item, NSString *property, NSString *kind) {
	NSString *ID = MZMetadataString(item, property);
	return [ID hasPrefix:@"umc."] ? MZLinkURL([NSString stringWithFormat:@"https://tv.apple.com/%@/%%@", kind], ID) : nil;
}

static MZTVMediaItem *MZCurrentMediaItem(void) {
	Class manager = %c(VUIPlaybackManager);
	if (![manager respondsToSelector:@selector(sharedInstance)] || ![manager instancesRespondToSelector:@selector(mainPlayer)]) return nil;
	id player = [[manager sharedInstance] mainPlayer];
	id item = [player respondsToSelector:@selector(currentMediaItem)] ? [player currentMediaItem] : nil;
	return [item respondsToSelector:@selector(mediaItemMetadataForProperty:)] ? item : nil;
}

%hook AVNowPlayingInfoController

- (void)_updateNowPlayingInfo:(NSDictionary *)info commandsAndStates:(id)commandsAndStates {
	MZTVMediaItem *item = [info isKindOfClass:NSDictionary.class] && [info[MZInfoTitle] length] ? MZCurrentMediaItem() : nil;
	// Only the item's own info.
	NSString *identifier = MZMetadataString(item, @"ExternalIdentifier");
	if (!identifier || ![info[MZInfoExternalContentIdentifier] isEqual:identifier]) {
		%orig;
		return;
	}

	NSMutableDictionary *withExtras = [info mutableCopy];
	NSString *title = MZMetadataString(item, @"Title");
	NSString *series = MZMetadataString(item, @"SeriesTitle");
	if (title) withExtras[MZInfoTitle] = title;
	if (series && ![series isEqualToString:title]) withExtras[MZInfoArtist] = series;

	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	NSString *cover = MZMetadataString(item, @"ArtworkURLFormat");
	cover = [cover stringByReplacingOccurrencesOfString:@"{w}" withString:@"600"];
	cover = [cover stringByReplacingOccurrencesOfString:@"{h}" withString:@"338"];
	cover = [cover stringByReplacingOccurrencesOfString:@"{f}" withString:@"jpg"];
	// Movies only have a sized picture, which the CDN also has as a JPEG.
	if (!cover) {
		NSURLComponents *picture = [NSURLComponents componentsWithString:MZMetadataString(item, @"ArtworkURLString") ?: @""];
		if (picture.path.pathExtension.length && ![picture.path.pathExtension isEqualToString:@"jpg"]) {
			picture.path = [picture.path.stringByDeletingPathExtension stringByAppendingPathExtension:@"jpg"];
			cover = picture.string;
		}
	}

	if ([cover hasPrefix:@"https://"] && ![cover containsString:@"{"]) extras[MZExtrasCoverKey] = cover;
	if (series) {
		extras[MZExtrasSeasonKey] = MZMetadataString(item, @"SeasonNumber");
		extras[MZExtrasEpisodeKey] = MZMetadataString(item, @"EpisodeNumber");
		extras[MZExtrasTitleURLKey] = MZPage(item, @"CanonicalID", @"episode");
		extras[MZExtrasArtistURLKey] = MZPage(item, @"ShowCanonicalID", @"show");
	} else {
		extras[MZExtrasTitleURLKey] = MZPage(item, @"CanonicalID", @"movie");
	}

	NSURL *extrasURL = MZExtrasURL(extras);
	if (extrasURL) {
		withExtras[MZInfoAssetURL] = extrasURL;
		MZProviderWorked();
	}

	%orig(withExtras, commandsAndStates);
}

%end

%ctor {
	MZProviderCheck(@[
		@"AVNowPlayingInfoController -_updateNowPlayingInfo:commandsAndStates:",
		@"VUIPlaybackManager +sharedInstance",
		@"VUIPlaybackManager -mainPlayer",
	], @[]);
	%init;
}
