#import <sqlite3.h>

#import "../../Shared/MZProvider/MZProvider.h"

// The now playing code reads a short-lived Playback.PlayerItem just before
// it publishes; what the items said is matched by title and artist.

@interface SCPlayerItem : NSObject
- (NSString *)title;
// The credited artist, which may not be the uploader.
- (NSString *)artistName;
- (id)artworkURL;
- (id)permalinkURL;
// "soundcloud:users:<id>", the uploader's.
- (id)artistUrn;
// Set for private tracks; their links carry it, so they get none.
- (id)secretToken;
- (BOOL)mz_recorded;
- (void)setMz_recorded:(BOOL)recorded;
@end

@interface MZSoundCloudItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *extras;
@end

@implementation MZSoundCloudItem
@end

static NSUInteger const MZRememberedItems = 8;
static NSMutableArray<MZSoundCloudItem *> *items;
// Empty for an artist without an account.
static NSMutableDictionary<NSString *, NSDictionary *> *accounts;

static NSString *MZURLString(id value) {
	return [value isKindOfClass:NSURL.class] ? [value absoluteString] : MZString(value);
}

static id MZItemValue(SCPlayerItem *item, SEL selector) {
	return MZGet(item, NSStringFromSelector(selector));
}

// SoundCloud's image URLs name their size ("artworks-<id>-large.jpg" is
// 100x100, templates say "{size}"); ask for the 500x500 rendition.
static NSString *MZSoundCloudImageURL(NSString *string) {
	if (!string.length) return nil;
	string = [string stringByReplacingOccurrencesOfString:@"{size}" withString:@"t500x500"];
	string = [string stringByReplacingOccurrencesOfString:@"-large." withString:@"-t500x500."];
	return [[NSURL URLWithString:string].scheme isEqualToString:@"https"] ? string : nil;
}

// Lowercase letters and digits only: "Lil Tecca ✰" and "liltecca" match.
static NSString *MZNormalized(NSString *name) {
	NSMutableString *normalized = [NSMutableString string];
	NSCharacterSet *keep = NSCharacterSet.alphanumericCharacterSet;
	NSString *folded = [name stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch locale:nil].lowercaseString;
	[folded enumerateSubstringsInRange:NSMakeRange(0, folded.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *character, NSRange range, NSRange enclosing, BOOL *stop) {
		if ([character rangeOfCharacterFromSet:keep.invertedSet].location == NSNotFound) [normalized appendString:character];
	}];
	return normalized;
}

