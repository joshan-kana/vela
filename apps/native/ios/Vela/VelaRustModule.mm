#import <Foundation/Foundation.h>
#import <React/RCTBridgeModule.h>
#import <Security/Security.h>

#import "../../../../crates/vela-ffi/include/vela_ffi.h"

@interface VelaRustModule : NSObject <RCTBridgeModule>
@end

static NSString *VelaCachePath(void);

static NSString *const VelaAccountService = @"io.github.joshankana.vela.youtrack";
static NSString *const VelaPendingOAuthService = @"io.github.joshankana.vela.oauth.pending";
static NSString *const VelaPermanentTokenAuthKind = @"permanent_token";
static NSString *const VelaOAuthPkceAuthKind = @"oauth_pkce";
static NSString *const VelaOAuthScheme = @"io.github.joshankana.vela";
static NSString *const VelaOAuthCallbackPath = @"/oauth/callback";
static NSString *const VelaOAuthRedirectUri = @"io.github.joshankana.vela:/oauth/callback";
static NSString *const VelaDefaultOAuthScope = @"YouTrack";
static NSTimeInterval const VelaTokenRefreshSkewSeconds = 60.0;

static NSError *VelaKeychainError(OSStatus status)
{
  NSString *message = (__bridge_transfer NSString *)SecCopyErrorMessageString(status, NULL);
  return [NSError errorWithDomain:@"VelaKeychain"
                             code:status
                         userInfo:@{NSLocalizedDescriptionKey: message ?: @"Keychain error"}];
}

static NSError *VelaError(NSString *message)
{
  return [NSError errorWithDomain:@"Vela"
                             code:-1
                         userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSDictionary *VelaDecodeRustResponse(char *result, NSError **error)
{
  if (result == NULL) {
    if (error != NULL) {
      *error = VelaError(@"Rust bridge returned no response");
    }
    return nil;
  }

  NSData *data = [NSData dataWithBytes:result length:strlen(result)];
  vela_string_free(result);

  NSError *jsonError = nil;
  NSDictionary *response = [NSJSONSerialization JSONObjectWithData:data
                                                           options:0
                                                             error:&jsonError];
  if (![response isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = jsonError ?: VelaError(@"Rust bridge returned invalid JSON");
    }
    return nil;
  }

  if (![response[@"status"] isEqualToString:@"ok"]) {
    NSString *message = response[@"message"];
    if (error != NULL) {
      *error = VelaError([message isKindOfClass:[NSString class]]
                           ? message
                           : @"Rust bridge request failed");
    }
    return nil;
  }

  NSDictionary *payload = response[@"data"];
  if (![payload isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = VelaError(@"Rust bridge returned invalid data");
    }
    return nil;
  }

  return payload;
}

static BOOL VelaSaveKeychainDictionary(NSString *service,
                                       NSString *accountId,
                                       NSDictionary *secret,
                                       NSError **error)
{
  NSError *jsonError = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:secret options:0 error:&jsonError];
  if (data == nil) {
    if (error != NULL) {
      *error = jsonError;
    }
    return NO;
  }

  NSDictionary *query = @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService: service,
    (__bridge id)kSecAttrAccount: accountId,
  };
  NSDictionary *attributes = @{
    (__bridge id)kSecValueData: data,
    (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
  };

  OSStatus status = SecItemUpdate(
    (__bridge CFDictionaryRef)query,
    (__bridge CFDictionaryRef)attributes);
  if (status == errSecItemNotFound) {
    NSMutableDictionary *add = [query mutableCopy];
    [add addEntriesFromDictionary:attributes];
    status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
  }

  if (status != errSecSuccess) {
    if (error != NULL) {
      *error = VelaKeychainError(status);
    }
    return NO;
  }

  return YES;
}

static NSDictionary *VelaLoadKeychainDictionary(NSString *service,
                                                NSString *accountId,
                                                NSError **error)
{
  NSDictionary *query = @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService: service,
    (__bridge id)kSecAttrAccount: accountId,
    (__bridge id)kSecReturnData: @YES,
    (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
  };

  CFTypeRef rawResult = NULL;
  OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &rawResult);
  if (status != errSecSuccess) {
    if (error != NULL) {
      *error = VelaKeychainError(status);
    }
    return nil;
  }

  NSData *data = CFBridgingRelease(rawResult);
  NSError *jsonError = nil;
  NSDictionary *secret = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
  if (![secret isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = jsonError ?: VelaError(@"Stored YouTrack credentials are invalid");
    }
    return nil;
  }

  return secret;
}

