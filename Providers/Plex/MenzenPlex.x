#import <objc/runtime.h>

#import "../../Shared/MenzenProvider/MenzenProvider.h"

// The engine's load configuration has the item's imageUri. Only pictures on
// plex.tv are used: the rest are on the user's server with their
// X-Plex-Token. Untested: found from the app's code only.

static NSString *loadedTitle;
static NSString *loadedIdentifier;
static NSString *loadedCover;
static NSString *loadedPage;

// A picture on Plex's own servers, never one with credentials.
static NSString *MenzenCover(NSString *imageURI) {
	NSString *cover = MenzenImageURL(imageURI, @[@"plex.tv", @".plex.tv"]);
	return cover && [cover rangeOfString:@"token" options:NSCaseInsensitiveSearch].location == NSNotFound ? cover : nil;
}

static void MenzenRememberLoad(id configuration) {
	NSDictionary *metadata = [configuration isKindOfClass:NSDictionary.class] ? configuration[@"metadata"] : nil;
	if (![metadata isKindOfClass:NSDictionary.class]) metadata = [configuration isKindOfClass:NSDictionary.class] ? configuration : nil;
	@synchronized(MPNowPlayingInfoCenter.class) {
		loadedTitle = MenzenString(metadata[@"title"]);
		loadedIdentifier = MenzenString(metadata[@"contentIdentifier"]);
		loadedCover = MenzenCover(MenzenString(metadata[@"imageUri"]));
		loadedPage = MenzenString(metadata[@"publicPageUri"]);
	}
}

%group Engine

%hook NativeEngineManager

- (void)load:(id)uri startOffsetMs:(long long)startOffsetMs configuration:(id)configuration {
	MenzenRememberLoad(configuration);
	%orig;
}

%end

%end

%group EngineNext

%hook NativeEngineManagerNext

- (void)load:(id)uri startOffsetMs:(long long)startOffsetMs configuration:(id)configuration {
	MenzenRememberLoad(configuration);
	%orig;
}

%end

%end

static NSDictionary *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	if (withExtras[MPNowPlayingInfoPropertyAssetURL]) return nil;
	NSString *title = MenzenString(info[MPMediaItemPropertyTitle]);
	NSString *identifier = MenzenString(info[MPNowPlayingInfoPropertyExternalContentIdentifier]);
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	@synchronized(MPNowPlayingInfoCenter.class) {
		// Only the loaded item's.
		if ((identifier && [identifier isEqualToString:loadedIdentifier]) || (title && [title isEqualToString:loadedTitle])) {
			extras[MenzenExtrasCoverKey] = loadedCover;
			extras[MenzenExtrasTitleURLKey] = loadedPage;
		}
	}

	return extras;
}

%ctor {
	MenzenProviderCheck(@[@"plex_react_native_video.NativeEngineManager -load:startOffsetMs:configuration: | plex_react_native_video.NativeEngineManagerNext -load:startOffsetMs:configuration:"], @[]);
	MenzenAddExtras(MenzenExtras);
	%init;
	Class engine = objc_getClass("plex_react_native_video.NativeEngineManager");
	if (engine) %init(Engine, NativeEngineManager = engine);
	Class engineNext = objc_getClass("plex_react_native_video.NativeEngineManagerNext");
	if (engineNext) %init(EngineNext, NativeEngineManagerNext = engineNext);
}
