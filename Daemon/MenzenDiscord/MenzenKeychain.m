#import <Security/Security.h>

#import "MenzenKeychain.h"

// Must match keychain-access-groups in entitlements.plist.
static NSString *const MenzenKeychainAccessGroup = @"moe.waru.menzend";
static NSString *const MenzenKeychainService = @"moe.waru.menzend";
static NSString *const MenzenKeychainAccount = @"discord";

static NSMutableDictionary *MenzenKeychainQuery(void) {
	return [@{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrAccessGroup: MenzenKeychainAccessGroup,
		(__bridge id)kSecAttrService: MenzenKeychainService,
		(__bridge id)kSecAttrAccount: MenzenKeychainAccount,
	} mutableCopy];
}

NSDictionary *MenzenKeychainLoadTokens(OSStatus *status) {
	NSMutableDictionary *query = MenzenKeychainQuery();
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

OSStatus MenzenKeychainSaveTokens(NSDictionary *tokens) {
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:tokens format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
	if (!data) return errSecParam;

	NSDictionary *attributes = @{
		(__bridge id)kSecValueData: data,
		(__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
	};
	OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)MenzenKeychainQuery(), (__bridge CFDictionaryRef)attributes);
	if (status != errSecItemNotFound) return status;

	NSMutableDictionary *item = MenzenKeychainQuery();
	[item addEntriesFromDictionary:attributes];
	return SecItemAdd((__bridge CFDictionaryRef)item, NULL);
}

OSStatus MenzenKeychainDeleteTokens(void) {
	OSStatus status = SecItemDelete((__bridge CFDictionaryRef)MenzenKeychainQuery());
	return status == errSecItemNotFound ? errSecSuccess : status;
}