static BOOL VelaDeleteKeychainItem(NSString *service,
                                   NSString *accountId,
                                   NSError **error)
{
  NSDictionary *query = @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService: service,
    (__bridge id)kSecAttrAccount: accountId,
  };

  OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
  if (status == errSecSuccess || status == errSecItemNotFound) {
    return YES;
  }

  if (error != NULL) {
    *error = VelaKeychainError(status);
  }
  return NO;
}

static NSArray<NSDictionary *> *VelaAccountEntries(NSError **error)
{
  NSDictionary *query = @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService: VelaAccountService,
    (__bridge id)kSecReturnAttributes: @YES,
    (__bridge id)kSecReturnData: @YES,
    (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
  };

  CFTypeRef rawResult = NULL;
  OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &rawResult);
  if (status == errSecItemNotFound) {
    return @[];
  }
  if (status != errSecSuccess) {
    if (error != NULL) {
      *error = VelaKeychainError(status);
    }
    return nil;
  }

  id result = CFBridgingRelease(rawResult);
  NSArray *items = [result isKindOfClass:[NSArray class]] ? result : @[result];
  NSMutableArray<NSDictionary *> *entries = [NSMutableArray arrayWithCapacity:items.count];

  for (NSDictionary *item in items) {
    NSString *accountId = item[(__bridge id)kSecAttrAccount];
    NSData *data = item[(__bridge id)kSecValueData];
    if (![accountId isKindOfClass:[NSString class]] || ![data isKindOfClass:[NSData class]]) {
      if (error != NULL) {
        *error = [NSError errorWithDomain:@"VelaKeychain"
                                     code:-1
                                 userInfo:@{NSLocalizedDescriptionKey: @"Stored YouTrack credentials are invalid"}];
      }
      return nil;
    }

    NSError *jsonError = nil;
    NSDictionary *secret = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (![secret isKindOfClass:[NSDictionary class]]) {
      if (error != NULL) {
        *error = jsonError ?: [NSError errorWithDomain:@"VelaKeychain"
                                                  code:-1
                                              userInfo:@{NSLocalizedDescriptionKey: @"Stored YouTrack credentials are invalid"}];
      }
      return nil;
    }

    NSMutableDictionary *entry = [secret mutableCopy];
    entry[@"id"] = accountId;
    [entries addObject:entry];
  }

  return entries;
}

static NSDictionary *VelaAccountMetadata(NSDictionary *entry)
{
  return @{
    @"id": entry[@"id"],
    @"service_url": entry[@"service_url"],
    @"auth_kind": entry[@"auth_kind"],
  };
}

static NSString *VelaExistingAccountId(NSString *serviceUrl, NSError **error)
{
  NSArray<NSDictionary *> *entries = VelaAccountEntries(error);
  if (entries == nil) {
    return nil;
  }

  for (NSDictionary *entry in entries) {
    if ([entry[@"service_url"] isEqualToString:serviceUrl]) {
      return entry[@"id"];
    }
  }

  return nil;
}

