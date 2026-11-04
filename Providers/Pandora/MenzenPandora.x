#import <objc/runtime.h>

#import "../../Shared/MenzenProvider/MenzenProvider.h"

// The external content ID is the track's Pandora ID ("TR:<n>::<n>"). Station
// tracks keep the API's answer (-response), with the cover and pages.
//
// The artist's picture comes from the track details page (HTML) the app
// loads as each track starts, matched by artist name; the track's ID is only
// in its lyrics, which not every track has.

// By Pandora ID ("TR:<n>").
static MenzenCache<NSString *, NSDictionary *> *tracks;
static MenzenCache<NSString *, NSString *> *pictures;
static dispatch_queue_t queue;

@interface NSObject (MenzenPandora)
- (id)response;
@end

@interface PMHTTPConnection : NSObject
- (NSURLRequest *)request;
- (NSData *)receivedData;
@end

static BOOL MenzenIsPath(NSString *path) {
	static NSCharacterSet *invalid;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		invalid = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./"].invertedSet;
	});
	return path.length > 1 && path.length <= 200 && [path rangeOfCharacterFromSet:invalid].location == NSNotFound && ![path containsString:@".."];
}

// A page on www.pandora.com, without its query (tracking).
static NSString *MenzenPageURL(id value) {
	NSURL *url = [NSURL URLWithString:MenzenString(value) ?: @""];
	if (![url.host.lowercaseString isEqualToString:@"www.pandora.com"] || !MenzenIsPath(url.path) || [url.path hasPrefix:@"/content/"]) return nil;
	return [@"https://www.pandora.com" stringByAppendingString:url.path];
}

// The cover at 500 px from Pandora's image CDN, which serves the same
// /images/ paths as the image servers the app uses (mediaserver-*.pandora.com,
// cont-*.p-cdn.us).
static NSString *MenzenCoverURL(id value) {
	NSURL *url = [NSURL URLWithString:MenzenString(value) ?: @""];
	NSString *path = url.path;
	NSString *host = url.host.lowercaseString;
	BOOL pandora = [host hasSuffix:@".pandora.com"] || [host hasSuffix:@".p-cdn.us"] || [host hasSuffix:@".p-cdn.com"];
	if (!pandora || ![path hasPrefix:@"/images/"] || !MenzenIsPath(path)) return nil;
	return [NSString stringWithFormat:@"https://content-images.p-cdn.com%@/500W_500H.jpg", path.stringByDeletingLastPathComponent];
}

static void MenzenRemember(id track) {
	id response = [track respondsToSelector:@selector(response)] ? [track response] : nil;
	if (![response isKindOfClass:NSDictionary.class]) return;
	NSString *pandoraID = MenzenString(response[@"pandoraId"]);
	if (![pandoraID hasPrefix:@"TR:"] || tracks[pandoraID]) return;
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	extras[MenzenExtrasCoverKey] = MenzenCoverURL(response[@"albumArtUrl"]);
	extras[MenzenExtrasTitleURLKey] = MenzenPageURL(response[@"songDetailUrl"]);
	extras[MenzenExtrasAlbumURLKey] = MenzenPageURL(response[@"albumDetailUrl"]);
	extras[MenzenExtrasArtistURLKey] = MenzenPageURL(response[@"artistDetailUrl"]);
	tracks[pandoraID] = extras;
}

static NSString *MenzenTextAfter(NSString *page, NSString *marker, NSString *start, NSString *end) {
	NSRange found = marker ? [page rangeOfString:marker] : NSMakeRange(0, 0);
	if (found.location == NSNotFound) return nil;
	NSRange from = [page rangeOfString:start options:0 range:NSMakeRange(NSMaxRange(found), page.length - NSMaxRange(found))];
	if (from.location == NSNotFound) return nil;
	NSRange to = [page rangeOfString:end options:0 range:NSMakeRange(NSMaxRange(from), MIN(page.length - NSMaxRange(from), 300))];
	if (to.location == NSNotFound) return nil;
	return [page substringWithRange:NSMakeRange(NSMaxRange(from), to.location - NSMaxRange(from))];
}

