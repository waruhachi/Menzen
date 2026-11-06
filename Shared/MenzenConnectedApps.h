#import <Foundation/Foundation.h>

#import "MenzenSettings.h"

NS_ASSUME_NONNULL_BEGIN

// Connected Apps: other tweaks showing activity through libmenzen
// (Client/Menzen.h), each only once the user allows it.

#define MenzenConnectedServiceName @"moe.waru.menzend.api"
// The libSandy profile that lets sandboxed processes look the service up.
#define MenzenConnectedSandyProfile "Menzen"
// Posted by menzend when an app registers or changes its name.
#define MenzenConnectedAppsChangedNotification "moe.waru.menzen.connected"

// BOOL, default NO.
#define MenzenSettingConnected @"connected"
// Dictionary: identifier to MenzenConnectedApp*Key, every app that has
// registered. Written by menzend only.
#define MenzenSettingConnectedApps @"connectedApps"
// Array of the identifiers the user allows. Written by the pane only.
#define MenzenSettingConnectedAllowed @"connectedAllowed"

#define MenzenConnectedAppNameKey @"name"
// The signing identifier of the process it last registered from.
#define MenzenConnectedAppProcessKey @"process"

// No more are kept, so a misbehaving client can't fill the settings.
static NSUInteger const MenzenConnectedAppLimit = 100;

// What the client sends: MenzenActivity*Key (MenzenService.h), with image
// URLs as strings and dates in seconds since 1970.
@protocol MenzenConnectedService
- (void)registerWithIdentifier:(NSString *)identifier name:(NSString *)name;
- (void)setActivity:(nullable NSDictionary<NSString *, id> *)activity;
@end

@protocol MenzenConnectedClient
// MenzenClientState.
- (void)stateChanged:(NSInteger)state;
@end

static inline NSXPCInterface *MenzenConnectedServiceInterface(void) {
	NSXPCInterface *interface = [NSXPCInterface interfaceWithProtocol:@protocol(MenzenConnectedService)];
	NSSet *classes = [NSSet setWithObjects:NSDictionary.class, NSString.class, NSNumber.class, nil];
	[interface setClasses:classes forSelector:@selector(setActivity:) argumentIndex:0 ofReply:NO];
	return interface;
}

static inline NSXPCInterface *MenzenConnectedClientInterface(void) {
	return [NSXPCInterface interfaceWithProtocol:@protocol(MenzenConnectedClient)];
}

static inline BOOL MenzenConnectedIdentifierIsValid(NSString *_Nullable identifier) {
	if (![identifier isKindOfClass:NSString.class] || !identifier.length || identifier.length > 128) return NO;
	NSMutableCharacterSet *allowed = [NSMutableCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"];
	return [identifier rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

// The name trimmed, or nil if it's empty or too long.
static inline NSString *_Nullable MenzenConnectedName(NSString *_Nullable name) {
	if (![name isKindOfClass:NSString.class]) return nil;
	name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	return name.length && name.length <= 64 ? name : nil;
}

static inline NSDictionary<NSString *, NSDictionary *> *MenzenConnectedApps(void) {
	NSDictionary *apps = MenzenSettingValue(MenzenSettingConnectedApps);
	if (![apps isKindOfClass:NSDictionary.class]) return @{};
	NSMutableDictionary *valid = [NSMutableDictionary dictionary];
	[apps enumerateKeysAndObjectsUsingBlock:^(id identifier, id app, BOOL *stop) {
		if (MenzenConnectedIdentifierIsValid(identifier) && [app isKindOfClass:NSDictionary.class] && MenzenConnectedName(app[MenzenConnectedAppNameKey])) valid[identifier] = app;
	}];
	return valid;
}

static inline NSArray<NSString *> *MenzenConnectedAllowed(void) {
	NSArray *allowed = MenzenSettingValue(MenzenSettingConnectedAllowed);
	if (![allowed isKindOfClass:NSArray.class]) return @[];
	return [allowed filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id identifier, NSDictionary *bindings) {
		return MenzenConnectedIdentifierIsValid(identifier);
	}]];
}

NS_ASSUME_NONNULL_END
