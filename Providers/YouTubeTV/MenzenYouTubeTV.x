#import "../../Shared/MenzenProvider/MenzenProvider.h"

// The cover comes from YTLockScreenControllerState, built just before the
// app publishes, keyed by the external content ID. The player itself only
// has the channel's picture.

@interface YTLockScreenControllerState : NSObject
- (NSString *)contentIdentifier;
- (NSDictionary<NSValue *, NSString *> *)thumbnailURLs;
@end

static MenzenCache<NSString *, NSString *> *covers;

// The largest https picture with a URL Discord takes.
static NSString *MenzenCover(NSDictionary *thumbnails) {
	NSString *cover = nil;
	CGFloat coverWidth = 0;
	for (NSValue *size in thumbnails) {
		NSString *url = thumbnails[size];
		if (![url isKindOfClass:NSString.class]) continue;
		if ([url hasPrefix:@"//"]) url = [@"https:" stringByAppendingString:url];
		CGFloat width = [size isKindOfClass:NSValue.class] && !strcmp(size.objCType, @encode(CGSize)) ? size.CGSizeValue.width : 0;
		if ([url hasPrefix:@"https://"] && url.length <= 256 && (!cover || width > coverWidth)) {
			cover = url;
			coverWidth = width;
		}
	}

	return cover;
}

%hook YTLockScreenControllerState

- (instancetype)initWithBuilder:(id)builder {
	self = %orig;
	NSString *contentID = [self respondsToSelector:@selector(contentIdentifier)] ? self.contentIdentifier : nil;
	NSDictionary *thumbnails = [self respondsToSelector:@selector(thumbnailURLs)] ? self.thumbnailURLs : nil;
	NSString *cover = [thumbnails isKindOfClass:NSDictionary.class] ? MenzenCover(thumbnails) : nil;
	if (MenzenString(contentID) && cover) covers[contentID] = cover;
	return self;
}

%end

static NSDictionary *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	NSString *contentID = MenzenString(info[MPNowPlayingInfoPropertyExternalContentIdentifier]);
	if (!contentID || withExtras[MPNowPlayingInfoPropertyAssetURL]) return nil;
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	extras[MenzenExtrasCoverKey] = covers[contentID];
	// Video IDs are 11 characters; other content has random IDs.
	if (contentID.length == 11 && ![contentID containsString:@"."] && ![contentID containsString:@":"]) extras[MenzenExtrasTitleURLKey] = MenzenLinkURL(@"https://tv.youtube.com/watch/%@", contentID);
	return extras;
}

%ctor {
	covers = [[MenzenCache alloc] initWithLimit:200];
	MenzenProviderCheck(@[@"YTLockScreenControllerState -initWithBuilder:", @"YTLockScreenControllerState -contentIdentifier", @"YTLockScreenControllerState -thumbnailURLs"], @[]);
	MenzenAddExtras(MenzenExtras);
	%init;
}