static NSString *VelaOptionalString(NSDictionary *dictionary, NSString *key)
{
  id value = dictionary[key];
  return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSNumber *VelaOptionalNumber(NSDictionary *dictionary, NSString *key)
{
  id value = dictionary[key];
  return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

static NSDictionary *VelaSaveOAuthAccount(NSString *serviceUrl,
                                          NSString *hubUrl,
                                          NSString *clientId,
                                          NSString *scope,
                                          NSDictionary *tokens,
                                          NSError **error)
{
  NSString *normalizedUrl =
    [serviceUrl stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSString *accountId = VelaExistingAccountId(normalizedUrl, error);
  if (accountId == nil && error != NULL && *error != nil) {
    return nil;
  }
  if (accountId == nil) {
    accountId = [NSUUID UUID].UUIDString.lowercaseString;
  }

  NSString *accessToken = VelaOptionalString(tokens, @"access_token");
  if (accessToken == nil) {
    if (error != NULL) {
      *error = VelaError(@"OAuth token response is missing an access token");
    }
    return nil;
  }

  NSMutableDictionary *secret = [@{
    @"service_url": normalizedUrl,
    @"hub_url": hubUrl,
    @"client_id": clientId,
    @"scope": scope,
    @"access_token": accessToken,
    @"auth_kind": VelaOAuthPkceAuthKind,
  } mutableCopy];

  NSString *refreshToken = VelaOptionalString(tokens, @"refresh_token");
  if (refreshToken != nil) {
    secret[@"refresh_token"] = refreshToken;
  }

  NSNumber *expiresIn = VelaOptionalNumber(tokens, @"expires_in");
  if (expiresIn != nil) {
    NSTimeInterval expiresAt =
      ([[NSDate date] timeIntervalSince1970] + expiresIn.doubleValue) * 1000.0;
    secret[@"expires_at_ms"] = @(expiresAt);
  }

  if (!VelaSaveKeychainDictionary(VelaAccountService, accountId, secret, error)) {
    return nil;
  }

  return @{
    @"id": accountId,
    @"service_url": normalizedUrl,
    @"auth_kind": VelaOAuthPkceAuthKind,
  };
}

static NSDictionary *VelaSavePermanentToken(NSString *serviceUrl,
                                            NSString *bearerToken,
                                            NSError **error)
{
  NSString *normalizedUrl =
    [serviceUrl stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

  NSString *accountId = VelaExistingAccountId(normalizedUrl, error);
  if (accountId == nil && error != NULL && *error != nil) {
    return nil;
  }
  if (accountId == nil) {
    accountId = [NSUUID UUID].UUIDString.lowercaseString;
  }

  NSDictionary *secret = @{
    @"service_url": normalizedUrl,
    @"bearer_token": bearerToken,
    @"auth_kind": VelaPermanentTokenAuthKind,
  };

  if (!VelaSaveKeychainDictionary(VelaAccountService, accountId, secret, error)) {
    return nil;
  }

  return @{
    @"id": accountId,
    @"service_url": normalizedUrl,
    @"auth_kind": VelaPermanentTokenAuthKind,
  };
}

static NSString *VelaLoadAccountToken(NSString *accountId, NSError **error)
{
  NSDictionary *secret = VelaLoadKeychainDictionary(VelaAccountService, accountId, error);
  if (secret == nil) {
    return nil;
  }

  NSString *authKind = VelaOptionalString(secret, @"auth_kind");
  if ([authKind isEqualToString:VelaPermanentTokenAuthKind]) {
    NSString *bearerToken = VelaOptionalString(secret, @"bearer_token");
    if (bearerToken == nil && error != NULL) {
      *error = VelaError(@"Stored permanent token is invalid");
    }
    return bearerToken;
  }

  if (![authKind isEqualToString:VelaOAuthPkceAuthKind]) {
    if (error != NULL) {
      *error = VelaError(@"Stored YouTrack authentication method is unsupported");
    }
    return nil;
  }

  NSString *accessToken = VelaOptionalString(secret, @"access_token");
  if (accessToken == nil) {
    if (error != NULL) {
      *error = VelaError(@"Stored OAuth account has no access token");
    }
    return nil;
  }

  NSNumber *expiresAtMs = VelaOptionalNumber(secret, @"expires_at_ms");
  NSTimeInterval nowMs = [[NSDate date] timeIntervalSince1970] * 1000.0;
  if (expiresAtMs == nil ||
      expiresAtMs.doubleValue > nowMs + (VelaTokenRefreshSkewSeconds * 1000.0)) {
    return accessToken;
  }

  NSString *refreshToken = VelaOptionalString(secret, @"refresh_token");
  NSString *hubUrl = VelaOptionalString(secret, @"hub_url");
  NSString *clientId = VelaOptionalString(secret, @"client_id");
  NSString *scope = VelaOptionalString(secret, @"scope");
  if (refreshToken == nil || hubUrl == nil || clientId == nil || scope == nil) {
    if (error != NULL) {
      *error = VelaError(@"OAuth access token expired and cannot be refreshed");
    }
    return nil;
  }

  NSDictionary *tokens = VelaDecodeRustResponse(
    vela_refresh_oauth_token_json(
      hubUrl.UTF8String,
      clientId.UTF8String,
      scope.UTF8String,
      refreshToken.UTF8String),
    error);
  if (tokens == nil) {
    return nil;
  }

  NSString *nextAccessToken = VelaOptionalString(tokens, @"access_token");
  if (nextAccessToken == nil) {
    if (error != NULL) {
      *error = VelaError(@"OAuth refresh response is missing an access token");
    }
    return nil;
  }

  NSMutableDictionary *updated = [secret mutableCopy];
  updated[@"access_token"] = nextAccessToken;

  NSString *nextRefreshToken = VelaOptionalString(tokens, @"refresh_token");
  if (nextRefreshToken != nil) {
    updated[@"refresh_token"] = nextRefreshToken;
  }

  NSNumber *expiresIn = VelaOptionalNumber(tokens, @"expires_in");
  if (expiresIn != nil) {
    NSTimeInterval nextExpiresAt =
      ([[NSDate date] timeIntervalSince1970] + expiresIn.doubleValue) * 1000.0;
    updated[@"expires_at_ms"] = @(nextExpiresAt);
  } else {
    [updated removeObjectForKey:@"expires_at_ms"];
  }

  if (!VelaSaveKeychainDictionary(VelaAccountService, accountId, updated, error)) {
    return nil;
  }

  return nextAccessToken;
}

static BOOL VelaDeleteAccount(NSString *accountId, NSError **error)
{
  return VelaDeleteKeychainItem(VelaAccountService, accountId, error);
}

static NSString *VelaQueryValue(NSURLComponents *components, NSString *name)
{
  for (NSURLQueryItem *item in components.queryItems) {
    if ([item.name isEqualToString:name]) {
      return item.value;
    }
  }
  return nil;
}

static void ResolveRustResponse(char *result,
                                RCTPromiseResolveBlock resolve,
                                RCTPromiseRejectBlock reject)
{
  if (result == NULL) {
    reject(@"vela_rust", @"Rust bridge returned no response", nil);
    return;
  }

  NSData *data = [NSData dataWithBytes:result length:strlen(result)];
  vela_string_free(result);

  NSError *jsonError = nil;
  NSDictionary *response = [NSJSONSerialization JSONObjectWithData:data
                                                           options:0
                                                             error:&jsonError];

  if (jsonError != nil || ![response isKindOfClass:[NSDictionary class]]) {
    reject(@"vela_rust", @"Rust bridge returned invalid JSON", jsonError);
    return;
  }

  if ([response[@"status"] isEqualToString:@"ok"]) {
    resolve(response[@"data"]);
    return;
  }

  NSString *message = response[@"message"];
  reject(@"youtrack_connection",
         [message isKindOfClass:[NSString class]] ? message : @"Connection failed",
         nil);
}

@implementation VelaRustModule

RCT_EXPORT_MODULE(VelaRust)

RCT_REMAP_METHOD(listAccounts,
                 listAccountsWithResolver : (RCTPromiseResolveBlock)resolve
                   rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *error = nil;
    NSArray<NSDictionary *> *entries = VelaAccountEntries(&error);
    if (entries == nil) {
      reject(@"vela_accounts", error.localizedDescription, error);
      return;
    }

    NSMutableArray<NSDictionary *> *accounts = [NSMutableArray arrayWithCapacity:entries.count];
    for (NSDictionary *entry in entries) {
      [accounts addObject:VelaAccountMetadata(entry)];
    }
    [accounts sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
      return [left[@"service_url"] localizedCaseInsensitiveCompare:right[@"service_url"]];
    }];

    resolve(accounts);
  });
}

RCT_REMAP_METHOD(savePermanentTokenAccount,
                 savePermanentTokenAccountWithServiceUrl : (NSString *)serviceUrl
                   bearerToken : (NSString *)bearerToken
                     resolver : (RCTPromiseResolveBlock)resolve
                       rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *error = nil;
    NSDictionary *account = VelaSavePermanentToken(serviceUrl, bearerToken, &error);
    if (account == nil) {
      reject(@"vela_accounts", error.localizedDescription, error);
      return;
    }
    resolve(account);
  });
}

