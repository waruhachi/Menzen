#import <dlfcn.h>

#import "../../Shared/MZApps.h"
#import "../../Shared/MZProviders.h"
#import "MZAppInfo.h"

@interface AVSystemController : NSObject
+ (instancetype)sharedAVSystemController;
- (id)attributeForKey:(NSString *)key;
@end

static NSInteger const MZGenreSocialNetworking = 6005;
static NSInteger const MZGenrePhotoAndVideo = 6008;
static NSInteger const MZGenreEntertainment = 6016;
static NSInteger const MZGenreGames = 6014;
// Action through Word.
static NSRange const MZGameSubgenres = {7001, 19};

// 0 for Apple's own apps, which have none.
static NSInteger MZAppGenre(NSString *bundleIdentifier) {
	static NSMutableDictionary<NSString *, NSNumber *> *genres;
	if (!genres) genres = [NSMutableDictionary dictionary];
	if (!genres[bundleIdentifier]) {
		// Boxed either way, whatever type this iOS version declares.
		id genre = [MZAppProxy(bundleIdentifier) valueForKey:@"genreID"];
		genres[bundleIdentifier] = @([genre respondsToSelector:@selector(integerValue)] ? [genre integerValue] : 0);
	}

	return genres[bundleIdentifier].integerValue;
}

NSString *MZAppName(NSString *bundleIdentifier) {
	NSDictionary *provider = MZProviderForBundleIdentifier(bundleIdentifier);
	if (provider) return provider[MZProviderNameKey];
	static NSMutableDictionary<NSString *, NSString *> *names;
	if (!names) names = [NSMutableDictionary dictionary];
	if (!names[bundleIdentifier]) {
		NSString *name = MZAppProxy(bundleIdentifier).localizedName;
		names[bundleIdentifier] = [name isKindOfClass:NSString.class] && name.length ? name : bundleIdentifier;
	}

	return names[bundleIdentifier];
}

BOOL MZIsChatApp(NSString *bundleIdentifier) {
	static NSSet<NSString *> *apple;
	if (!apple) apple = [NSSet setWithArray:@[@"com.apple.MobileSMS", @"com.apple.facetime", @"com.apple.mobilephone", @"com.apple.VoiceMemos"]];
	return [apple containsObject:bundleIdentifier] || MZAppGenre(bundleIdentifier) == MZGenreSocialNetworking;
}

BOOL MZIsBrowserApp(NSString *bundleIdentifier) {
	static NSMutableDictionary<NSString *, NSNumber *> *browsers;
	if (!browsers) browsers = [NSMutableDictionary dictionary];
	if (!browsers[bundleIdentifier]) {
		// Safari's views in other apps play under their own name.
		BOOL browser = [bundleIdentifier isEqualToString:@"com.apple.SafariViewService"];
		// Every app that can be the default browser has this entitlement.
		browser = browser || [[MZAppProxy(bundleIdentifier) entitlementValueForKey:@"com.apple.developer.web-browser" ofClass:NSNumber.class] boolValue];
		browsers[bundleIdentifier] = @(browser);
	}

	return browsers[bundleIdentifier].boolValue;
}

BOOL MZIsVideoApp(NSString *bundleIdentifier) {
	static NSArray<NSString *> *streamingApps;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		dlopen("/System/Library/PrivateFrameworks/MediaExperience.framework/MediaExperience", RTLD_LAZY);
		id list = [[NSClassFromString(@"AVSystemController") sharedAVSystemController] attributeForKey:@"AVSystemController_LongFormVideoAppsAttribute"];
		streamingApps = [list isKindOfClass:NSArray.class] ? list : @[];
	});
	if ([streamingApps containsObject:bundleIdentifier]) return YES;
	NSInteger genre = MZAppGenre(bundleIdentifier);
	return genre == MZGenrePhotoAndVideo || genre == MZGenreEntertainment;
}

BOOL MZIsGameApp(NSString *bundleIdentifier) {
	NSInteger genre = MZAppGenre(bundleIdentifier);
	return genre == MZGenreGames || NSLocationInRange(genre, MZGameSubgenres);
}
