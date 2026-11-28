#import <Security/Security.h>

#import "MenzenKeychain.h"

// Must match keychain-access-groups in entitlements.plist.
static NSString *const MenzenKeychainAccessGroup = @"moe.waru.menzend";
static NSString *const MenzenKeychainService = @"moe.waru.menzend";
static NSString *const MenzenKeychainTokensAccount = @"discord";

static NSMutableDictionary *MenzenKeychainQuery(NSString *account) {
	return [@{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrAccessGroup: MenzenKeychainAccessGroup,
		(__bridge id)kSecAttrService: MenzenKeychainService,
		(__bridge id)kSecAttrAccount: account,
	} mutableCopy];
}

id MenzenKeychainLoadItem(NSString *account, OSStatus *status) {
	NSMutableDictionary *query = MenzenKeychainQuery(account);
	query[(__bridge id)kSecReturnData] = @YES;
	query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

	CFTypeRef result = NULL;
	OSStatus copyStatus = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	if (status) *status = copyStatus;
	NSData *data = CFBridgingRelease(result);
	if (copyStatus != errSecSuccess || ![data isKindOfClass:NSData.class]) return nil;

	return [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
}

OSStatus MenzenKeychainSaveItem(NSString *account, id value) {
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
	if (!data) return errSecParam;

	NSDictionary *attributes = @{
		(__bridge id)kSecValueData: data,
		(__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
	};

	OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)MenzenKeychainQuery(account), (__bridge CFDictionaryRef)attributes);
	if (status != errSecItemNotFound) return status;

	NSMutableDictionary *item = MenzenKeychainQuery(account);
	[item addEntriesFromDictionary:attributes];

	return SecItemAdd((__bridge CFDictionaryRef)item, NULL);
}

OSStatus MenzenKeychainDeleteItem(NSString *account) {
	OSStatus status = SecItemDelete((__bridge CFDictionaryRef)MenzenKeychainQuery(account));
	return status == errSecItemNotFound ? errSecSuccess : status;
}

NSDictionary *MenzenKeychainLoadTokens(OSStatus *status) {
	NSDictionary *tokens = MenzenKeychainLoadItem(MenzenKeychainTokensAccount, status);
	return [tokens isKindOfClass:NSDictionary.class] ? tokens : nil;
}

OSStatus MenzenKeychainSaveTokens(NSDictionary *tokens) {
	return MenzenKeychainSaveItem(MenzenKeychainTokensAccount, tokens);
}

OSStatus MenzenKeychainDeleteTokens(void) {
	return MenzenKeychainDeleteItem(MenzenKeychainTokensAccount);
}
