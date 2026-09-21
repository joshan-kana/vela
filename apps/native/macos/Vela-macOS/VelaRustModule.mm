#import <Foundation/Foundation.h>
#import <React/RCTBridgeModule.h>

#import "../../../../crates/vela-ffi/include/vela_ffi.h"

@interface VelaRustModule : NSObject <RCTBridgeModule>
@end

@implementation VelaRustModule

RCT_EXPORT_MODULE(VelaRust)

RCT_REMAP_METHOD(checkConnection,
                 checkConnectionWithServiceUrl:(NSString *)serviceUrl
                 bearerToken:(NSString *)bearerToken
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const char *serviceUrlUtf8 = serviceUrl.UTF8String;
    const char *tokenUtf8 = bearerToken.length > 0 ? bearerToken.UTF8String : NULL;
    char *result = vela_check_connection_json(serviceUrlUtf8, tokenUtf8);

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
      resolve(response[@"user"]);
      return;
    }

    NSString *message = response[@"message"];
    reject(@"youtrack_connection",
           [message isKindOfClass:[NSString class]] ? message : @"Connection failed",
           nil);
  });
}

@end