// The first of several credited artists: "A, B", "A & B", "A x B", "A feat. B".
static NSString *MZFirstArtist(NSString *artist) {
	for (NSString *separator in @[@", ", @" & ", @" x ", @" X ", @" feat. ", @" feat ", @" ft. ", @" ft ", @" (feat"]) {
		NSRange range = [artist rangeOfString:separator options:NSCaseInsensitiveSearch];
		if (range.location != NSNotFound && range.location > 0) artist = [artist substringToIndex:range.location];
	}

	return [artist stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

static NSString *MZColumn(sqlite3_stmt *statement, int column) {
	const unsigned char *text = sqlite3_column_text(statement, column);
	return text ? [NSString stringWithUTF8String:(const char *)text] : nil;
}

// The app's own copy of the accounts it has seen, read only.
static sqlite3 *MZOpenStore(void) {
	NSURL *group = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:@"group.com.soundcloud.ios"];
	NSString *path = [group URLByAppendingPathComponent:@"store.sqlite"].path;
	if (!path || ![NSFileManager.defaultManager fileExistsAtPath:path]) return NULL;
	sqlite3 *store = NULL;
	if (sqlite3_open_v2(path.fileSystemRepresentation, &store, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
		sqlite3_close(store);
		return NULL;
	}

	sqlite3_busy_timeout(store, 100);
	return store;
}

static NSDictionary *MZAccountExtras(NSString *name, NSString *permalink, NSString *avatar) {
	NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"].invertedSet;
	if (!permalink.length || [permalink rangeOfCharacterFromSet:invalid].location != NSNotFound) return nil;
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	extras[MZExtrasArtistURLKey] = [@"https://soundcloud.com/" stringByAppendingString:permalink];
	// Everyone without a picture has the same placeholder.
	if (![avatar containsString:@"default_avatar"]) extras[MZExtrasArtistImageKey] = MZSoundCloudImageURL(avatar);
	extras[MZExtrasArtistNameKey] = name;
	return extras;
}

// The credited artist's own account when the app knows it, by name or
// permalink; otherwise the uploader's.
static NSDictionary *MZLookUpAccount(NSString *artist, NSString *uploaderURN) {
	sqlite3 *store = MZOpenStore();
	if (!store) return nil;
	NSDictionary *found;
	sqlite3_stmt *statement = NULL;

	NSString *wanted = MZNormalized(MZFirstArtist(artist ?: @""));
	if (wanted.length && sqlite3_prepare_v2(store, "SELECT ZNAME, ZPERMALINK, ZAVATARURLTEMPLATE FROM ZCDUSER WHERE ZPERMALINK IS NOT NULL", -1, &statement, NULL) == SQLITE_OK) {
		while (!found && sqlite3_step(statement) == SQLITE_ROW) {
			NSString *name = MZColumn(statement, 0);
			NSString *permalink = MZColumn(statement, 1);
			if ([MZNormalized(name ?: @"") isEqualToString:wanted] || [permalink.lowercaseString isEqualToString:wanted]) {
				NSMutableDictionary *extras = [MZAccountExtras(name, permalink, MZColumn(statement, 2)) mutableCopy];
				// Their name as the track credits it, not with its decorations.
				if (extras) extras[MZExtrasArtistNameKey] = MZFirstArtist(artist);
				found = extras;
			}
		}
	}

	sqlite3_finalize(statement);
	statement = NULL;

	if (!found && [uploaderURN hasPrefix:@"soundcloud:users:"] && sqlite3_prepare_v2(store, "SELECT ZNAME, ZPERMALINK, ZAVATARURLTEMPLATE FROM ZCDUSER WHERE ZURNSTRING = ?1 LIMIT 1", -1, &statement, NULL) == SQLITE_OK) {
		sqlite3_bind_text(statement, 1, uploaderURN.UTF8String, -1, SQLITE_TRANSIENT);
		if (sqlite3_step(statement) == SQLITE_ROW) found = MZAccountExtras(MZColumn(statement, 0), MZColumn(statement, 1), MZColumn(statement, 2));
	}

	sqlite3_finalize(statement);
	sqlite3_close(store);
	return found;
}

static NSDictionary *MZAccount(NSString *artist, NSString *uploaderURN) {
	NSString *key = [NSString stringWithFormat:@"%@\n%@", artist ?: @"", uploaderURN ?: @""];
	@synchronized(accounts) {
		NSDictionary *known = accounts[key];
		if (known) return known;
	}

	NSDictionary *account = MZLookUpAccount(artist, uploaderURN) ?: @{};
	@synchronized(accounts) {
		accounts[key] = account;
	}

	return account;
}

static void MZRemember(SCPlayerItem *item, id artworkURL) {
	NSString *title = MZString(MZItemValue(item, @selector(title)));
	if (!title.length) return;
	NSString *artist = MZString(MZItemValue(item, @selector(artistName)));

	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	extras[MZExtrasCoverKey] = MZSoundCloudImageURL(MZURLString(artworkURL));
	// Never pass on a private track's links or uploader.
	if (![MZString(MZItemValue(item, @selector(secretToken))) length]) {
		extras[MZExtrasTitleURLKey] = MZURLString(MZItemValue(item, @selector(permalinkURL)));
		id uploader = MZItemValue(item, @selector(artistUrn));
		NSString *uploaderURN = MZString(uploader) ?: [uploader description];
		[extras addEntriesFromDictionary:MZAccount(artist, uploaderURN)];
	}

	if (!extras.count) return;

	MZSoundCloudItem *remembered = [MZSoundCloudItem new];
	remembered.title = title;
	remembered.artist = artist;
	remembered.extras = extras;

	@synchronized(items) {
		[items filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MZSoundCloudItem *existing, NSDictionary *bindings) {
			return !([existing.title isEqualToString:remembered.title] && (existing.artist == remembered.artist || [existing.artist isEqualToString:remembered.artist]));
		}]];
		[items addObject:remembered];
		if (items.count > MZRememberedItems) [items removeObjectAtIndex:0];
	}
}

static NSDictionary *MZExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	NSString *title = MZString(info[MPMediaItemPropertyTitle]);
	NSString *artist = MZString(info[MPMediaItemPropertyArtist]);
	NSDictionary *extras = nil;
	@synchronized(items) {
		for (MZSoundCloudItem *item in items.reverseObjectEnumerator) {
			if (title.length && [item.title isEqualToString:title] && (!artist.length || !item.artist.length || [item.artist isEqualToString:artist])) {
				extras = item.extras;
				break;
			}
		}
	}

	return extras;
}

%hook SCPlayerItem

%property (nonatomic, assign) BOOL mz_recorded;

- (id)artworkURL {
	id artworkURL = %orig;
	[self setMz_recorded:YES];
	MZRemember(self, artworkURL);
	return artworkURL;
}

// The now playing code skips the artwork when the image is cached, but it
// always reads the title.
- (NSString *)title {
	NSString *title = %orig;
	if (![self mz_recorded]) {
		[self setMz_recorded:YES];
		[self artworkURL];
	}

	return title;
}

%end

%ctor {
	MZProviderCheck(@[@"_TtC8Playback10PlayerItem -title", @"_TtC8Playback10PlayerItem -artworkURL"], @[
		@"_TtC8Playback10PlayerItem -artistName",
		@"_TtC8Playback10PlayerItem -permalinkURL",
		@"_TtC8Playback10PlayerItem -artistUrn",
		@"_TtC8Playback10PlayerItem -secretToken",
	]);
	Class playerItem = %c(_TtC8Playback10PlayerItem);
	if (!playerItem) return;
	MZAddExtras(MZExtras);
	items = [NSMutableArray array];
	accounts = [NSMutableDictionary dictionary];
	%init(SCPlayerItem = playerItem);
}