RCT_REMAP_METHOD(deleteAccount,
                 deleteAccountWithId : (NSString *)accountId
                   resolver : (RCTPromiseResolveBlock)resolve
                     rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *error = nil;
    NSDictionary *account = nil;
    for (NSDictionary *entry in VelaAccountEntries(&error)) {
      if ([entry[@"id"] isEqualToString:accountId]) {
        account = entry;
        break;
      }
    }
    if (error != nil) {
      reject(@"vela_accounts", error.localizedDescription, error);
      return;
    }
    if (account != nil) {
      NSString *scope = [NSString stringWithFormat:@"%@::%@", account[@"service_url"], accountId];
      char *response = vela_clear_cache_account_json(VelaCachePath().UTF8String, scope.UTF8String);
      NSError *cacheError = nil;
      NSDictionary *cleared = VelaDecodeRustResponse(response, &cacheError);
      if (cleared == nil) {
        reject(@"vela_accounts", cacheError.localizedDescription, cacheError);
        return;
      }
    }
    if (!VelaDeleteAccount(accountId, &error)) {
      reject(@"vela_accounts", error.localizedDescription, error);
      return;
    }
    resolve(nil);
  });
}

RCT_REMAP_METHOD(loadAccountToken,
                 loadAccountTokenWithId : (NSString *)accountId
                   resolver : (RCTPromiseResolveBlock)resolve
                     rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *error = nil;
    NSString *token = VelaLoadAccountToken(accountId, &error);
    if (token == nil) {
      reject(@"vela_accounts", error.localizedDescription, error);
      return;
    }
    resolve(token);
  });
}