// HTML text without its character references (&amp;, &#39;, &#x27;).
static NSString *MenzenUnescape(NSString *html) {
	NSMutableString *text = [NSMutableString string];
	NSScanner *scanner = [NSScanner scannerWithString:html];
	scanner.charactersToBeSkipped = nil;
	NSDictionary *named = @{@"amp": @"&", @"lt": @"<", @"gt": @">", @"quot": @"\"", @"apos": @"'", @"nbsp": @" "};
	while (!scanner.isAtEnd) {
		NSString *part;
		if ([scanner scanUpToString:@"&" intoString:&part]) [text appendString:part];
		if (scanner.isAtEnd) break;
		scanner.scanLocation++;
		NSString *name;
		if ([scanner scanUpToString:@";" intoString:&name] && !scanner.isAtEnd && name.length <= 8) {
			scanner.scanLocation++;
			unsigned code = 0;
			if ([name hasPrefix:@"#x"] || [name hasPrefix:@"#X"]) [[NSScanner scannerWithString:[name substringFromIndex:2]] scanHexInt:&code];
			else if ([name hasPrefix:@"#"]) code = (unsigned)[name substringFromIndex:1].integerValue;
			if (named[name]) [text appendString:named[name]];
			else if (code > 0 && code <= 0x10FFFF) {
				UTF32Char character = code;
				[text appendString:[[NSString alloc] initWithBytes:&character length:4 encoding:NSUTF32LittleEndianStringEncoding] ?: @""];
			} else [text appendFormat:@"&%@;", name];
		} else {
			[text appendString:@"&"];
			if (name) [text appendString:name];
		}
	}

	return text;
}

static void MenzenRememberDetails(NSData *data) {
	NSString *page = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	NSString *picture = MenzenCoverURL(MenzenTextAfter(page, @"media--artistRow", @"background-image:url('", @"'"));
	NSString *name = MenzenTextAfter(page, @"media--artistRow", @"data-qa=\"nowPlayingtrackDetailPage_artist_name\">", @"<");
	NSString *artist = name ? [MenzenUnescape(name) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
	if (!picture || !artist.length) return;
	if ([pictures[artist] isEqualToString:picture]) return;
	pictures[artist] = picture;
	MenzenRepublish();
}

%hook PMHTTPConnection

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
	NSURL *url = [self respondsToSelector:@selector(request)] ? self.request.URL : nil;
	NSData *data = !error && [self respondsToSelector:@selector(receivedData)] ? self.receivedData : nil;
	NSInteger status = [task.response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)task.response).statusCode : 0;
	if ([url.host.lowercaseString isEqualToString:@"www.pandora.com"] && [url.path isEqualToString:@"/content/mobile/nowplaying_track_detail.vm"] && status == 200 && [data isKindOfClass:NSData.class] && data.length <= 1024 * 1024) {
		NSData *copy = [data copy];
		dispatch_async(queue, ^{
			MenzenRememberDetails(copy);
		});
	}

	%orig;
}

%end

%group Station

%hook Track

- (void)registerPlaybackStarted {
	%orig;
	MenzenRemember(self);
}

- (NSString *)pandoraId {
	NSString *pandoraID = %orig;
	MenzenRemember(self);
	return pandoraID;
}

%end

%end

static NSDictionary *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	if (withExtras[MPNowPlayingInfoPropertyAssetURL]) return nil;
	// "TR:<n>::<n>".
	NSString *pandoraID = [MenzenString(info[MPNowPlayingInfoPropertyExternalContentIdentifier]) componentsSeparatedByString:@"::"].firstObject;
	NSMutableDictionary *extras = pandoraID ? [tracks[pandoraID] mutableCopy] : nil;
	NSString *artist = MenzenString(info[MPMediaItemPropertyArtist]);
	if (extras && artist) extras[MenzenExtrasArtistImageKey] = pictures[artist];
	return extras;
}

%ctor {
	tracks = [[MenzenCache alloc] initWithLimit:2000];
	pictures = [[MenzenCache alloc] initWithLimit:1000];
	queue = dispatch_queue_create("moe.waru.menzen.pandora", DISPATCH_QUEUE_SERIAL);
	MenzenProviderCheck(@[
		@"PMCore.StationTrackModel -response",
		@"PMCore.StationTrackModel -pandoraId | PMCore.StationTrackModel -registerPlaybackStarted",
	], @[
		@"PMHTTPConnection -URLSession:task:didCompleteWithError:",
		@"PMHTTPConnection -request",
		@"PMHTTPConnection -receivedData",
	]);
	MenzenAddExtras(MenzenExtras);
	%init;
	Class track = objc_getClass("PMCore.StationTrackModel");
	if (track) %init(Station, Track = track);
}
