#import <roothide.h>

#import "../Shared/MenzenConnectedApps.h"
#import "../Shared/MenzenLocalization/MenzenLocalization.h"

// Connected Apps' requests (MenzenSettingConnectedRequests), shown as
// notifications from Menzen. Tapping one opens Connected Apps; touching and
// holding offers Allow and Deny.

@interface BBSectionIconVariant : NSObject
+ (instancetype)variantWithFormat:(NSInteger)format imageData:(NSData *)imageData;
@end

@interface BBSectionIcon : NSObject
- (void)addVariant:(BBSectionIconVariant *)variant;
@end

@interface BBAppearance : NSObject
+ (instancetype)appearanceWithTitle:(NSString *)title;
@end

@interface BBAction : NSObject
+ (instancetype)actionWithLaunchURL:(NSURL *)url;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) BBAppearance *appearance;
@end

@interface BBBulletin : NSObject
@property (nonatomic, copy) NSString *header;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy) NSString *sectionID;
@property (nonatomic, copy) NSString *bulletinID;
@property (nonatomic, copy) NSString *recordID;
@property (nonatomic, copy) NSString *publisherBulletinID;
@property (nonatomic, copy) NSString *threadID;
@property (nonatomic, retain) NSDate *date;
@property (nonatomic, copy) BBSectionIcon *icon;
@property (nonatomic, copy) BBAction *defaultAction;
@property (nonatomic, copy) NSDictionary *supplementaryActionsByLayout;
@property (nonatomic) BOOL clearable;
@property (nonatomic) BOOL showsMessagePreview;
@end

@interface BBResponse : NSObject
@property (nonatomic, copy) NSString *bulletinID;
@property (nonatomic, copy) NSString *actionID;
@end

@interface BBServer : NSObject
- (void)publishBulletin:(BBBulletin *)bulletin destinations:(NSUInteger)destinations;
- (void)_sendRemoveBulletin:(BBBulletin *)bulletin toFeeds:(NSUInteger)feeds shouldSync:(BOOL)shouldSync;
@end

// Shown under Settings, whose notifications are on by default, with Menzen's
// name and icon.
static NSString *const MenzenRequestSection = @"com.apple.Preferences";
static NSString *const MenzenRequestPrefix = @"moe.waru.menzen.connected.";
// Lock screen, Notification Center, banner and sound.
static NSUInteger const MenzenRequestDestinations = 15;
// Every feed, as BBServer removes its own bulletins.
static NSUInteger const MenzenRequestFeeds = 0x3dff;
static NSString *const MenzenRequestAllow = @"allow";
static NSString *const MenzenRequestDeny = @"deny";

static BBServer *MenzenBulletinServer;
static dispatch_queue_t MenzenBulletinQueue;
// The request shown for each app, used only on MenzenBulletinQueue. BBServer
// lets go of a bulletin once it's shown, so removing one needs it kept here.
static NSMutableDictionary<NSString *, BBBulletin *> *MenzenRequestBulletins;
// Requests from before this were shown already, or SpringBoard wasn't there
// to show them.
static NSDate *MenzenRequestsShownUntil;

// Shuffle moves tweak panes into its own Tweaks page and turns root=Menzen
// into root=Tweaks&path=Menzen, so there the page has to go in the root.
static NSURL *MenzenConnectedPageURL(void) {
	BOOL shuffle = [NSFileManager.defaultManager fileExistsAtPath:jbroot(@"/Library/MobileSubstrate/DynamicLibraries/shuffle.dylib")];
	return [NSURL URLWithString:shuffle ? @"prefs:root=Menzen/connected" : @"prefs:root=Menzen&path=connected"];
}

static BBSectionIcon *MenzenIcon(void) {
	static BBSectionIcon *icon;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSData *data = [NSData dataWithContentsOfFile:jbroot(@"/Library/PreferenceBundles/MenzenPreferences.bundle/icon@3x.png")];
		if (!data) return;
		icon = [%c(BBSectionIcon) new];
		[icon addVariant:[%c(BBSectionIconVariant) variantWithFormat:0 imageData:data]];
	});
	return icon;
}

static void MenzenRemoveRequestBulletin(NSString *identifier) {
	BBBulletin *bulletin = MenzenRequestBulletins[identifier];
	if (!bulletin) return;
	[MenzenRequestBulletins removeObjectForKey:identifier];
	[MenzenBulletinServer _sendRemoveBulletin:bulletin toFeeds:MenzenRequestFeeds shouldSync:NO];
}

static void MenzenWithdrawRequest(NSString *identifier) {
	dispatch_async(MenzenBulletinQueue, ^{
		MenzenRemoveRequestBulletin(identifier);
	});
}

static BBAction *MenzenRequestAction(NSString *identifier, NSString *title) {
	BBAction *action = [%c(BBAction) actionWithLaunchURL:nil];
	action.identifier = identifier;
	action.appearance = [%c(BBAppearance) appearanceWithTitle:title];
	return action;
}