RCT_REMAP_METHOD(beginOAuth,
                 beginOAuthWithServiceUrl : (NSString *)serviceUrl
                   clientId : (NSString *)clientId
                     hubUrl : (NSString *)hubUrl
                       scope : (NSString *)scope
                         resolver : (RCTPromiseResolveBlock)resolve
                           rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSString *normalizedServiceUrl =
      [serviceUrl stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *normalizedClientId =
      [clientId stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *normalizedHubUrl =
      [hubUrl isKindOfClass:[NSString class]]
        ? [hubUrl stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        : @"";
    NSString *normalizedScope =
      [scope isKindOfClass:[NSString class]]
        ? [scope stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        : @"";
    if (normalizedScope.length == 0) {
      normalizedScope = VelaDefaultOAuthScope;
    }

    NSError *error = nil;
    NSDictionary *authorization = VelaDecodeRustResponse(
      vela_begin_oauth_json(
        normalizedServiceUrl.UTF8String,
        normalizedHubUrl.length > 0 ? normalizedHubUrl.UTF8String : NULL,
        normalizedClientId.UTF8String,
        VelaOAuthRedirectUri.UTF8String,
        normalizedScope.UTF8String),
      &error);
    if (authorization == nil) {
      reject(@"vela_oauth", error.localizedDescription, error);
      return;
    }

    NSString *state = VelaOptionalString(authorization, @"state");
    NSString *authorizationUrl = VelaOptionalString(authorization, @"authorization_url");
    if (state == nil || authorizationUrl == nil) {
      NSError *invalid = VelaError(@"OAuth authorization response is invalid");
      reject(@"vela_oauth", invalid.localizedDescription, invalid);
      return;
    }

    NSMutableDictionary *pending = [authorization mutableCopy];
    pending[@"service_url"] = normalizedServiceUrl;
    if (!VelaSaveKeychainDictionary(VelaPendingOAuthService, state, pending, &error)) {
      reject(@"vela_oauth", error.localizedDescription, error);
      return;
    }

    resolve(@{
      @"authorization_url": authorizationUrl,
      @"state": state,
    });
  });
}

RCT_REMAP_METHOD(completeOAuth,
                 completeOAuthWithCallbackUrl : (NSString *)callbackUrl
                   resolver : (RCTPromiseResolveBlock)resolve
                     rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSURLComponents *components = [NSURLComponents componentsWithString:callbackUrl];
    if (components == nil ||
        ![components.scheme isEqualToString:VelaOAuthScheme] ||
        ![components.path isEqualToString:VelaOAuthCallbackPath]) {
      NSError *error = VelaError(@"Unexpected OAuth callback URL");
      reject(@"vela_oauth", error.localizedDescription, error);
      return;
    }

    NSString *state = VelaQueryValue(components, @"state");
    NSString *oauthError = VelaQueryValue(components, @"error");
    if (oauthError != nil) {
      if (state != nil) {
        VelaDeleteKeychainItem(VelaPendingOAuthService, state, NULL);
      }
      NSString *description = VelaQueryValue(components, @"error_description");
      NSString *message = description != nil
                            ? [NSString stringWithFormat:@"%@: %@", oauthError, description]
                            : oauthError;
      NSError *error = VelaError(message);
      reject(@"vela_oauth", error.localizedDescription, error);
      return;
    }

    NSString *code = VelaQueryValue(components, @"code");
    if (state == nil || code == nil) {
      NSError *error = VelaError(@"OAuth callback is missing code or state");
      reject(@"vela_oauth", error.localizedDescription, error);
      return;
    }

    NSError *error = nil;
    NSDictionary *pending =
      VelaLoadKeychainDictionary(VelaPendingOAuthService, state, &error);
    if (pending == nil) {
      reject(@"vela_oauth", error.localizedDescription, error);
      return;
    }

    NSString *hubUrl = VelaOptionalString(pending, @"hub_url");
    NSString *clientId = VelaOptionalString(pending, @"client_id");
    NSString *redirectUri = VelaOptionalString(pending, @"redirect_uri");
    NSString *codeVerifier = VelaOptionalString(pending, @"code_verifier");
    NSString *scope = VelaOptionalString(pending, @"scope");
    NSString *serviceUrl = VelaOptionalString(pending, @"service_url");
    if (hubUrl == nil || clientId == nil || redirectUri == nil ||
        codeVerifier == nil || scope == nil || serviceUrl == nil) {
      NSError *invalid = VelaError(@"Stored OAuth authorization request is invalid");
      reject(@"vela_oauth", invalid.localizedDescription, invalid);
      return;
    }

    NSDictionary *tokens = VelaDecodeRustResponse(
      vela_exchange_oauth_code_json(
        hubUrl.UTF8String,
        clientId.UTF8String,
        redirectUri.UTF8String,
        codeVerifier.UTF8String,
        code.UTF8String),
      &error);
    if (tokens == nil) {
      reject(@"vela_oauth", error.localizedDescription, error);
      return;
    }

    NSDictionary *account = VelaSaveOAuthAccount(
      serviceUrl,
      hubUrl,
      clientId,
      scope,
      tokens,
      &error);
    if (account == nil) {
      reject(@"vela_oauth", error.localizedDescription, error);
      return;
    }

    VelaDeleteKeychainItem(VelaPendingOAuthService, state, NULL);
    resolve(account);
  });
}

