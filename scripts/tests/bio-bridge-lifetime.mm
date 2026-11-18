// Host-only ownership regression: exercise the production bridge with a synthetic
// engine, never the iPhone-only archive or a user's health data.
#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#undef TARGET_OS_IOS
#define TARGET_OS_IOS 1
#undef TARGET_OS_SIMULATOR
#define TARGET_OS_SIMULATOR 0
#undef TARGET_OS_MACCATALYST
#define TARGET_OS_MACCATALYST 0
#define SLEEP_IWOWN_LOCAL 1
#import "../../sleeptongshu/BIOLocalSleepBridge.mm"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation IVSleep
- (IV_SA_SleepBufInfoV2)ivSleepDataFromV2:(NSString *)previousPath andTodayPath:(NSString *)todayPath
    andDate:(NSString *)date andRriData:(NSArray<NSNumber *> *)rri andError:(NSError **)error {
    IV_SA_SleepBufInfoV2 info = {};
    if ([date isEqualToString:@"vendor-error"]) {
        if (error) *error = [NSError errorWithDomain:@"SyntheticEngine" code:1 userInfo:nil];
    } else if ([date isEqualToString:@"objc-exception"]) {
        [NSException raise:@"SyntheticFailure" format:@"Ownership test"];
    } else if ([date isEqualToString:@"cpp-exception"]) {
        throw 1;
    } else if ([date isEqualToString:@"invalid-buffer"]) {
        info.total = 1;
    } else if (![date isEqualToString:@"empty"]) {
        info.inSleepTime = {2026, 11, 16, 23, 0};
        info.outSleepTime = {2026, 11, 17, 7, 0};
        info.total = 1;
        info.data = new IV_SA_SleepDataInfo[1];
        info.data[0] = {info.inSleepTime, info.outSleepTime, IV_SA_STATE_SLEEP_DEEP_SLEEP};
    }
    return info;
}
@end
#pragma clang diagnostic pop

int main(void) {
    @autoreleasepool {
        for (int i = 0; i < 1000; ++i) {
            NSError *error = nil;
            NSData *data = [STBIOLocalSleepBridge calculatePreviousPath:@"unused" todayPath:@"unused"
                date:@"20261117" rri:@[] error:&error];
            // The production bridge has already drained its inner pool here.
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            NSCAssert(!error && [json[@"sections"] count] == 1, @"Returned bytes must remain valid");
            NSCAssert([json[@"sections"][0][@"type"] intValue] == 3, @"Keep native stage mapping");
        }
        for (NSString *mode in @[@"vendor-error", @"invalid-buffer", @"objc-exception", @"cpp-exception"]) {
            NSError *error = nil;
            NSData *data = [STBIOLocalSleepBridge calculatePreviousPath:@"unused" todayPath:@"unused"
                date:mode rri:@[] error:&error];
            NSCAssert(!data && [error.domain isEqualToString:@"BIO.LocalSleep"], @"Error must survive pool drainage");
            NSCAssert(error.localizedDescription.length > 0, @"Caller must be able to read the error");
            NSCAssert(error.code == ([mode isEqualToString:@"objc-exception"] ? 2 :
                [mode isEqualToString:@"cpp-exception"] ? 4 : 1), @"Preserve error classification");
            NSCAssert(![STBIOLocalSleepBridge calculatePreviousPath:@"unused" todayPath:@"unused"
                date:mode rri:@[] error:NULL], @"A caller may omit the error output");
        }
        NSError *error = [NSError errorWithDomain:@"StaleError" code:1 userInfo:nil];
        NSData *empty = [STBIOLocalSleepBridge calculatePreviousPath:@"unused" todayPath:@"unused"
            date:@"empty" rri:@[] error:&error];
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:empty options:0 error:&error];
        NSCAssert(!error && [json[@"sections"] count] == 0, @"Empty native results stay empty");
        puts("BIO bridge ownership: 1000 results, empty result, NSError and exception paths passed (synthetic engine).");
    }
}
