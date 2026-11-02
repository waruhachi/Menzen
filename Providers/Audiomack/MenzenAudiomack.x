#import <CoreData/CoreData.h>

#import "../../Shared/MZProvider/MZProvider.h"

// The app publishes no IDs. Its songs and albums are Core Data Items, made
// from API responses whether or not they're saved, with slugs, the album's
// ID and the uploader's picture.

static NSHashTable *items;
static Class itemClass;

// Only Items on no context (as the API's are) or on the main queue's, as
// the main thread may use them.
static BOOL MZUsable(NSManagedObject *item) {
	NSManagedObjectContext *context = item.managedObjectContext;
	return !item.isDeleted && (!context || context.concurrencyType == NSMainQueueConcurrencyType);
}

static id MZValue(NSManagedObject *item, NSString *key) {
	return item.entity.attributesByName[key] ? [item valueForKey:key] : nil;
}

static NSString *MZImage(NSManagedObject *item, NSString *key) {
	return MZImageURL(MZValue(item, key), @[@"audiomack.com", @".audiomack.com"]);
}

static NSString *MZSlug(id value) {
	return MZLinkURL(@"%@", MZString(value));
}

static NSDictionary *MZExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	// Items belong to the main thread, where the app publishes.
	if (!NSThread.isMainThread || withExtras[MPNowPlayingInfoPropertyAssetURL]) return nil;
	NSString *title = MZString(info[MPMediaItemPropertyTitle]);
	NSString *artist = MZString(info[MPMediaItemPropertyArtist]);
	if (!title) return nil;
	NSArray *all;
	@synchronized(items) {
		all = items.allObjects;
	}

	NSManagedObject *song = nil;
	for (NSManagedObject *item in all.reverseObjectEnumerator) {
		if (!MZUsable(item) || ![MZValue(item, @"title") isEqual:title]) continue;
		NSString *itemArtist = MZString(MZValue(item, @"artist"));
		if (artist && itemArtist && ![itemArtist isEqualToString:artist]) continue;
		if (![MZValue(item, @"isAlbum") boolValue] && ![MZValue(item, @"isPlaylist") boolValue]) {
			song = item;
			break;
		}
	}

	if (!song) return nil;

	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	extras[MZExtrasCoverKey] = MZImage(song, @"image");
	NSString *uploader = MZSlug(MZValue(song, @"uploaderSlug"));
	if (uploader) {
		NSString *slug = MZSlug(MZValue(song, @"urlSlug"));
		if (slug) extras[MZExtrasTitleURLKey] = [NSString stringWithFormat:@"https://audiomack.com/%@/song/%@", uploader, slug];
		extras[MZExtrasArtistURLKey] = [@"https://audiomack.com/" stringByAppendingString:uploader];
		extras[MZExtrasArtistNameKey] = MZString(MZValue(song, @"uploaderName"));
		extras[MZExtrasArtistImageKey] = MZImage(song, @"uploaderImage");
	}

	NSString *albumID = MZString(MZValue(song, @"albumID"));
	if (albumID) {
		for (NSManagedObject *item in all) {
			if (!MZUsable(item) || ![MZValue(item, @"isAlbum") boolValue]) continue;
			if (![MZString(MZValue(item, @"itemID")) isEqualToString:albumID]) continue;
			NSString *albumUploader = MZSlug(MZValue(item, @"uploaderSlug"));
			NSString *albumSlug = MZSlug(MZValue(item, @"urlSlug"));
			if (albumUploader && albumSlug) extras[MZExtrasAlbumURLKey] = [NSString stringWithFormat:@"https://audiomack.com/%@/album/%@", albumUploader, albumSlug];
			break;
		}
	}

	return extras;
}

// Swift makes Items without going through Item's own ObjC initializer, but
// it always calls NSManagedObject's.
%hook NSManagedObject

- (id)initWithEntity:(NSEntityDescription *)entity insertIntoManagedObjectContext:(NSManagedObjectContext *)context {
	id item = %orig;
	if ([item isKindOfClass:itemClass]) {
		@synchronized(items) {
			[items addObject:item];
		}
	}

	return item;
}

%end

%ctor {
	MZProviderCheck(@[@"Item"], @[]);
	itemClass = %c(Item);
	if (!itemClass) return;
	items = [NSHashTable weakObjectsHashTable];
	MZAddExtras(MZExtras);
	%init;
}
