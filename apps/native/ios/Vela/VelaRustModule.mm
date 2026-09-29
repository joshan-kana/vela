#import <Foundation/Foundation.h>
#import <React/RCTBridgeModule.h>
#import <Security/Security.h>

#import "../../../../crates/vela-ffi/include/vela_ffi.h"

@interface VelaRustModule : NSObject <RCTBridgeModule>
@end

static NSString *const VelaAccountService = @"io.github.joshankana.vela.youtrack";
static NSString *const VelaPermanentTokenAuthKind = @"permanent_token";

static NSError *VelaKeychainError(OSStatus status)
{
  NSString *message = (__bridge_transfer NSString *)SecCopyErrorMessageString(status, NULL);
  return [NSError errorWithDomain:@"VelaKeychain"
                             code:status
                         userInfo:@{NSLocalizedDescriptionKey: message ?: @"Keychain error"}];
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

static NSDictionary *VelaSavePermanentToken(NSString *serviceUrl,
                                             NSString *bearerToken,
                                             NSError **error)
{
  NSString *normalizedUrl =
    [serviceUrl stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

  NSArray<NSDictionary *> *entries = VelaAccountEntries(error);
  if (entries == nil) {
    return nil;
  }

  NSString *accountId = nil;
  for (NSDictionary *entry in entries) {
    if ([entry[@"service_url"] isEqualToString:normalizedUrl]) {
      accountId = entry[@"id"];
      break;
    }
  }
  if (accountId == nil) {
    accountId = [NSUUID UUID].UUIDString.lowercaseString;
  }

  NSDictionary *secret = @{
    @"service_url": normalizedUrl,
    @"bearer_token": bearerToken,
    @"auth_kind": VelaPermanentTokenAuthKind,
  };

  NSError *jsonError = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:secret options:0 error:&jsonError];
  if (data == nil) {
    if (error != NULL) {
      *error = jsonError;
    }
    return nil;
  }

  NSDictionary *query = @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService: VelaAccountService,
    (__bridge id)kSecAttrAccount: accountId,
  };

  NSDictionary *attributes = @{
    (__bridge id)kSecValueData: data,
    (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
  };

  OSStatus status = SecItemUpdate(
    (__bridge CFDictionaryRef)query,
    (__bridge CFDictionaryRef)attributes
  );

  if (status == errSecItemNotFound) {
    NSMutableDictionary *add = [query mutableCopy];
    [add addEntriesFromDictionary:attributes];
    status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
  }

  if (status != errSecSuccess) {
    if (error != NULL) {
      *error = VelaKeychainError(status);
    }
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
  NSDictionary *query = @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService: VelaAccountService,
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
  if (![secret isKindOfClass:[NSDictionary class]] ||
      ![secret[@"auth_kind"] isEqualToString:VelaPermanentTokenAuthKind] ||
      ![secret[@"bearer_token"] isKindOfClass:[NSString class]]) {
    if (error != NULL) {
      *error = jsonError ?: [NSError errorWithDomain:@"VelaKeychain"
                                                code:-1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Stored YouTrack credentials are invalid"}];
    }
    return nil;
  }

  return secret[@"bearer_token"];
}

static BOOL VelaDeleteAccount(NSString *accountId, NSError **error)
{
  NSDictionary *query = @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService: VelaAccountService,
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
                 listAccountsWithResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
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
                 savePermanentTokenAccountWithServiceUrl:(NSString *)serviceUrl
                 bearerToken:(NSString *)bearerToken
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
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
                 deleteAccountWithId:(NSString *)accountId
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *error = nil;
    if (!VelaDeleteAccount(accountId, &error)) {
      reject(@"vela_accounts", error.localizedDescription, error);
      return;
    }
    resolve(nil);
  });
}

RCT_REMAP_METHOD(loadAccountToken,
                 loadAccountTokenWithId:(NSString *)accountId
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
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

RCT_REMAP_METHOD(discover,
                 discoverWithServiceUrl:(NSString *)serviceUrl
                 bearerToken:(NSString *)bearerToken
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    char *result = vela_discover_json(serviceUrlUtf8, tokenUtf8);
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(loadProjectSchema,
                 loadProjectSchemaWithServiceUrl:(NSString *)serviceUrl
                 bearerToken:(NSString *)bearerToken
                 projectId:(NSString *)projectId
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    char *result = vela_project_schema_json(serviceUrlUtf8, tokenUtf8, projectId.UTF8String);
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(loadUsers,
                 loadUsersWithServiceUrl:(NSString *)serviceUrl
                 bearerToken:(NSString *)bearerToken
                 skip:(nonnull NSNumber *)skip
                 top:(nonnull NSNumber *)top
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
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
                 loadAgileBoardsWithServiceUrl:(NSString *)serviceUrl
                 bearerToken:(NSString *)bearerToken
                 skip:(nonnull NSNumber *)skip
                 top:(nonnull NSNumber *)top
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
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
                 loadSavedQueriesWithServiceUrl:(NSString *)serviceUrl
                 bearerToken:(NSString *)bearerToken
                 skip:(nonnull NSNumber *)skip
                 top:(nonnull NSNumber *)top
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
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

RCT_REMAP_METHOD(loadIssueDetails,
                 loadIssueDetailsWithServiceUrl:(NSString *)serviceUrl
                 bearerToken:(NSString *)bearerToken
                 issueId:(NSString *)issueId
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    char *result = vela_issue_details_json(serviceUrlUtf8, tokenUtf8, issueId.UTF8String);
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(loadIssueLinks,
                 loadIssueLinksWithServiceUrl:(NSString *)serviceUrl
                 bearerToken:(NSString *)bearerToken
                 issueId:(NSString *)issueId
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    char *result = vela_issue_links_json(serviceUrlUtf8, tokenUtf8, issueId.UTF8String);
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(setIssueSummary,
                 setIssueSummaryWithServiceUrl:(NSString *)serviceUrl
                 bearerToken:(NSString *)bearerToken
                 issueId:(NSString *)issueId
                 summary:(NSString *)summary
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    char *result = vela_set_issue_summary_json(
      serviceUrlUtf8,
      tokenUtf8,
      issueId.UTF8String,
      summary.UTF8String
    );
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(setIssueDescription,
                 setIssueDescriptionWithServiceUrl:(NSString *)serviceUrl
                 bearerToken:(NSString *)bearerToken
                 issueId:(NSString *)issueId
                 description:(id)description
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
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
      descriptionUtf8
    );
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(setCustomFieldValue,
                 setCustomFieldValueWithServiceUrl:(NSString *)serviceUrl
                 bearerToken:(NSString *)bearerToken
                 issueId:(NSString *)issueId
                 fieldId:(NSString *)fieldId
                 fieldType:(NSString *)fieldType
                 value:(id)value
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
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
      valueJson.UTF8String
    );
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(applyCustomFieldEvent,
                 applyCustomFieldEventWithServiceUrl:(NSString *)serviceUrl
                 bearerToken:(NSString *)bearerToken
                 issueId:(NSString *)issueId
                 fieldId:(NSString *)fieldId
                 fieldType:(NSString *)fieldType
                 eventId:(NSString *)eventId
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
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
      eventId.UTF8String
    );
    ResolveRustResponse(result, resolve, reject);
  });
}

RCT_REMAP_METHOD(loadMyWork,
                 loadMyWorkWithServiceUrl:(NSString *)serviceUrl
                 bearerToken:(NSString *)bearerToken
                 top:(nonnull NSNumber *)top
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
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