static void MenzenShowRequest(NSString *identifier, NSString *name) {
	BBBulletin *bulletin = [%c(BBBulletin) new];
	NSString *recordID = [MenzenRequestPrefix stringByAppendingString:identifier];
	// A new ID each time, so a request shown again gets fresh actions; the
	// app's identifier comes before the slash.
	NSString *bulletinID = [NSString stringWithFormat:@"%@/%@", recordID, NSUUID.UUID.UUIDString];
	bulletin.sectionID = MenzenRequestSection;
	bulletin.bulletinID = bulletinID;
	bulletin.recordID = recordID;
	bulletin.publisherBulletinID = bulletinID;
	bulletin.threadID = @"moe.waru.menzen.connected";
	bulletin.header = @"Menzen";
	bulletin.title = [NSString stringWithFormat:MenzenLocalizedString(@"connected.x_wants_to_show_activity", @"%@ wants to show activity"), name];
	bulletin.message = MenzenLocalizedString(@"connected.touch_and_hold_to_allow", @"Touch and hold to allow it, or tap to open Connected Apps.");
	bulletin.date = NSDate.date;
	bulletin.icon = MenzenIcon();
	bulletin.clearable = YES;
	bulletin.showsMessagePreview = YES;
	bulletin.defaultAction = [%c(BBAction) actionWithLaunchURL:MenzenConnectedPageURL()];
	bulletin.supplementaryActionsByLayout = @{@0: @[
		MenzenRequestAction(MenzenRequestAllow, MenzenLocalizedString(@"connected.allow", @"Allow")),
		MenzenRequestAction(MenzenRequestDeny, MenzenLocalizedString(@"connected.deny", @"Deny")),
	]};
	dispatch_async(MenzenBulletinQueue, ^{
		MenzenRemoveRequestBulletin(identifier);
		MenzenRequestBulletins[identifier] = bulletin;
		[MenzenBulletinServer publishBulletin:bulletin destinations:MenzenRequestDestinations];
	});
}

static void MenzenRequestsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
	if (!MenzenBulletinServer) return;
	CFPreferencesAppSynchronize((__bridge CFStringRef)MenzenSettingsDomain);
	NSArray *requests = MenzenSettingValue(MenzenSettingConnectedRequests);
	if (![requests isKindOfClass:NSArray.class]) return;
	NSArray *allowed = MenzenConnectedAllowed();
	NSDate *latest = MenzenRequestsShownUntil;
	for (NSDictionary *request in requests) {
		if (![request isKindOfClass:NSDictionary.class]) continue;
		NSString *identifier = request[MenzenConnectedRequestIdentifierKey];
		NSString *appName = MenzenConnectedName(request[MenzenConnectedRequestNameKey]);
		NSDate *date = request[MenzenConnectedRequestDateKey];
		if (![date isKindOfClass:NSDate.class] || [date compare:MenzenRequestsShownUntil] != NSOrderedDescending) continue;
		latest = [date laterDate:latest];
		if (!MenzenConnectedIdentifierIsValid(identifier) || !appName || [allowed containsObject:identifier]) continue;
		MenzenShowRequest(identifier, appName);
	}

	MenzenRequestsShownUntil = latest;
}

// Allowed in the settings, so nothing left to ask.
static void MenzenSettingsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
	if (!MenzenBulletinServer) return;
	CFPreferencesAppSynchronize((__bridge CFStringRef)MenzenSettingsDomain);
	for (NSString *identifier in MenzenConnectedAllowed()) MenzenWithdrawRequest(identifier);
}

%hook BBServer

- (id)initWithQueue:(dispatch_queue_t)queue dataProviderManager:(id)dataProviderManager syncService:(id)syncService dismissalSyncCache:(id)dismissalSyncCache observerListener:(id)observerListener conduitListener:(id)conduitListener settingsListener:(id)settingsListener {
	self = %orig;
	if (self) {
		MenzenBulletinServer = self;
		MenzenBulletinQueue = queue;
	}

	return self;
}

// Action callblocks don't make it through to the notification, so Allow and
// Deny are handled here when their response comes back.
- (void)observer:(id)observer handleResponse:(BBResponse *)response withCompletion:(id)completion {
	NSString *bulletinID = response.bulletinID;
	NSString *actionID = response.actionID;
	if ([bulletinID hasPrefix:MenzenRequestPrefix] && ([actionID isEqualToString:MenzenRequestAllow] || [actionID isEqualToString:MenzenRequestDeny])) {
		NSString *identifier = [bulletinID substringFromIndex:MenzenRequestPrefix.length].pathComponents.firstObject;
		if (MenzenConnectedIdentifierIsValid(identifier)) {
			if ([actionID isEqualToString:MenzenRequestAllow]) MenzenConnectedSetAllowed(identifier, YES);
			MenzenWithdrawRequest(identifier);
		}
	}

	%orig;
}

%end

%ctor {
	MenzenRequestsShownUntil = NSDate.date;
	MenzenRequestBulletins = [NSMutableDictionary dictionary];
	CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
	CFNotificationCenterAddObserver(center, NULL, MenzenRequestsChanged, CFSTR(MenzenConnectedRequestNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	CFNotificationCenterAddObserver(center, NULL, MenzenSettingsChanged, CFSTR(MenzenSettingsChangedNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
