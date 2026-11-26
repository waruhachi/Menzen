#import <Foundation/Foundation.h>

#import "MenzenLocalization/MenzenLocalization.h"
#import "MenzenSettings.h"

#define MenzenPartHeading MenzenSettingHeading
// Discord needs a first line.
#define MenzenPartFirstLine @"firstLine"
#define MenzenPartSecondLine @"secondLine"
#define MenzenPartThirdLine @"thirdLine"
#define MenzenPartBigPicture @"bigPicture"
#define MenzenPartSmallPicture @"smallPicture"
#define MenzenPartSmallPictureText @"smallPictureText"
// Without timestamps Discord shows the time since the activity started anyway,
// so there's no "none".
#define MenzenPartTime @"time"
#define MenzenPartMemberList MenzenSettingMemberList

static inline NSArray<NSArray<NSString *> *> *MenzenPartChoices(NSString *part) {
	static NSDictionary<NSString *, NSArray *> *choices;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		choices = @{
			MenzenPartHeading: @[@[@"app", MenzenLocalizedString(@"card.app_name", @"App Name")], @[@"menzen", @"Menzen"], @[@"artist", MenzenLocalizedString(@"card.artist_or_show", @"Artist or Show")], @[@"album", MenzenLocalizedString(@"card.album_or_episode", @"Album or Episode")], @[@"custom", MenzenLocalizedString(@"card.custom", @"Custom")]],
			MenzenPartFirstLine: @[@[@"title", MenzenLocalizedString(@"common.title", @"Title")], @[@"artist", MenzenLocalizedString(@"card.artist_or_show", @"Artist or Show")], @[@"album", MenzenLocalizedString(@"card.album_or_episode", @"Album or Episode")]],
			MenzenPartSecondLine: @[@[@"artist", MenzenLocalizedString(@"card.artist_or_show", @"Artist or Show")], @[@"album", MenzenLocalizedString(@"card.album_or_episode", @"Album or Episode")], @[@"title", MenzenLocalizedString(@"common.title", @"Title")], @[@"none", MenzenLocalizedString(@"common.none", @"None")]],
			MenzenPartThirdLine: @[@[@"album", MenzenLocalizedString(@"card.album_or_episode", @"Album or Episode")], @[@"artist", MenzenLocalizedString(@"card.artist_or_show", @"Artist or Show")], @[@"title", MenzenLocalizedString(@"common.title", @"Title")], @[@"none", MenzenLocalizedString(@"common.none", @"None")]],
			MenzenPartBigPicture: @[@[@"cover", MenzenLocalizedString(@"card.artwork", @"Artwork")], @[@"artistImage", MenzenLocalizedString(@"card.artist_or_show_picture", @"Artist or Show Picture")], @[@"logo", MenzenLocalizedString(@"card.app_logo", @"App Logo")], @[@"none", MenzenLocalizedString(@"common.none", @"None")]],
			MenzenPartSmallPicture: @[@[@"artistImage", MenzenLocalizedString(@"card.artist_or_show_picture", @"Artist or Show Picture")], @[@"logo", MenzenLocalizedString(@"card.app_logo", @"App Logo")], @[@"cover", MenzenLocalizedString(@"card.artwork", @"Artwork")], @[@"none", MenzenLocalizedString(@"common.none", @"None")]],
			MenzenPartSmallPictureText: @[@[@"artist", MenzenLocalizedString(@"card.artist_or_show", @"Artist or Show")], @[@"app", MenzenLocalizedString(@"card.app_name", @"App Name")], @[@"none", MenzenLocalizedString(@"common.none", @"None")]],
			MenzenPartTime: @[@[@"progress", MenzenLocalizedString(@"card.progress_bar", @"Progress Bar")], @[@"elapsed", MenzenLocalizedString(@"common.time_elapsed", @"Time Elapsed")]],
			MenzenPartMemberList: @[@[@"details", MenzenLocalizedString(@"common.first_line", @"First Line")], @[@"state", MenzenLocalizedString(@"common.second_line", @"Second Line")], @[@"name", MenzenLocalizedString(@"common.heading", @"Heading")]],
		};
	});
	return choices[part] ?: @[];
}

static inline NSString *MenzenPart(NSString *part) {
	NSString *value = MenzenSettingString(part, nil);
	if (!value) {
		// Before the parts, these were switches.
		if ([part isEqualToString:MenzenPartSecondLine]) value = MenzenSettingBool(MenzenSettingShowArtist, YES) ? @"artist" : @"none";
		if ([part isEqualToString:MenzenPartBigPicture]) value = MenzenSettingBool(MenzenSettingShowCover, YES) ? @"cover" : @"logo";
		if ([part isEqualToString:MenzenPartSmallPicture]) value = MenzenSettingBool(MenzenSettingShowArtistPicture, YES) ? @"artistImage" : @"none";
		if ([part isEqualToString:MenzenPartTime]) value = MenzenSettingBool(MenzenSettingShowProgress, YES) ? @"progress" : @"elapsed";
	}
	if ([part isEqualToString:MenzenPartTime] && [value isEqualToString:@"none"]) value = @"elapsed";
	// Member lists were briefly set by what they showed, and before that "app"
	// was the heading.
	if ([part isEqualToString:MenzenPartMemberList]) {
		if ([value isEqualToString:@"title"] || [value isEqualToString:@"artist"] || [value isEqualToString:@"album"]) {
			if ([MenzenPart(MenzenPartSecondLine) isEqualToString:value]) value = @"state";
			else if ([MenzenPart(MenzenPartHeading) isEqualToString:value]) value = @"name";
			else value = @"details";
		} else if ([value isEqualToString:@"app"]) {
			value = @"name";
		}
	}
	NSArray *choices = MenzenPartChoices(part);
	for (NSArray<NSString *> *choice in choices) {
		if ([choice.firstObject isEqualToString:value]) return value;
	}
	return [choices.firstObject firstObject] ?: @"";
}

static inline NSString *MenzenPartTitle(NSString *part, NSString *value) {
	for (NSArray<NSString *> *choice in MenzenPartChoices(part)) {
		if ([choice.firstObject isEqualToString:value]) return choice[1];
	}
	return value;
}
