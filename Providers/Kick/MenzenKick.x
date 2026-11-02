#import "../../Shared/MZProvider/MZProvider.h"
#import "../../Shared/MZProvider/MZResponses.h"

// The player (React Native) only has the stream's URL. The thumbnail comes
// from the channel info the app fetches as a channel opens, matched by
// stream title, else by channel name.

// By stream title and by lowercased channel name.
static MZCache<NSString *, NSDictionary *> *streams;

static BOOL MZIsChannelInfo(NSURL *url) {
	NSArray<NSString *> *parts = url.path.pathComponents;
	// "/", "api", "v2", "channels", "<slug>", "info"
	return [url.host isEqualToString:@"kick.com"] && parts.count == 6 && [parts[3] isEqualToString:@"channels"] && [parts[5] isEqualToString:@"info"];
}

static NSString *MZThumbnail(NSDictionary *thumbnail) {
	if (![thumbnail isKindOfClass:NSDictionary.class]) return nil;
	NSString *found = nil;
	for (id value in thumbnail.allValues) {
		NSString *url = MZString(value);
		if (![url hasPrefix:@"https://images.kick.com/"] || [url rangeOfString:@" "].location != NSNotFound || url.length > 256) continue;
		if ([url containsString:@"/720."]) return url;
		found = found ?: url;
	}

	return found;
}

static void MZRememberInfo(NSData *data, NSString *slug) {
	NSDictionary *info = MZJSON(data);
	NSDictionary *livestream = [info isKindOfClass:NSDictionary.class] ? info[@"livestream"] : nil;
	if (![livestream isKindOfClass:NSDictionary.class]) return;
	NSString *thumbnail = MZThumbnail(livestream[@"thumbnail"]);
	if (!thumbnail) return;
	NSString *title = MZString(livestream[@"session_title"]);
	NSDictionary *user = info[@"user"];
	NSString *name = MZString([user isKindOfClass:NSDictionary.class] ? user[@"username"] : nil).lowercaseString;
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	extras[MZExtrasCoverKey] = thumbnail;
	NSString *page = MZLinkURL(@"https://kick.com/%@", slug.lowercaseString);
	extras[MZExtrasTitleURLKey] = page;
	extras[MZExtrasArtistURLKey] = page;
	if (title) streams[title] = extras;
	if (name) streams[name] = extras;
}

static NSDictionary *MZExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	NSString *title = withExtras[MPNowPlayingInfoPropertyAssetURL] ? nil : MZString(info[MPMediaItemPropertyTitle]);
	if (!title) return nil;
	return streams[title] ?: streams[MZString(info[MPMediaItemPropertyArtist]).lowercaseString ?: @""];
}

%ctor {
	streams = [[MZCache alloc] initWithLimit:200];
	MZProviderCheck(@[], @[@"ExpoModulesCore.URLSessionSessionDelegateProxy -URLSession:dataTask:didReceiveData:"]);
	MZAddExtras(MZExtras);
	MZObserveResponses(^BOOL(NSURL *url) {
		return MZIsChannelInfo(url);
	}, ^(NSURL *url, NSData *body) {
		// "/", "api", "v2", "channels", "<slug>", "info"
		MZRememberInfo(body, url.path.pathComponents[4]);
	});
}
