#import <dlfcn.h>

#import "../../Shared/MenzenProvider/MenzenProvider.h"

// The cover is the last image PlayerCore fetched from the app's image
// server; the app publishes only its bytes. Untested: found from the app's
// code only.

static NSString *cover;

static BOOL MenzenIsImageServer(NSURL *url) {
	NSString *host = url.host.lowercaseString;
	return [url.scheme isEqualToString:@"https"] && ([host hasSuffix:@".discomax.com"] || [host hasSuffix:@".hbomax.com"] || [host hasSuffix:@".max.com"]);
}

static BOOL MenzenIsPlayerCore(const void *address) {
	Dl_info info;
	return dladdr(address, &info) && info.dli_fname && strstr(info.dli_fname, "/PlayerCore.framework/");
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
	NSURL *url = request.URL;
	if (MenzenIsImageServer(url) && url.absoluteString.length <= 256 && MenzenIsPlayerCore(__builtin_return_address(0))) {
		@synchronized(NSURLSession.class) {
			cover = url.absoluteString;
		}
	}

	return %orig;
}

%end

static NSDictionary *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	// Only info with the builder's picture.
	if (!info[MPMediaItemPropertyArtwork] || withExtras[MPNowPlayingInfoPropertyAssetURL]) return nil;
	@synchronized(NSURLSession.class) {
		return cover ? @{MenzenExtrasCoverKey: cover} : nil;
	}
}

%ctor {
	MenzenProviderCheck(@[], @[]);
	MenzenAddExtras(MenzenExtras);
	%init;
}
