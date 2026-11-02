#import <Foundation/Foundation.h>

#import "MZSettings.h"

// The parts of the activity card and what each can show, for menzend (which
// builds the activity) and the pane (which offers the choices). Each part is
// one string setting; one that isn't set yet follows the switches it
// replaced.

NS_ASSUME_NONNULL_BEGIN

// "Listening to <heading>": app (default), menzen, artist, album or custom
// (MZSettingHeadingText).
#define MZPartHeading MZSettingHeading
// title (default), artist or album. Discord needs a first line.
#define MZPartFirstLine @"firstLine"
// artist (default), album, title or none.
#define MZPartSecondLine @"secondLine"
// The big picture's caption, which Discord shows as a third line: album
// (default), artist, title or none.
#define MZPartThirdLine @"thirdLine"
// cover (default), artistImage, logo or none. A missing cover or artist
// picture falls back to the app's logo.
#define MZPartBigPicture @"bigPicture"
// In the big picture's corner: artistImage (default), logo, cover or none.
#define MZPartSmallPicture @"smallPicture"
// The small picture's hover text: artist (default), app or none.
#define MZPartSmallPictureText @"smallPictureText"
// progress (default) or elapsed. Without timestamps Discord shows the time
// since the activity started anyway, so there's no "none".
#define MZPartTime @"time"
// What member lists show next to the name: title (default), artist, album,
// or name (the heading). Discord can only show the heading, first or second
// line there; see MZMemberListDisplay.
#define MZPartMemberList MZSettingMemberList

// [value, title] pairs, the default first.
static inline NSArray<NSArray<NSString *> *> *MZPartChoices(NSString *part) {
	static NSDictionary<NSString *, NSArray *> *choices;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		choices = @{
			MZPartHeading: @[@[@"app", @"App Name"], @[@"menzen", @"Menzen"], @[@"artist", @"Artist"], @[@"album", @"Album"], @[@"custom", @"Custom"]],
			MZPartFirstLine: @[@[@"title", @"Title"], @[@"artist", @"Artist"], @[@"album", @"Album"]],
			MZPartSecondLine: @[@[@"artist", @"Artist"], @[@"album", @"Album"], @[@"title", @"Title"], @[@"none", @"None"]],
			MZPartThirdLine: @[@[@"album", @"Album"], @[@"artist", @"Artist"], @[@"title", @"Title"], @[@"none", @"None"]],
			MZPartBigPicture: @[@[@"cover", @"Cover Art"], @[@"artistImage", @"Artist Picture"], @[@"logo", @"App Logo"], @[@"none", @"None"]],
			MZPartSmallPicture: @[@[@"artistImage", @"Artist Picture"], @[@"logo", @"App Logo"], @[@"cover", @"Cover Art"], @[@"none", @"None"]],
			MZPartSmallPictureText: @[@[@"artist", @"Artist"], @[@"app", @"App Name"], @[@"none", @"None"]],
			MZPartTime: @[@[@"progress", @"Progress Bar"], @[@"elapsed", @"Time Elapsed"]],
			MZPartMemberList: @[@[@"title", @"Title"], @[@"artist", @"Artist"], @[@"album", @"Album"], @[@"name", @"Heading"]],
		};
	});
	return choices[part] ?: @[];
}

// The part's setting, one of its choices.
static inline NSString *MZPart(NSString *part) {
	NSString *value = MZSettingString(part, nil);
	if (!value) {
		// Before the parts, these were switches.
		if ([part isEqualToString:MZPartSecondLine]) value = MZSettingBool(MZSettingShowArtist, YES) ? @"artist" : @"none";
		if ([part isEqualToString:MZPartBigPicture]) value = MZSettingBool(MZSettingShowCover, YES) ? @"cover" : @"logo";
		if ([part isEqualToString:MZPartSmallPicture]) value = MZSettingBool(MZSettingShowArtistPicture, YES) ? @"artistImage" : @"none";
		if ([part isEqualToString:MZPartTime]) value = MZSettingBool(MZSettingShowProgress, YES) ? @"progress" : @"elapsed";
	}
	if ([part isEqualToString:MZPartTime] && [value isEqualToString:@"none"]) value = @"elapsed";
	// Member lists were briefly set by line, and before that "app" was the
	// heading.
	if ([part isEqualToString:MZPartMemberList]) {
		if ([value isEqualToString:@"details"]) value = MZPart(MZPartFirstLine);
		else if ([value isEqualToString:@"state"]) value = MZPart(MZPartSecondLine);
		else if ([value isEqualToString:@"app"]) value = @"name";
	}
	NSArray *choices = MZPartChoices(part);
	for (NSArray<NSString *> *choice in choices) {
		if ([choice.firstObject isEqualToString:value]) return value;
	}
	return [choices.firstObject firstObject] ?: @"";
}

// Where the member list choice is on the card: details, state or name, or
// nil when it isn't on the heading, first or second line.
static inline NSString *_Nullable MZMemberListDisplayFor(NSString *content) {
	if ([content isEqualToString:@"name"]) return @"name";
	if ([MZPart(MZPartFirstLine) isEqualToString:content]) return @"details";
	if ([MZPart(MZPartSecondLine) isEqualToString:content]) return @"state";
	if ([MZPart(MZPartHeading) isEqualToString:content]) return @"name";
	return nil;
}

static inline NSString *_Nullable MZMemberListDisplay(void) {
	return MZMemberListDisplayFor(MZPart(MZPartMemberList));
}

static inline NSString *MZPartTitle(NSString *part, NSString *value) {
	for (NSArray<NSString *> *choice in MZPartChoices(part)) {
		if ([choice.firstObject isEqualToString:value]) return choice[1];
	}
	return value;
}

NS_ASSUME_NONNULL_END
