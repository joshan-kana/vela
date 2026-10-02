#import <Foundation/Foundation.h>
#import <React/RCTBridgeModule.h>

#import "../../../../crates/vela-ffi/include/vela_ffi.h"

@interface VelaRustModule : NSObject <RCTBridgeModule>
@end

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
