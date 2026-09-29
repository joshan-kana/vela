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
