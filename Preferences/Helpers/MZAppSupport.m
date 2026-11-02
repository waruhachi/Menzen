#import "../../Shared/MZApps.h"
#import "../../Shared/MZProviders.h"
#import "MZAppSupport.h"

NSString *MZInstalledVersion(NSDictionary *provider) {
	return MZInstalledAppVersion(provider[MZProviderBundleIdentifierKey]) ?: @"?";
}

NSArray<NSString *> *MZMissingParts(NSDictionary *status) {
	NSArray *list = status[MZSupportMissingKey];
	if (![list isKindOfClass:NSArray.class]) return @[];
	return [list filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self isKindOfClass: %@", NSString.class]];
}

MZSupportState MZSupportStateFor(NSDictionary *provider, NSDictionary *status, NSSet<NSString *> *hooked) {
	if (![hooked containsObject:provider[MZProviderBundleIdentifierKey]]) return MZSupportStateNotHooked;
	if (!MZStatusIsCurrent(status, MZInstalledVersion(provider))) return MZSupportStateNotChecked;
	if (!MZMissingParts(status).count) return MZSupportStateWorks;
	return [status[MZSupportBackgroundKey] boolValue] ? MZSupportStateNotFullyChecked : MZSupportStateMayNotWork;
}
