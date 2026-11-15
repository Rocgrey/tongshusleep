#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Copies the vendor's native result immediately; no native pointers escape to Swift.
@interface STBIOLocalSleepBridge : NSObject
@property(class, nonatomic, readonly) BOOL available;
+ (nullable NSData *)calculatePreviousPath:(NSString *)previousPath
                                todayPath:(NSString *)todayPath
                                     date:(NSString *)date
                                      rri:(NSArray<NSNumber *> *)rri
                                    error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(calculate(previousPath:todayPath:date:rri:));
@end
NS_ASSUME_NONNULL_END