RCT_REMAP_METHOD(discover,
                 discoverWithServiceUrl : (NSString *)serviceUrl
                   bearerToken : (NSString *)bearerToken
                     resolver : (RCTPromiseResolveBlock)resolve
                       rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    char *result = vela_discover_json(serviceUrlUtf8, tokenUtf8);
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(loadProjectSchema,
                 loadProjectSchemaWithServiceUrl : (NSString *)serviceUrl
                   bearerToken : (NSString *)bearerToken
                     projectId : (NSString *)projectId
                       resolver : (RCTPromiseResolveBlock)resolve
                         rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    char *result = vela_project_schema_json(serviceUrlUtf8, tokenUtf8, projectId.UTF8String);
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(loadUsers,
                 loadUsersWithServiceUrl : (NSString *)serviceUrl
                   bearerToken : (NSString *)bearerToken
                     skip : (nonnull NSNumber *)skip
                       top : (nonnull NSNumber *)top
                         resolver : (RCTPromiseResolveBlock)resolve
                           rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    NSUInteger skipValue = MAX((NSInteger)0, skip.integerValue);
    NSUInteger topValue = MAX((NSInteger)1, top.integerValue);
    char *result = vela_users_json(serviceUrlUtf8, tokenUtf8, skipValue, topValue);
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(loadAgileBoards,
                 loadAgileBoardsWithServiceUrl : (NSString *)serviceUrl
                   bearerToken : (NSString *)bearerToken
                     skip : (nonnull NSNumber *)skip
                       top : (nonnull NSNumber *)top
                         resolver : (RCTPromiseResolveBlock)resolve
                           rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    NSUInteger skipValue = MAX((NSInteger)0, skip.integerValue);
    NSUInteger topValue = MAX((NSInteger)1, top.integerValue);
    char *result = vela_agile_boards_json(serviceUrlUtf8, tokenUtf8, skipValue, topValue);
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(loadSavedQueries,
                 loadSavedQueriesWithServiceUrl : (NSString *)serviceUrl
                   bearerToken : (NSString *)bearerToken
                     skip : (nonnull NSNumber *)skip
                       top : (nonnull NSNumber *)top
                         resolver : (RCTPromiseResolveBlock)resolve
                           rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    NSUInteger skipValue = MAX((NSInteger)0, skip.integerValue);
    NSUInteger topValue = MAX((NSInteger)1, top.integerValue);
    char *result = vela_saved_queries_json(serviceUrlUtf8, tokenUtf8, skipValue, topValue);
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(executeIssueAction,
                 executeIssueActionWithServiceUrl : (NSString *)serviceUrl
                   bearerToken : (NSString *)bearerToken
                     action : (NSDictionary *)action
                       resolver : (RCTPromiseResolveBlock)resolve
                         rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *jsonError = nil;
    NSData *actionData = [NSJSONSerialization dataWithJSONObject:action options:0 error:&jsonError];
    if (actionData == nil) {
      reject(@"vela_action", @"Unable to serialize issue action", jsonError);
      return;
    }

    NSString *actionJson = [[NSString alloc] initWithData:actionData encoding:NSUTF8StringEncoding];
    if (actionJson == nil) {
      reject(@"vela_action", @"Unable to encode issue action", nil);
      return;
    }

    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    char *result = vela_execute_issue_action_json(
      serviceUrlUtf8,
      tokenUtf8,
      actionJson.UTF8String);
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(loadIssueDetails,
                 loadIssueDetailsWithServiceUrl : (NSString *)serviceUrl
                   bearerToken : (NSString *)bearerToken
                     issueId : (NSString *)issueId
                       resolver : (RCTPromiseResolveBlock)resolve
                         rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    char *result = vela_issue_details_json(serviceUrlUtf8, tokenUtf8, issueId.UTF8String);
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(loadIssueLinks,
                 loadIssueLinksWithServiceUrl : (NSString *)serviceUrl
                   bearerToken : (NSString *)bearerToken
                     issueId : (NSString *)issueId
                       resolver : (RCTPromiseResolveBlock)resolve
                         rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    char *result = vela_issue_links_json(serviceUrlUtf8, tokenUtf8, issueId.UTF8String);
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(setIssueSummary,
                 setIssueSummaryWithServiceUrl : (NSString *)serviceUrl
                   bearerToken : (NSString *)bearerToken
                     issueId : (NSString *)issueId
                       summary : (NSString *)summary
                         resolver : (RCTPromiseResolveBlock)resolve
                           rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    char *result = vela_set_issue_summary_json(
      serviceUrlUtf8,
      tokenUtf8,
      issueId.UTF8String,
      summary.UTF8String);
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(setIssueDescription,
                 setIssueDescriptionWithServiceUrl : (NSString *)serviceUrl
                   bearerToken : (NSString *)bearerToken
                     issueId : (NSString *)issueId
                       description : (id)description
                         resolver : (RCTPromiseResolveBlock)resolve
                           rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    const char *descriptionUtf8 = NULL;

    if ([description isKindOfClass:[NSString class]]) {
      descriptionUtf8 = [(NSString *)description UTF8String];
    }

    char *result = vela_set_issue_description_json(
      serviceUrlUtf8,
      tokenUtf8,
      issueId.UTF8String,
      descriptionUtf8);
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(setCustomFieldValue,
                 setCustomFieldValueWithServiceUrl : (NSString *)serviceUrl
                   bearerToken : (NSString *)bearerToken
                     issueId : (NSString *)issueId
                       fieldId : (NSString *)fieldId
                         fieldType : (NSString *)fieldType
                           value : (id)value
                             resolver : (RCTPromiseResolveBlock)resolve
                               rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *jsonError = nil;
    NSData *valueData = [NSJSONSerialization dataWithJSONObject:value ?: [NSNull null]
                                                        options:NSJSONWritingFragmentsAllowed
                                                          error:&jsonError];
    if (valueData == nil) {
      reject(@"vela_rust", @"Unable to serialize custom field value", jsonError);
      return;
    }

    NSString *valueJson = [[NSString alloc] initWithData:valueData
                                                encoding:NSUTF8StringEncoding];
    if (valueJson == nil) {
      reject(@"vela_rust", @"Unable to encode custom field value", nil);
      return;
    }

    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    char *result = vela_set_custom_field_value_json(
      serviceUrlUtf8,
      tokenUtf8,
      issueId.UTF8String,
      fieldId.UTF8String,
      fieldType.UTF8String,
      valueJson.UTF8String);
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(applyCustomFieldEvent,
                 applyCustomFieldEventWithServiceUrl : (NSString *)serviceUrl
                   bearerToken : (NSString *)bearerToken
                     issueId : (NSString *)issueId
                       fieldId : (NSString *)fieldId
                         fieldType : (NSString *)fieldType
                           eventId : (NSString *)eventId
                             resolver : (RCTPromiseResolveBlock)resolve
                               rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    char *result = vela_apply_custom_field_event_json(
      serviceUrlUtf8,
      tokenUtf8,
      issueId.UTF8String,
      fieldId.UTF8String,
      fieldType.UTF8String,
      eventId.UTF8String);
    ResolveRustResponse(result, resolve, reject);
  });
}

static NSString *VelaCachePath(void)
{
  NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
  return [[support stringByAppendingPathComponent:@"Vela"] stringByAppendingPathComponent:@"cache.sqlite3"];
}

RCT_REMAP_METHOD(storeMyWork,
                 storeMyWorkWithServiceUrl : (NSString *)serviceUrl
                   accountId : (NSString *)accountId
                     top : (nonnull NSNumber *)top
                       workJson : (NSString *)workJson
                         resolver : (RCTPromiseResolveBlock)resolve
                           rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSString *scope = [NSString stringWithFormat:@"%@::%@", serviceUrl, accountId];
    char *result = vela_store_my_work_json(VelaCachePath().UTF8String,
                                           scope.UTF8String,
                                           MAX((NSUInteger)1, top.unsignedIntegerValue),
                                           workJson.UTF8String);
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(cachedMyWork,
                 cachedMyWorkWithServiceUrl : (NSString *)serviceUrl
                   accountId : (NSString *)accountId
                     top : (nonnull NSNumber *)top
                       resolver : (RCTPromiseResolveBlock)resolve
                         rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSString *scope = [NSString stringWithFormat:@"%@::%@", serviceUrl, accountId];
    char *result = vela_cached_my_work_json(VelaCachePath().UTF8String, scope.UTF8String, MAX((NSUInteger)1, top.unsignedIntegerValue));
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(refreshMyWork,
                 refreshMyWorkWithServiceUrl : (NSString *)serviceUrl
                   bearerToken : (NSString *)bearerToken
                     accountId : (NSString *)accountId
                       top : (nonnull NSNumber *)top
                         resolver : (RCTPromiseResolveBlock)resolve
                           rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSString *scope = [NSString stringWithFormat:@"%@::%@", serviceUrl, accountId];
    char *result = vela_refresh_my_work_json(serviceUrl.UTF8String,
                                             bearerToken.length ? bearerToken.UTF8String : NULL,
                                             VelaCachePath().UTF8String,
                                             scope.UTF8String,
                                             MAX((NSUInteger)1, top.unsignedIntegerValue));
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(loadMyWork,
                 loadMyWorkWithServiceUrl : (NSString *)serviceUrl
                   bearerToken : (NSString *)bearerToken
                     top : (nonnull NSNumber *)top
                       resolver : (RCTPromiseResolveBlock)resolve
                         rejecter : (RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    NSUInteger topValue = MAX((NSUInteger)1, top.unsignedIntegerValue);
    char *result = vela_load_my_work_json(serviceUrlUtf8, tokenUtf8, topValue);

    ResolveRustResponse(result, resolve, reject);
  });
}

@end
