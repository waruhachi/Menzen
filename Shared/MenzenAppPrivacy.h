#import <Foundation/Foundation.h>

#import "MenzenApps.h"
#import "MenzenProviders.h"
#import "MenzenSettings.h"

// The app the Control Center module switches Privacy Mode for.
#define MenzenSettingPrivacyModuleApp @"privacyModuleApp"

static inline NSArray<NSArray<NSString *> *> *MenzenInstalledProviderApps(void) {
	NSMutableArray<NSArray<NSString *> *> *apps = [NSMutableArray array];
	LSApplicationWorkspace *workspace = MenzenWorkspace();

	for (NSDictionary *provider in MenzenProviders()) {
		NSString *bundleIdentifier = provider[MenzenProviderBundleIdentifierKey];
		if ([workspace applicationIsInstalled:bundleIdentifier]) [apps addObject:@[bundleIdentifier, provider[MenzenProviderNameKey]]];
	}

	[apps sortUsingComparator:^NSComparisonResult(NSArray<NSString *> *a, NSArray<NSString *> *b) {
		return [a[1] localizedCaseInsensitiveCompare:b[1]];
	}];

	return apps;
}

// The first installed app until one is picked, or when the picked one is
// removed; nil when none is installed.
static inline NSArray<NSString *> *MenzenPrivacyModuleChoice(void) {
	NSArray<NSArray<NSString *> *> *apps = MenzenInstalledProviderApps();
	NSString *picked = MenzenSettingString(MenzenSettingPrivacyModuleApp, nil);

	for (NSArray<NSString *> *app in apps) {
		if ([app[0] isEqualToString:picked]) return app;
	}

	return apps.firstObject;
}

static inline NSString *MenzenPrivacyModuleApp(void) {
	return MenzenPrivacyModuleChoice().firstObject;
}

static inline NSString *MenzenPrivacyModuleKey(void) {
	NSString *app = MenzenPrivacyModuleApp();
	return app ? [MenzenSettingPrivatePrefix stringByAppendingString:app] : MenzenSettingPrivacy;
}
