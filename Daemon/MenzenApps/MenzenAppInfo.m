#import <dlfcn.h>

#import "../../Shared/MenzenApps.h"
#import "../../Shared/MenzenProviders.h"
#import "MenzenAppInfo.h"

@interface AVSystemController : NSObject
+ (instancetype)sharedAVSystemController;
- (id)attributeForKey:(NSString *)key;
@end

static NSInteger const MenzenGenreSocialNetworking = 6005;
static NSInteger const MenzenGenrePhotoAndVideo = 6008;
static NSInteger const MenzenGenreEntertainment = 6016;
static NSInteger const MenzenGenreGames = 6014;
// Action through Word.
static NSRange const MenzenGameSubgenres = {7001, 19};

// 0 for Apple's own apps, which have none.
static NSInteger MenzenAppGenre(NSString *bundleIdentifier) {
	static NSMutableDictionary<NSString *, NSNumber *> *genres;
	if (!genres) genres = [NSMutableDictionary dictionary];
	if (!genres[bundleIdentifier]) {
		// Boxed either way, whatever type this iOS version declares.
		id genre = [MenzenAppProxy(bundleIdentifier) valueForKey:@"genreID"];
		genres[bundleIdentifier] = @([genre respondsToSelector:@selector(integerValue)] ? [genre integerValue] : 0);
	}

	return genres[bundleIdentifier].integerValue;
}

NSString *MenzenAppName(NSString *bundleIdentifier) {
	NSDictionary *provider = MenzenProviderForBundleIdentifier(bundleIdentifier);
	if (provider) return provider[MenzenProviderNameKey];
	static NSMutableDictionary<NSString *, NSString *> *names;
	if (!names) names = [NSMutableDictionary dictionary];
	if (!names[bundleIdentifier]) {
		NSString *name = MenzenAppProxy(bundleIdentifier).localizedName;
		names[bundleIdentifier] = [name isKindOfClass:NSString.class] && name.length ? name : bundleIdentifier;
	}

	return names[bundleIdentifier];
}

BOOL MenzenIsChatApp(NSString *bundleIdentifier) {
	static NSSet<NSString *> *apple;
	if (!apple) apple = [NSSet setWithArray:@[@"com.apple.MobileSMS", @"com.apple.facetime", @"com.apple.mobilephone", @"com.apple.VoiceMemos"]];
	return [apple containsObject:bundleIdentifier] || MenzenAppGenre(bundleIdentifier) == MenzenGenreSocialNetworking;
}

BOOL MenzenIsBrowserApp(NSString *bundleIdentifier) {
	static NSMutableDictionary<NSString *, NSNumber *> *browsers;
	if (!browsers) browsers = [NSMutableDictionary dictionary];
	if (!browsers[bundleIdentifier]) {
		// Safari's views in other apps play under their own name.
		BOOL browser = [bundleIdentifier isEqualToString:@"com.apple.SafariViewService"];
		// Every app that can be the default browser has this entitlement.
		browser = browser || [[MenzenAppProxy(bundleIdentifier) entitlementValueForKey:@"com.apple.developer.web-browser" ofClass:NSNumber.class] boolValue];
		browsers[bundleIdentifier] = @(browser);
	}

	return browsers[bundleIdentifier].boolValue;
}

BOOL MenzenIsVideoApp(NSString *bundleIdentifier) {
	static NSArray<NSString *> *streamingApps;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		dlopen("/System/Library/PrivateFrameworks/MediaExperience.framework/MediaExperience", RTLD_LAZY);
		id list = [[NSClassFromString(@"AVSystemController") sharedAVSystemController] attributeForKey:@"AVSystemController_LongFormVideoAppsAttribute"];
		streamingApps = [list isKindOfClass:NSArray.class] ? list : @[];
	});
	if ([streamingApps containsObject:bundleIdentifier]) return YES;
	NSInteger genre = MenzenAppGenre(bundleIdentifier);
	return genre == MenzenGenrePhotoAndVideo || genre == MenzenGenreEntertainment;
}

BOOL MenzenIsGameApp(NSString *bundleIdentifier) {
	NSInteger genre = MenzenAppGenre(bundleIdentifier);
	return genre == MenzenGenreGames || NSLocationInRange(genre, MenzenGameSubgenres);
}
