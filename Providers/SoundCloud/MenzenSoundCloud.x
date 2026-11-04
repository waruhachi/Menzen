#import <sqlite3.h>

#import "../../Shared/MenzenProvider/MenzenProvider.h"

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
- (BOOL)menzen_recorded;
- (void)setMz_recorded:(BOOL)recorded;
@end

@interface MenzenSoundCloudItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *extras;
@end

@implementation MenzenSoundCloudItem
@end

static NSUInteger const MenzenRememberedItems = 8;
static NSMutableArray<MenzenSoundCloudItem *> *items;
// Empty for an artist without an account.
static NSMutableDictionary<NSString *, NSDictionary *> *accounts;

static NSString *MenzenURLString(id value) {
	return [value isKindOfClass:NSURL.class] ? [value absoluteString] : MenzenString(value);
}

static id MenzenItemValue(SCPlayerItem *item, SEL selector) {
	return MenzenGet(item, NSStringFromSelector(selector));
}

// SoundCloud's image URLs name their size ("artworks-<id>-large.jpg" is
// 100x100, templates say "{size}"); ask for the 500x500 rendition.
static NSString *MenzenSoundCloudImageURL(NSString *string) {
	if (!string.length) return nil;
	string = [string stringByReplacingOccurrencesOfString:@"{size}" withString:@"t500x500"];
	string = [string stringByReplacingOccurrencesOfString:@"-large." withString:@"-t500x500."];
	return [[NSURL URLWithString:string].scheme isEqualToString:@"https"] ? string : nil;
}

// Lowercase letters and digits only: "Lil Tecca ✰" and "liltecca" match.
static NSString *MenzenNormalized(NSString *name) {
	NSMutableString *normalized = [NSMutableString string];
	NSCharacterSet *keep = NSCharacterSet.alphanumericCharacterSet;
	NSString *folded = [name stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch locale:nil].lowercaseString;
	[folded enumerateSubstringsInRange:NSMakeRange(0, folded.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *character, NSRange range, NSRange enclosing, BOOL *stop) {
		if ([character rangeOfCharacterFromSet:keep.invertedSet].location == NSNotFound) [normalized appendString:character];
	}];
	return normalized;
}

