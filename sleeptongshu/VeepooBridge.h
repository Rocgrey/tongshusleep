#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

NS_ASSUME_NONNULL_BEGIN
@interface STVeepooBridge : NSObject
@property(nonatomic, copy, nullable) void (^event)(NSString *message);
@property(nonatomic, copy, nullable) void (^progress)(NSUInteger total, NSUInteger day, NSUInteger percent);
@property(nonatomic, copy, nullable) void (^completed)(NSDictionary *result);
@property(nonatomic, copy, nullable) void (^failed)(NSString *message);
- (void)startWithPeripheral:(CBPeripheral *)peripheral NS_SWIFT_NAME(start(peripheral:));
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
