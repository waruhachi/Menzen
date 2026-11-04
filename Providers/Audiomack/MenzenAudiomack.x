#import <CoreData/CoreData.h>

#import "../../Shared/MenzenProvider/MenzenProvider.h"

// The app publishes no IDs. Its songs and albums are Core Data Items, made
// from API responses whether or not they're saved, with slugs, the album's
// ID and the uploader's picture.

static NSHashTable *items;
static Class itemClass;

// Only Items on no context (as the API's are) or on the main queue's, as
// the main thread may use them.
static BOOL MenzenUsable(NSManagedObject *item) {
	NSManagedObjectContext *context = item.managedObjectContext;
	return !item.isDeleted && (!context || context.concurrencyType == NSMainQueueConcurrencyType);
}

static id MenzenValue(NSManagedObject *item, NSString *key) {
	return item.entity.attributesByName[key] ? [item valueForKey:key] : nil;
}

static NSString *MenzenImage(NSManagedObject *item, NSString *key) {
	return MenzenImageURL(MenzenValue(item, key), @[@"audiomack.com", @".audiomack.com"]);
}

static NSString *MenzenSlug(id value) {
	return MenzenLinkURL(@"%@", MenzenString(value));
}

static NSDictionary *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	// Items belong to the main thread, where the app publishes.
	if (!NSThread.isMainThread || withExtras[MPNowPlayingInfoPropertyAssetURL]) return nil;
	NSString *title = MenzenString(info[MPMediaItemPropertyTitle]);
	NSString *artist = MenzenString(info[MPMediaItemPropertyArtist]);
	if (!title) return nil;
	NSArray *all;
	@synchronized(items) {
		all = items.allObjects;
	}

	NSManagedObject *song = nil;
	for (NSManagedObject *item in all.reverseObjectEnumerator) {
		if (!MenzenUsable(item) || ![MenzenValue(item, @"title") isEqual:title]) continue;
		NSString *itemArtist = MenzenString(MenzenValue(item, @"artist"));
		if (artist && itemArtist && ![itemArtist isEqualToString:artist]) continue;
		if (![MenzenValue(item, @"isAlbum") boolValue] && ![MenzenValue(item, @"isPlaylist") boolValue]) {
			song = item;
			break;
		}
	}

	if (!song) return nil;

	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	extras[MenzenExtrasCoverKey] = MenzenImage(song, @"image");
	NSString *uploader = MenzenSlug(MenzenValue(song, @"uploaderSlug"));
	if (uploader) {
		NSString *slug = MenzenSlug(MenzenValue(song, @"urlSlug"));
		if (slug) extras[MenzenExtrasTitleURLKey] = [NSString stringWithFormat:@"https://audiomack.com/%@/song/%@", uploader, slug];
		extras[MenzenExtrasArtistURLKey] = [@"https://audiomack.com/" stringByAppendingString:uploader];
		extras[MenzenExtrasArtistNameKey] = MenzenString(MenzenValue(song, @"uploaderName"));
		extras[MenzenExtrasArtistImageKey] = MenzenImage(song, @"uploaderImage");
	}

	NSString *albumID = MenzenString(MenzenValue(song, @"albumID"));
	if (albumID) {
		for (NSManagedObject *item in all) {
			if (!MenzenUsable(item) || ![MenzenValue(item, @"isAlbum") boolValue]) continue;
			if (![MenzenString(MenzenValue(item, @"itemID")) isEqualToString:albumID]) continue;
			NSString *albumUploader = MenzenSlug(MenzenValue(item, @"uploaderSlug"));
			NSString *albumSlug = MenzenSlug(MenzenValue(item, @"urlSlug"));
			if (albumUploader && albumSlug) extras[MenzenExtrasAlbumURLKey] = [NSString stringWithFormat:@"https://audiomack.com/%@/album/%@", albumUploader, albumSlug];
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
	MenzenProviderCheck(@[@"Item"], @[]);
	itemClass = %c(Item);
	if (!itemClass) return;
	items = [NSHashTable weakObjectsHashTable];
	MenzenAddExtras(MenzenExtras);
	%init;
}
