#import <os/lock.h>

#import "MZProvider.h"

NSString *MZString(id value) {
	if ([value isKindOfClass:NSNumber.class]) value = [value stringValue];
	return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

NSDictionary *MZDictionary(id value) {
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

NSArray *MZArray(id value) {
	return [value isKindOfClass:NSArray.class] ? value : nil;
}

id MZPath(id object, NSArray<NSString *> *keys) {
	for (NSString *key in keys) {
		if (![object isKindOfClass:NSDictionary.class]) return nil;
		object = object[key];
	}

	return object;
}

id MZGet(id object, NSString *name) {
	return [object respondsToSelector:NSSelectorFromString(name)] ? [object valueForKey:name] : nil;
}

NSString *MZImageURL(id value, NSArray<NSString *> *hosts) {
	NSString *string = [value isKindOfClass:NSURL.class] ? [value absoluteString] : MZString(value);
	if (string.length > 256) return nil;

	NSURLComponents *components = string ? [NSURLComponents componentsWithString:string] : nil;
	NSString *host = components.host.lowercaseString;
	if (![components.scheme isEqualToString:@"https"] || !host.length || components.user || components.password) return nil;

	for (NSString *allowed in hosts) {
		if ([allowed hasPrefix:@"."] ? [host hasSuffix:allowed] : [host isEqualToString:allowed]) return string;
	}

	return nil;
}

NSString *MZPairKey(NSString *first, NSString *second) {
	return first && second ? [NSString stringWithFormat:@"%@\n%@", first, second] : nil;
}

@implementation MZCache {
	NSUInteger _limit;
	NSMutableDictionary *_objects;
	NSMutableOrderedSet *_keys;
	os_unfair_lock _lock;
}

- (instancetype)initWithLimit:(NSUInteger)limit {
	if ((self = [super init])) {
		_limit = limit;
		_objects = [NSMutableDictionary dictionary];
		_keys = [NSMutableOrderedSet orderedSet];
		_lock = OS_UNFAIR_LOCK_INIT;
	}

	return self;
}

- (id)objectForKeyedSubscript:(id)key {
	if (!key) return nil;
	os_unfair_lock_lock(&_lock);
	id object = _objects[key];
	os_unfair_lock_unlock(&_lock);
	return object;
}

- (void)setObject:(id)object forKeyedSubscript:(id<NSCopying>)key {
	if (!key) return;
	os_unfair_lock_lock(&_lock);
	[_keys removeObject:key];
	if (object) {
		_objects[key] = object;
		[_keys addObject:key];
		while (_keys.count > _limit) {
			[_objects removeObjectForKey:_keys.firstObject];
			[_keys removeObjectAtIndex:0];
		}
	} else {
		[_objects removeObjectForKey:key];
	}

	os_unfair_lock_unlock(&_lock);
}

- (void)removeAllObjects {
	os_unfair_lock_lock(&_lock);
	[_objects removeAllObjects];
	[_keys removeAllObjects];
	os_unfair_lock_unlock(&_lock);
}

@end

static MZExtrasFunction extrasFunction;

static BOOL MZIsExtras(id assetURL) {
	return MZExtrasFromURL([assetURL isKindOfClass:NSURL.class] ? [assetURL absoluteString] : MZString(assetURL)) != nil;
}

%group Extras

%hook MPNowPlayingInfoCenter

- (void)setNowPlayingInfo:(NSDictionary *)info {
	if (![info isKindOfClass:NSDictionary.class]) {
		%orig;
		return;
	}

	// Apps often build an update from the info they published last, which
	// still has the extras added to it then.
	NSMutableDictionary *withExtras = [info mutableCopy];
	if (MZIsExtras(info[MPNowPlayingInfoPropertyAssetURL])) [withExtras removeObjectForKey:MPNowPlayingInfoPropertyAssetURL];

	NSDictionary *extras = extrasFunction(self, info, withExtras);
	NSURL *extrasURL = extras.count ? MZExtrasURL(extras) : nil;
	if (extrasURL) {
		withExtras[MPNowPlayingInfoPropertyAssetURL] = extrasURL;
		MZProviderWorked();
	}

	%orig(withExtras);
}

%end

%end

void MZAddExtras(MZExtrasFunction extrasFor) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		extrasFunction = extrasFor;
		%init(Extras);
	});
}

void MZRepublish(void) {
	dispatch_async(dispatch_get_main_queue(), ^{
		MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
		NSDictionary *info = center.nowPlayingInfo;
		if (info) center.nowPlayingInfo = info;
	});
}
