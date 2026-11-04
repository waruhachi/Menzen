#import "../../Shared/MZLocalization/MZLocalization.h"
#import "MZDeviceSignIn.h"

typedef void (^MZDeviceSignInCompletion)(NSString *accessToken, NSString *refreshToken, NSTimeInterval expiresIn, NSString *error);

static NSString *const MZDeviceAuthorizeURL = @"https://discord.com/api/v10/oauth2/device/authorize";
static NSString *const MZTokenURL = @"https://discord.com/api/v10/oauth2/token";
static NSString *const MZDeviceCodeGrantType = @"urn:ietf:params:oauth:grant-type:device_code";
// Used when Discord leaves them out; it sent 5 and 300.
static NSTimeInterval const MZDefaultPollInterval = 5;
static NSTimeInterval const MZDefaultCodeLifetime = 5 * 60;
// RFC 8628: slow_down adds 5 seconds to the interval.
static NSTimeInterval const MZSlowDownStep = 5;
// Discord once answered a poll with invalid_request partway through a code's
// life and accepted the same code afterwards, so other errors are only final
// when they repeat.
static NSUInteger const MZMaxUnexpectedErrors = 3;

static NSString *MZFormEncoded(NSDictionary<NSString *, NSString *> *fields) {
	NSCharacterSet *unreserved = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
	NSMutableArray *pairs = [NSMutableArray array];
	[fields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
		[pairs addObject:[NSString stringWithFormat:@"%@=%@", [key stringByAddingPercentEncodingWithAllowedCharacters:unreserved], [value stringByAddingPercentEncodingWithAllowedCharacters:unreserved]]];
	}];
	return [pairs componentsJoinedByString:@"&"];
}

static NSString *MZJSONString(NSDictionary *json, NSString *key) {
	id value = json[key];
	return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

static NSTimeInterval MZJSONSeconds(NSDictionary *json, NSString *key, NSTimeInterval fallback) {
	id value = json[key];
	return [value isKindOfClass:NSNumber.class] && [value doubleValue] > 0 ? [value doubleValue] : fallback;
}

@implementation MZDeviceSignIn {
	NSString *_clientId;
	NSString *_scopes;
	NSURLSession *_session;
	// Bumped by every start, cancel and finish, so answers to an older code
	// are dropped.
	NSUInteger _generation;
	NSString *_deviceCode;
	NSTimeInterval _pollInterval;
	NSDate *_expiry;
	NSUInteger _unexpectedErrors;
	MZDeviceSignInCompletion _completion;
}

- (instancetype)initWithApplicationId:(uint64_t)applicationId scopes:(NSString *)scopes {
	if ((self = [super init])) {
		_clientId = [NSString stringWithFormat:@"%llu", applicationId];
		_scopes = [scopes copy];
		_session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
	}

	return self;
}

- (void)startWithCodeHandler:(void (^)(NSURL *, NSString *, NSString *))codeHandler completion:(MZDeviceSignInCompletion)completion {
	[self cancel];
	NSUInteger generation = _generation;
	__weak typeof(self) weakSelf = self;
	[self post:MZDeviceAuthorizeURL fields:@{@"client_id": _clientId, @"scope": _scopes} completion:^(NSInteger statusCode, NSDictionary *json) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf->_generation) return;

		NSString *deviceCode = MZJSONString(json, @"device_code");
		NSString *userCode = MZJSONString(json, @"user_code");
		NSString *page = MZJSONString(json, @"verification_uri_complete") ?: MZJSONString(json, @"verification_uri");
		NSURL *verificationURL = page ? [NSURL URLWithString:page] : nil;
		if (!deviceCode || !userCode || ![verificationURL.scheme isEqualToString:@"https"]) {
			codeHandler(nil, nil, MZLocalizedString(@"signin.error.discord_couldn_t_start_the_sign", @"Discord couldn't start the sign-in. Try again."));
			return;
		}
		strongSelf->_deviceCode = deviceCode;
		strongSelf->_pollInterval = MZJSONSeconds(json, @"interval", MZDefaultPollInterval);
		strongSelf->_expiry = [NSDate dateWithTimeIntervalSinceNow:MZJSONSeconds(json, @"expires_in", MZDefaultCodeLifetime)];
		strongSelf->_unexpectedErrors = 0;
		strongSelf->_completion = completion;
		codeHandler(verificationURL, userCode, nil);
		[strongSelf schedulePoll];
	}];
}

