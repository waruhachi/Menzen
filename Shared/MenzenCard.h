#import <Foundation/Foundation.h>

#import "MenzenLocalization/MenzenLocalization.h"
#import "MenzenSettings.h"

// The parts of the activity card and what each can show, for menzend (which
// builds the activity) and the pane (which offers the choices). Each part is
// one string setting; one that isn't set yet follows the switches it
// replaced.

NS_ASSUME_NONNULL_BEGIN

// "Listening to <heading>": app (default), menzen, artist, album or custom
// (MenzenSettingHeadingText).
#define MenzenPartHeading MenzenSettingHeading
// title (default), artist or album. Discord needs a first line.
#define MenzenPartFirstLine @"firstLine"
// artist (default), album, title or none.
#define MenzenPartSecondLine @"secondLine"
// The big picture's caption, which Discord shows as a third line: album
// (default), artist, title or none.
#define MenzenPartThirdLine @"thirdLine"
// cover (default), artistImage, logo or none. A missing cover or artist
// picture falls back to the app's logo.
#define MenzenPartBigPicture @"bigPicture"
// In the big picture's corner: artistImage (default), logo, cover or none.
#define MenzenPartSmallPicture @"smallPicture"
// The small picture's hover text: artist (default), app or none.
#define MenzenPartSmallPictureText @"smallPictureText"
// progress (default) or elapsed. Without timestamps Discord shows the time
// since the activity started anyway, so there's no "none".
#define MenzenPartTime @"time"
// What member lists show next to the name: title (default), artist, album,
// or name (the heading). Discord can only show the heading, first or second
// line there; see MenzenMemberListDisplay.
#define MenzenPartMemberList MenzenSettingMemberList

// [value, title] pairs, the default first.
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
			MenzenPartMemberList: @[@[@"title", MenzenLocalizedString(@"common.title", @"Title")], @[@"artist", MenzenLocalizedString(@"card.artist_or_show", @"Artist or Show")], @[@"album", MenzenLocalizedString(@"card.album_or_episode", @"Album or Episode")], @[@"name", MenzenLocalizedString(@"common.heading", @"Heading")]],
		};
	});
	return choices[part] ?: @[];
}

// The part's setting, one of its choices.
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
	// Member lists were briefly set by line, and before that "app" was the
	// heading.
	if ([part isEqualToString:MenzenPartMemberList]) {
		if ([value isEqualToString:@"details"]) value = MenzenPart(MenzenPartFirstLine);
		else if ([value isEqualToString:@"state"]) value = MenzenPart(MenzenPartSecondLine);
		else if ([value isEqualToString:@"app"]) value = @"name";
	}
	NSArray *choices = MenzenPartChoices(part);
	for (NSArray<NSString *> *choice in choices) {
		if ([choice.firstObject isEqualToString:value]) return value;
	}
	return [choices.firstObject firstObject] ?: @"";
}

// Where the member list choice is on the card: details, state or name, or
// nil when it isn't on the heading, first or second line.
static inline NSString *_Nullable MenzenMemberListDisplayFor(NSString *content) {
	if ([content isEqualToString:@"name"]) return @"name";
	if ([MenzenPart(MenzenPartFirstLine) isEqualToString:content]) return @"details";
	if ([MenzenPart(MenzenPartSecondLine) isEqualToString:content]) return @"state";
	if ([MenzenPart(MenzenPartHeading) isEqualToString:content]) return @"name";
	return nil;
}

static inline NSString *_Nullable MenzenMemberListDisplay(void) {
	return MenzenMemberListDisplayFor(MenzenPart(MenzenPartMemberList));
}

static inline NSString *MenzenPartTitle(NSString *part, NSString *value) {
	for (NSArray<NSString *> *choice in MenzenPartChoices(part)) {
		if ([choice.firstObject isEqualToString:value]) return choice[1];
	}
	return value;
}

NS_ASSUME_NONNULL_END
