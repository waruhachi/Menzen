#import <Foundation/Foundation.h>

#import "MenzenSettings.h"

#define MenzenConnectedServiceName @"moe.waru.menzend.api"
#define MenzenConnectedSandyProfile "Menzen"
#define MenzenConnectedAppsChangedNotification "moe.waru.menzen.connected"

#define MenzenSettingConnected @"connected"
// Written by menzend only.
#define MenzenSettingConnectedApps @"connectedApps"
// Written by the pane only.
#define MenzenSettingConnectedAllowed @"connectedAllowed"
// Written by menzend only, which posts MenzenConnectedRequestNotification
// after.
#define MenzenSettingConnectedRequests @"connectedRequests"
#define MenzenConnectedRequestNotification "moe.waru.menzen.connected.request"
#define MenzenConnectedRequestIdentifierKey @"identifier"
#define MenzenConnectedRequestNameKey @"name"
#define MenzenConnectedRequestDateKey @"date"

#define MenzenConnectedAppNameKey @"name"
#define MenzenConnectedAppProcessKey @"process"
#define MenzenConnectedAppAskedKey @"asked"

// No more are kept, so a misbehaving client can't fill the settings.
static NSUInteger const MenzenConnectedAppLimit = 100;

@protocol MenzenConnectedService
- (void)registerWithIdentifier:(NSString *)identifier name:(NSString *)name;
- (void)setActivity:(NSDictionary<NSString *, id> *)activity;
@end

@protocol MenzenConnectedClient
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

static inline BOOL MenzenConnectedIdentifierIsValid(NSString *identifier) {
	if (![identifier isKindOfClass:NSString.class] || !identifier.length || identifier.length > 128) return NO;
	NSMutableCharacterSet *allowed = [NSMutableCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"];
	return [identifier rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

static inline NSString *MenzenConnectedName(NSString *name) {
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

static inline void MenzenConnectedSetAllowed(NSString *identifier, BOOL allowed) {
	NSMutableArray<NSString *> *identifiers = [MenzenConnectedAllowed() mutableCopy];
	[identifiers removeObject:identifier];
	if (allowed) [identifiers addObject:identifier];
	MenzenWriteSetting(MenzenSettingConnectedAllowed, identifiers);
	MenzenPostDarwinNotification(CFSTR(MenzenSettingsChangedNotification));
}
