#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// How well Menzen fits the installed version of a provider's app, from what
// its provider's check found (Shared/MZSupport.h).
typedef NS_ENUM(NSInteger, MZSupportState) {
	// No provider hooks it: Menzen shows only what it publishes.
	MZSupportStateNotHooked,
	// Its provider hasn't checked this version yet.
	MZSupportStateNotChecked,
	// Checked in the background, which found something missing that may
	// only load once the app is open.
	MZSupportStateNotFullyChecked,
	MZSupportStateWorks,
	// Its provider is missing something it needs in this version.
	MZSupportStateMayNotWork,
};

// provider is one of MZProviders(); hooked is MZHookedBundles().
FOUNDATION_EXPORT MZSupportState MZSupportStateFor(NSDictionary *provider, NSDictionary *_Nullable status, NSSet<NSString *> *hooked);
// The installed version as the status has it, "?" when it's unknown.
FOUNDATION_EXPORT NSString *MZInstalledVersion(NSDictionary *provider);
FOUNDATION_EXPORT NSArray<NSString *> *MZMissingParts(NSDictionary *_Nullable status);

NS_ASSUME_NONNULL_END