- (void)cancel {
	_generation++;
	_deviceCode = nil;
	_completion = nil;
}

- (void)schedulePoll {
	NSUInteger generation = _generation;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_pollInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		typeof(self) strongSelf = weakSelf;
		if (strongSelf && generation == strongSelf->_generation) [strongSelf poll];
	});
}

- (void)poll {
	if (_expiry.timeIntervalSinceNow < 0) {
		[self finishWithError:nil];
		return;
	}

	NSUInteger generation = _generation;
	__weak typeof(self) weakSelf = self;
	NSDictionary *fields = @{@"grant_type": MZDeviceCodeGrantType, @"device_code": _deviceCode, @"client_id": _clientId};
	[self post:MZTokenURL fields:fields completion:^(NSInteger statusCode, NSDictionary *json) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf->_generation) return;
		[strongSelf handleTokenResponse:json statusCode:statusCode];
	}];
}

- (void)handleTokenResponse:(NSDictionary *)json statusCode:(NSInteger)statusCode {
	NSString *accessToken = MZJSONString(json, @"access_token");
	NSString *refreshToken = MZJSONString(json, @"refresh_token");
	if (statusCode == 200 && accessToken && refreshToken) {
		MZDeviceSignInCompletion completion = _completion;
		[self cancel];
		completion(accessToken, refreshToken, MZJSONSeconds(json, @"expires_in", 0), nil);
		return;
	}

	NSString *error = MZJSONString(json, @"error");
	if ([error isEqualToString:@"authorization_pending"]) {
		_unexpectedErrors = 0;
		[self schedulePoll];
	} else if ([error isEqualToString:@"slow_down"]) {
		_pollInterval += MZSlowDownStep;
		[self schedulePoll];
	} else if ([error isEqualToString:@"expired_token"]) {
		[self finishWithError:nil];
	} else if ([error isEqualToString:@"access_denied"]) {
		[self finishWithError:MZLocalizedString(@"signin.error.the_sign_in_was_declined", @"The sign-in was declined.")];
	} else if (!statusCode || statusCode >= 500) {
		// No answer or a server hiccup; the code is still good until it expires.
		[self schedulePoll];
	} else if (++_unexpectedErrors < MZMaxUnexpectedErrors) {
		[self schedulePoll];
	} else {
		[self finishWithError:MZLocalizedString(@"signin.error.discord_couldn_t_complete_the_sign_2", @"Discord couldn't complete the sign-in.")];
	}
}

- (void)finishWithError:(NSString *)error {
	MZDeviceSignInCompletion completion = _completion;
	[self cancel];
	if (completion) completion(nil, nil, 0, error);
}

// completion runs on the main queue; json is nil when the answer wasn't a
// JSON object.
- (void)post:(NSString *)url fields:(NSDictionary<NSString *, NSString *> *)fields completion:(void (^)(NSInteger statusCode, NSDictionary *json))completion {
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
	request.HTTPMethod = @"POST";
	request.HTTPBody = [MZFormEncoded(fields) dataUsingEncoding:NSUTF8StringEncoding];
	[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
	[[_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		NSInteger statusCode = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
		id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
		dispatch_async(dispatch_get_main_queue(), ^{
			completion(statusCode, [json isKindOfClass:NSDictionary.class] ? json : nil);
		});
	}] resume];
}

@end
