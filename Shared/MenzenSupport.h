#import <Foundation/Foundation.h>

// What MenzenProviderCheck found, kept in the app's data container for the
// settings pane.

#define MenzenIssuesURL @"https://github.com/waruhachi/Menzen/issues"

#define MenzenSupportStatusPath @"Library/Application Support/moe.waru.menzen/status.plist"

// "<version> (<build>)".
#define MenzenSupportAppVersionKey @"appVersion"
#define MenzenSupportMenzenVersionKey @"menzenVersion"
#define MenzenSupportCheckedKey @"checked"
#define MenzenSupportMissingKey @"missing"
#define MenzenSupportMissingOptionalKey @"missingOptional"
#define MenzenSupportWorkedVersionKey @"workedVersion"
#define MenzenSupportWorkedKey @"worked"
#define MenzenSupportAlertedVersionKey @"alertedVersion"
// Set when menzend launched the app in the background to check it: some
// parts only load once the app is open, so missing ones aren't final.
#define MenzenSupportBackgroundKey @"background"

// Followed by the app's bundle ID.
#define MenzenSupportCheckedNotificationPrefix "moe.waru.menzen.checked."

NS_ASSUME_NONNULL_BEGIN

// Just the version when the build is the same or missing.
static inline NSString *MenzenSupportVersion(NSString *_Nullable version, NSString *_Nullable build) {
	if (![version isKindOfClass:NSString.class] || !version.length) version = @"?";
	return [build isKindOfClass:NSString.class] && build.length && ![build isEqualToString:version] ? [NSString stringWithFormat:@"%@ (%@)", version, build] : version;
}

static inline NSString *MenzenSupportDetails(NSString *app, NSString *version, NSString *bundleIdentifier, NSString *menzenVersion, NSString *systemVersion, NSArray<NSString *> *missing) {
	return [NSString stringWithFormat:@"App: %@ %@ (%@)\nMenzen: %@\niOS: %@\nMissing:\n%@", app, version, bundleIdentifier, menzenVersion, systemVersion, [missing componentsJoinedByString:@"\n"]];
}

static inline NSURL *MenzenSupportReportURL(NSString *app, NSString *version, NSString *details) {
	NSURLComponents *components = [NSURLComponents componentsWithString:[MenzenIssuesURL stringByAppendingString:@"/new"]];
	components.queryItems = @[
		[NSURLQueryItem queryItemWithName:@"title" value:[NSString stringWithFormat:@"%@ %@: missing parts", app, version]],
		[NSURLQueryItem queryItemWithName:@"body" value:[NSString stringWithFormat:@"```\n%@\n```\n", details]],
	];
	return components.URL ?: [NSURL URLWithString:MenzenIssuesURL];
}

// The repository's catalog workflow adds the requested app to the list.
static inline NSURL *MenzenAppRequestURL(NSString *bundleIdentifier) {
	NSURLComponents *components = [NSURLComponents componentsWithString:[MenzenIssuesURL stringByAppendingString:@"/new"]];
	components.queryItems = @[
		[NSURLQueryItem queryItemWithName:@"template" value:@"app-request.yml"],
		[NSURLQueryItem queryItemWithName:@"app" value:bundleIdentifier],
	];
	return components.URL ?: [NSURL URLWithString:MenzenIssuesURL];
}

NS_ASSUME_NONNULL_END
