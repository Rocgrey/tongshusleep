#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

NS_ASSUME_NONNULL_BEGIN
@interface STVeepooBridge : NSObject
@property(nonatomic, copy, nullable) void (^event)(NSString *message);
@property(nonatomic, copy, nullable) void (^progress)(NSUInteger total, NSUInteger day, NSUInteger percent);
@property(nonatomic, copy, nullable) void (^batteryChanged)(BOOL isPercent, BOOL isLow, NSUInteger level);
@property(nonatomic, copy, nullable) void (^completed)(NSDictionary *result);
@property(nonatomic, copy, nullable) void (^failed)(NSString *message);
@property(nonatomic) BOOL validationEnabled;
@property(nonatomic, copy, nullable) void (^validationData)(NSDictionary *snapshot);
- (void)startWithPeripheral:(CBPeripheral *)peripheral NS_SWIFT_NAME(start(peripheral:));
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