// The first of several credited artists: "A, B", "A & B", "A x B", "A feat. B".
static NSString *MenzenFirstArtist(NSString *artist) {
	for (NSString *separator in @[@", ", @" & ", @" x ", @" X ", @" feat. ", @" feat ", @" ft. ", @" ft ", @" (feat"]) {
		NSRange range = [artist rangeOfString:separator options:NSCaseInsensitiveSearch];
		if (range.location != NSNotFound && range.location > 0) artist = [artist substringToIndex:range.location];
	}

	return [artist stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

static NSString *MenzenColumn(sqlite3_stmt *statement, int column) {
	const unsigned char *text = sqlite3_column_text(statement, column);
	return text ? [NSString stringWithUTF8String:(const char *)text] : nil;
}

// The app's own copy of the accounts it has seen, read only.
static sqlite3 *MenzenOpenStore(void) {
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

static NSDictionary *MenzenAccountExtras(NSString *name, NSString *permalink, NSString *avatar) {
	NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"].invertedSet;
	if (!permalink.length || [permalink rangeOfCharacterFromSet:invalid].location != NSNotFound) return nil;
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	extras[MenzenExtrasArtistURLKey] = [@"https://soundcloud.com/" stringByAppendingString:permalink];
	// Everyone without a picture has the same placeholder.
	if (![avatar containsString:@"default_avatar"]) extras[MenzenExtrasArtistImageKey] = MenzenSoundCloudImageURL(avatar);
	extras[MenzenExtrasArtistNameKey] = name;
	return extras;
}

// The credited artist's own account when the app knows it, by name or
// permalink; otherwise the uploader's.
static NSDictionary *MenzenLookUpAccount(NSString *artist, NSString *uploaderURN) {
	sqlite3 *store = MenzenOpenStore();
	if (!store) return nil;
	NSDictionary *found;
	sqlite3_stmt *statement = NULL;

	NSString *wanted = MenzenNormalized(MenzenFirstArtist(artist ?: @""));
	if (wanted.length && sqlite3_prepare_v2(store, "SELECT ZNAME, ZPERMALINK, ZAVATARURLTEMPLATE FROM ZCDUSER WHERE ZPERMALINK IS NOT NULL", -1, &statement, NULL) == SQLITE_OK) {
		while (!found && sqlite3_step(statement) == SQLITE_ROW) {
			NSString *name = MenzenColumn(statement, 0);
			NSString *permalink = MenzenColumn(statement, 1);
			if ([MenzenNormalized(name ?: @"") isEqualToString:wanted] || [permalink.lowercaseString isEqualToString:wanted]) {
				NSMutableDictionary *extras = [MenzenAccountExtras(name, permalink, MenzenColumn(statement, 2)) mutableCopy];
				// Their name as the track credits it, not with its decorations.
				if (extras) extras[MenzenExtrasArtistNameKey] = MenzenFirstArtist(artist);
				found = extras;
			}
		}
	}

	sqlite3_finalize(statement);
	statement = NULL;

	if (!found && [uploaderURN hasPrefix:@"soundcloud:users:"] && sqlite3_prepare_v2(store, "SELECT ZNAME, ZPERMALINK, ZAVATARURLTEMPLATE FROM ZCDUSER WHERE ZURNSTRING = ?1 LIMIT 1", -1, &statement, NULL) == SQLITE_OK) {
		sqlite3_bind_text(statement, 1, uploaderURN.UTF8String, -1, SQLITE_TRANSIENT);
		if (sqlite3_step(statement) == SQLITE_ROW) found = MenzenAccountExtras(MenzenColumn(statement, 0), MenzenColumn(statement, 1), MenzenColumn(statement, 2));
	}

	sqlite3_finalize(statement);
	sqlite3_close(store);
	return found;
}

static NSDictionary *MenzenAccount(NSString *artist, NSString *uploaderURN) {
	NSString *key = [NSString stringWithFormat:@"%@\n%@", artist ?: @"", uploaderURN ?: @""];
	@synchronized(accounts) {
		NSDictionary *known = accounts[key];
		if (known) return known;
	}

	NSDictionary *account = MenzenLookUpAccount(artist, uploaderURN) ?: @{};
	@synchronized(accounts) {
		accounts[key] = account;
	}

	return account;
}

static void MenzenRemember(SCPlayerItem *item, id artworkURL) {
	NSString *title = MenzenString(MenzenItemValue(item, @selector(title)));
	if (!title.length) return;
	NSString *artist = MenzenString(MenzenItemValue(item, @selector(artistName)));

	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	extras[MenzenExtrasCoverKey] = MenzenSoundCloudImageURL(MenzenURLString(artworkURL));
	// Never pass on a private track's links or uploader.
	if (![MenzenString(MenzenItemValue(item, @selector(secretToken))) length]) {
		extras[MenzenExtrasTitleURLKey] = MenzenURLString(MenzenItemValue(item, @selector(permalinkURL)));
		id uploader = MenzenItemValue(item, @selector(artistUrn));
		NSString *uploaderURN = MenzenString(uploader) ?: [uploader description];
		[extras addEntriesFromDictionary:MenzenAccount(artist, uploaderURN)];
	}

	if (!extras.count) return;

	MenzenSoundCloudItem *remembered = [MenzenSoundCloudItem new];
	remembered.title = title;
	remembered.artist = artist;
	remembered.extras = extras;

	@synchronized(items) {
		[items filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MenzenSoundCloudItem *existing, NSDictionary *bindings) {
			return !([existing.title isEqualToString:remembered.title] && (existing.artist == remembered.artist || [existing.artist isEqualToString:remembered.artist]));
		}]];
		[items addObject:remembered];
		if (items.count > MenzenRememberedItems) [items removeObjectAtIndex:0];
	}
}

static NSDictionary *MenzenExtras(MPNowPlayingInfoCenter *center, NSDictionary *info, NSMutableDictionary *withExtras) {
	NSString *title = MenzenString(info[MPMediaItemPropertyTitle]);
	NSString *artist = MenzenString(info[MPMediaItemPropertyArtist]);
	NSDictionary *extras = nil;
	@synchronized(items) {
		for (MenzenSoundCloudItem *item in items.reverseObjectEnumerator) {
			if (title.length && [item.title isEqualToString:title] && (!artist.length || !item.artist.length || [item.artist isEqualToString:artist])) {
				extras = item.extras;
				break;
			}
		}
	}

	return extras;
}

%hook SCPlayerItem

%property (nonatomic, assign) BOOL menzen_recorded;

- (id)artworkURL {
	id artworkURL = %orig;
	[self setMz_recorded:YES];
	MenzenRemember(self, artworkURL);
	return artworkURL;
}

// The now playing code skips the artwork when the image is cached, but it
// always reads the title.
- (NSString *)title {
	NSString *title = %orig;
	if (![self menzen_recorded]) {
		[self setMz_recorded:YES];
		[self artworkURL];
	}

	return title;
}

%end

%ctor {
	MenzenProviderCheck(@[@"_TtC8Playback10PlayerItem -title", @"_TtC8Playback10PlayerItem -artworkURL"], @[
		@"_TtC8Playback10PlayerItem -artistName",
		@"_TtC8Playback10PlayerItem -permalinkURL",
		@"_TtC8Playback10PlayerItem -artistUrn",
		@"_TtC8Playback10PlayerItem -secretToken",
	]);
	Class playerItem = %c(_TtC8Playback10PlayerItem);
	if (!playerItem) return;
	MenzenAddExtras(MenzenExtras);
	items = [NSMutableArray array];
	accounts = [NSMutableDictionary dictionary];
	%init(SCPlayerItem = playerItem);
}
