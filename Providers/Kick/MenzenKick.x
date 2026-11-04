#import "../../Shared/MenzenProvider/MenzenProvider.h"
#import "../../Shared/MenzenProvider/MenzenResponses.h"

// The player (React Native) only has the stream's URL. The thumbnail comes
// from the channel info the app fetches as a channel opens, matched by
// stream title, else by channel name.

// By stream title and by lowercased channel name.
static MenzenCache<NSString *, NSDictionary *> *streams;

static BOOL MenzenIsChannelInfo(NSURL *url) {
	NSArray<NSString *> *parts = url.path.pathComponents;
	// "/", "api", "v2", "channels", "<slug>", "info"
	return [url.host isEqualToString:@"kick.com"] && parts.count == 6 && [parts[3] isEqualToString:@"channels"] && [parts[5] isEqualToString:@"info"];
}

static NSString *MenzenThumbnail(NSDictionary *thumbnail) {
	if (![thumbnail isKindOfClass:NSDictionary.class]) return nil;
	NSString *found = nil;
	for (id value in thumbnail.allValues) {
		NSString *url = MenzenString(value);
		if (![url hasPrefix:@"https://images.kick.com/"] || [url rangeOfString:@" "].location != NSNotFound || url.length > 256) continue;
		if ([url containsString:@"/720."]) return url;
		found = found ?: url;
	}

	return found;
}

static void MenzenRememberInfo(NSData *data, NSString *slug) {
	NSDictionary *info = MenzenJSON(data);
	NSDictionary *livestream = [info isKindOfClass:NSDictionary.class] ? info[@"livestream"] : nil;
	if (![livestream isKindOfClass:NSDictionary.class]) return;
	NSString *thumbnail = MenzenThumbnail(livestream[@"thumbnail"]);
	if (!thumbnail) return;
	NSString *title = MenzenString(livestream[@"session_title"]);
	NSDictionary *user = info[@"user"];
	NSString *name = MenzenString([user isKindOfClass:NSDictionary.class] ? user[@"username"] : nil).lowercaseString;
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	extras[MenzenExtrasCoverKey] = thumbnail;
	NSString *page = MenzenLinkURL(@"https://kick.com/%@", slug.lowercaseString);
	extras[MenzenExtrasTitleURLKey] = page;
	extras[MenzenExtrasArtistURLKey] = page;
	if (title) streams[title] = extras;
	if (name) streams[name] = extras;
}

static NSDictionary *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	NSString *title = withExtras[MPNowPlayingInfoPropertyAssetURL] ? nil : MenzenString(info[MPMediaItemPropertyTitle]);
	if (!title) return nil;
	return streams[title] ?: streams[MenzenString(info[MPMediaItemPropertyArtist]).lowercaseString ?: @""];
}

%ctor {
	streams = [[MenzenCache alloc] initWithLimit:200];
	MenzenProviderCheck(@[], @[@"ExpoModulesCore.URLSessionSessionDelegateProxy -URLSession:dataTask:didReceiveData:"]);
	MenzenAddExtras(MenzenExtras);
	MenzenObserveResponses(^BOOL(NSURL *url) {
		return MenzenIsChannelInfo(url);
	}, ^(NSURL *url, NSData *body) {
		// "/", "api", "v2", "channels", "<slug>", "info"
		MenzenRememberInfo(body, url.path.pathComponents[4]);
	});
}
