#import <UIKit/UIKit.h>

#import "../../Shared/MenzenProvider/MenzenProvider.h"

// An episode is published as "Netflix - <show>". The player's
// model.videoModel has the real title, show, numbers and cover.

@interface NFUIFullPlayerViewController : UIViewController
@end

static __weak UIViewController *player;

static NSString *MenzenText(id object, NSString *key) {
	id value = MenzenGet(object, key);
	return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

// Some episode pictures have URLs longer than Discord takes; the show's
// picture then.
static NSString *MenzenCover(id video) {
	NSMutableArray *pictures = [NSMutableArray array];
	for (NSString *key in @[@"nowPlayingImageUrl", @"airPlayImageUrl"]) {
		NSString *picture = MenzenText(video, key);
		if (picture) [pictures addObject:picture];
	}

	id panels = MenzenGet(video, @"shortPanelArt");
	if ([panels isKindOfClass:NSArray.class]) [pictures addObjectsFromArray:panels];
	for (NSString *picture in pictures) {
		if ([picture isKindOfClass:NSString.class] && [picture hasPrefix:@"https://"] && picture.length <= 256) return picture;
	}

	return nil;
}

static NSString *MenzenNumber(id object, NSString *key) {
	id value = MenzenGet(object, key);
	return [value isKindOfClass:NSNumber.class] && [value integerValue] > 0 ? [value stringValue] : nil;
}

%hook NFUIFullPlayerViewController

- (void)viewWillAppear:(BOOL)animated {
	%orig;
	player = self;
}

%end

static NSDictionary *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	id video = MenzenGet(MenzenGet(player, @"model"), @"videoModel");
	NSString *title = MenzenText(video, @"title");
	NSString *show = MenzenText(video, @"showTitle");
	NSString *infoTitle = MenzenString(info[MPMediaItemPropertyTitle]);
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
	extras[MenzenExtrasCoverKey] = MenzenCover(video);
	extras[MenzenExtrasTitleURLKey] = MenzenLinkURL(@"https://www.netflix.com/watch/%@", MenzenGet(video, @"videoId"));
	if (episode) extras[MenzenExtrasArtistURLKey] = MenzenLinkURL(@"https://www.netflix.com/title/%@", MenzenGet(video, @"showId"));
	if (episode && ![MenzenGet(video, @"hasHiddenEpisodeNumbers") boolValue]) {
		extras[MenzenExtrasSeasonKey] = MenzenNumber(video, @"seasonNumber");
		extras[MenzenExtrasEpisodeKey] = MenzenNumber(video, @"episodeNumber");
	}

	return extras;
}

%ctor {
	MenzenProviderCheck(@[@"NFUIFullPlayerViewController -viewWillAppear:", @"NFUIFullPlayerViewController -model"], @[]);
	MenzenAddExtras(MenzenExtras);
	%init;
}
