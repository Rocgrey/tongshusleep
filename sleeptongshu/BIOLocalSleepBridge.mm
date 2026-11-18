#import "BIOLocalSleepBridge.h"
#import <TargetConditionals.h>

#if !__has_feature(objc_arc)
#error BIOLocalSleepBridge requires ARC. Build with Configuration/IwownSleep.xcconfig.
#endif

#if SLEEP_IWOWN_LOCAL && TARGET_OS_IOS && !TARGET_OS_SIMULATOR && !TARGET_OS_MACCATALYST
#if !__has_include("../Vendor/IwownSleep/IVSleep.h")
#error Run scripts/setup-iwown-sleep.sh with the manufacturer Sleep folder before building for iPhone.
#endif
#import "../Vendor/IwownSleep/IVSleep.h"
#define ST_HAS_LOCAL_SLEEP 1
#include <memory>
#else
#define ST_HAS_LOCAL_SLEEP 0
#endif

@implementation STBIOLocalSleepBridge
+ (BOOL)available { return ST_HAS_LOCAL_SLEEP; }

#if ST_HAS_LOCAL_SLEEP
static NSString *STSleepTime(IV_SA_TimeInfo t) {
    return [NSString stringWithFormat:@"%04d-%02d-%02d %02d:%02d", t.year, t.month, t.day, t.hour, t.minute];
}
#endif

+ (NSData *)calculatePreviousPath:(NSString *)previousPath todayPath:(NSString *)todayPath
                            date:(NSString *)date rri:(NSArray<NSNumber *> *)rri error:(NSError **)error {
    // Strong owners must outlive the pool, including the NSError out-parameter.
    NSData *result = nil;
    NSError *failure = nil;
    // Serialize calculation and pool drainage: the closed library may use globals.
    @synchronized(self) {
        @autoreleasepool {
#if ST_HAS_LOCAL_SLEEP
            try {
                @try {
                    IVSleep *algorithm = [IVSleep new];
                    NSError *vendorError = nil;
                    IV_SA_SleepBufInfoV2 info = [algorithm ivSleepDataFromV2:previousPath
                        andTodayPath:todayPath andDate:date andRriData:rri andError:&vendorError];
                    // This pinned archive allocates IV_SA_SleepDataInfo[] with C++ new[].
                    std::unique_ptr<IV_SA_SleepDataInfo[]> owned(info.data);
                    if (vendorError || info.total < 0 || info.total > 2880 || (info.total > 0 && !info.data)) {
                        failure = [NSError errorWithDomain:@"BIO.LocalSleep" code:1
                            userInfo:@{NSLocalizedDescriptionKey: @"设备睡眠输入暂时无法计算，原始记录已保留。"}];
                    } else {
                        NSMutableArray *sections = [NSMutableArray array];
                        for (int i = 0; i < info.total; i++) {
                            IV_SA_SleepDataInfo item = info.data[i];
                            [sections addObject:@{@"start": STSleepTime(item.startTime),
                                @"end": STSleepTime(item.stopTime), @"type": @((int)item.type)}];
                        }
                        // V2 has no completion flag. Never invent a final-completeness guarantee.
                        NSDictionary *payload = @{@"completed": @0, @"start_time": STSleepTime(info.inSleepTime),
                            @"end_time": STSleepTime(info.outSleepTime), @"sections": sections};
                        result = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&failure];
                    }
                } @catch (NSException *exception) {
                    failure = [NSError errorWithDomain:@"BIO.LocalSleep" code:2
                        userInfo:@{NSLocalizedDescriptionKey: @"设备睡眠计算暂未完成，原始记录已保留。"}];
                }
            } catch (...) {
                failure = [NSError errorWithDomain:@"BIO.LocalSleep" code:4
                    userInfo:@{NSLocalizedDescriptionKey: @"设备睡眠输入暂时无法计算，原始记录已保留。"}];
            }
#else
            failure = [NSError errorWithDomain:@"BIO.LocalSleep" code:3
                userInfo:@{NSLocalizedDescriptionKey: @"本地设备睡眠算法需要在 iPhone 上运行。"}];
#endif
        }
    }
    if (error) *error = failure;
    return result;
}
@end
