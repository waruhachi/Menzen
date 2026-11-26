#import <Foundation/Foundation.h>

// Private, but present on iOS.
@interface NSXPCConnection (MenzenAuditToken)
@property (nonatomic, readonly) audit_token_t auditToken;
@end

typedef struct __SecTask *SecTaskRef;
extern SecTaskRef SecTaskCreateWithAuditToken(CFAllocatorRef allocator, audit_token_t token);
extern CFStringRef SecTaskCopySigningIdentifier(SecTaskRef task, CFErrorRef *error);
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error);
extern uint32_t SecTaskGetCodeSignStatus(SecTaskRef task);

// The audit token identifies the process that sent the connection, unlike its
// pid, which can be reused.
static inline NSString *MenzenSigningIdentifier(audit_token_t token) {
	SecTaskRef task = SecTaskCreateWithAuditToken(kCFAllocatorDefault, token);
	if (!task) return nil;

	NSString *identifier = CFBridgingRelease(SecTaskCopySigningIdentifier(task, NULL));
	CFRelease(task);

	return identifier;
}
