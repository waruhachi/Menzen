#import <UIKit/UIKit.h>

#import "../../Shared/MZProvider/MZProvider.h"

// An episode is published as "Netflix - <show>". The player's
// model.videoModel has the real title, show, numbers and cover.

@interface NFUIFullPlayerViewController : UIViewController
@end

static __weak UIViewController *player;

static NSString *MZText(id object, NSString *key) {
	id value = MZGet(object, key);
	return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

// Some episode pictures have URLs longer than Discord takes; the show's
// picture then.
static NSString *MZCover(id video) {
	NSMutableArray *pictures = [NSMutableArray array];
	for (NSString *key in @[@"nowPlayingImageUrl", @"airPlayImageUrl"]) {
		NSString *picture = MZText(video, key);
		if (picture) [pictures addObject:picture];
	}

	id panels = MZGet(video, @"shortPanelArt");
	if ([panels isKindOfClass:NSArray.class]) [pictures addObjectsFromArray:panels];
	for (NSString *picture in pictures) {
		if ([picture isKindOfClass:NSString.class] && [picture hasPrefix:@"https://"] && picture.length <= 256) return picture;
	}

	return nil;
}

static NSString *MZNumber(id object, NSString *key) {
	id value = MZGet(object, key);
	return [value isKindOfClass:NSNumber.class] && [value integerValue] > 0 ? [value stringValue] : nil;
}

%hook NFUIFullPlayerViewController

- (void)viewWillAppear:(BOOL)animated {
	%orig;
	player = self;
}

%end

static NSDictionary *MZExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	id video = MZGet(MZGet(player, @"model"), @"videoModel");
	NSString *title = MZText(video, @"title");
	NSString *show = MZText(video, @"showTitle");
	NSString *infoTitle = MZString(info[MPMediaItemPropertyTitle]);
	// Only the video's own info, which is titled after its show (or itself).
	if (!title || center != MPNowPlayingInfoCenter.defaultCenter || ![infoTitle hasSuffix:show ?: title]) return nil;

	withExtras[MPMediaItemPropertyTitle] = title;
	BOOL episode = show && ![show isEqualToString:title];
	if (episode) {
		withExtras[MPMediaItemPropertyArtist] = show;
		// An album that's the artist again is taken as none.
		withExtras[MPMediaItemPropertyAlbumTitle] = show;
	} else if (withExtras[MPMediaItemPropertyAlbumTitle]) {
		withExtras[MPMediaItemPropertyAlbumTitle] = @"";
	}

	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	extras[MZExtrasCoverKey] = MZCover(video);
	extras[MZExtrasTitleURLKey] = MZLinkURL(@"https://www.netflix.com/watch/%@", MZGet(video, @"videoId"));
	if (episode) extras[MZExtrasArtistURLKey] = MZLinkURL(@"https://www.netflix.com/title/%@", MZGet(video, @"showId"));
	if (episode && ![MZGet(video, @"hasHiddenEpisodeNumbers") boolValue]) {
		extras[MZExtrasSeasonKey] = MZNumber(video, @"seasonNumber");
		extras[MZExtrasEpisodeKey] = MZNumber(video, @"episodeNumber");
	}

	return extras;
}

%ctor {
	MZProviderCheck(@[@"NFUIFullPlayerViewController -viewWillAppear:", @"NFUIFullPlayerViewController -model"], @[]);
	MZAddExtras(MZExtras);
	%init;
}
