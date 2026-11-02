#import <Security/Security.h>

#import "MZKeychain.h"

// Must match keychain-access-groups in entitlements.plist.
static NSString *const MZKeychainAccessGroup = @"moe.waru.menzend";
static NSString *const MZKeychainService = @"moe.waru.menzend";
static NSString *const MZKeychainAccount = @"discord";

static NSMutableDictionary *MZKeychainQuery(void) {
	return [@{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrAccessGroup: MZKeychainAccessGroup,
		(__bridge id)kSecAttrService: MZKeychainService,
		(__bridge id)kSecAttrAccount: MZKeychainAccount,
	} mutableCopy];
}

NSDictionary *MZKeychainLoadTokens(OSStatus *status) {
	NSMutableDictionary *query = MZKeychainQuery();
	query[(__bridge id)kSecReturnData] = @YES;
	query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

	CFTypeRef result = NULL;
	OSStatus copyStatus = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	if (status) *status = copyStatus;
	NSData *data = CFBridgingRelease(result);
	if (copyStatus != errSecSuccess || ![data isKindOfClass:NSData.class]) return nil;

	NSDictionary *tokens = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
	return [tokens isKindOfClass:NSDictionary.class] ? tokens : nil;
}

OSStatus MZKeychainSaveTokens(NSDictionary *tokens) {
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:tokens format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
	if (!data) return errSecParam;

	NSDictionary *attributes = @{
		(__bridge id)kSecValueData: data,
		(__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
	};
	OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)MZKeychainQuery(), (__bridge CFDictionaryRef)attributes);
	if (status != errSecItemNotFound) return status;

	NSMutableDictionary *item = MZKeychainQuery();
	[item addEntriesFromDictionary:attributes];
	return SecItemAdd((__bridge CFDictionaryRef)item, NULL);
}

OSStatus MZKeychainDeleteTokens(void) {
	OSStatus status = SecItemDelete((__bridge CFDictionaryRef)MZKeychainQuery());
	return status == errSecItemNotFound ? errSecSuccess : status;
}
