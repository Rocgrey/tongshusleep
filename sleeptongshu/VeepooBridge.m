#if SLEEP_VEEPOO
#import "VeepooBridge.h"
#import <VeepooBleSDK/VeepooBleSDK.h>

@interface STVeepooBridge ()
@property(nonatomic) BOOL stopped;
@property(nonatomic) BOOL reading;
@property(nonatomic) BOOL oxygenReading;
@property(nonatomic) BOOL hrvReading;
@property(nonatomic, strong) NSTimer *oxygenDeadline;
@property(nonatomic, strong) CBPeripheral *pendingPeripheral;
@property(nonatomic) BOOL connectionStarted;
@end

@implementation STVeepooBridge
- (void)startWithPeripheral:(CBPeripheral *)peripheral {
    self.stopped = NO;
    self.reading = NO;
    self.oxygenReading = NO;
    self.hrvReading = NO;
    self.pendingPeripheral = peripheral;
    self.connectionStarted = NO;
    VPBleCentralManage *manager = [VPBleCentralManage sharedBleManager];
    manager.isLogEnable = NO;
    manager.automaticConnection = NO;
    manager.systemLanguage = NO;
    manager.isAutoShowPair = NO;
    manager.isAutoConnectBT = NO;
    manager.peripheralManage = [VPPeripheralManage shareVPPeripheralManager];
    __weak typeof(self) weakSelf = self;
    manager.VPBleCentralManageChangeBlock = ^(VPCentralManagerState state) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STVeepooBridge *owner = weakSelf;
            if (!owner || owner.stopped) return;
            if (state == VPCentralManagerStatePoweredOn) [owner connectIfReady];
            else if ((state == VPCentralManagerStateUnauthorized || state == VPCentralManagerStatePoweredOff) && owner.failed) {
                owner.failed(@"厂商蓝牙通道不可用，请检查蓝牙开关与 App 权限。");
            }
        });
    };
    manager.VPBleConnectStateChangeBlock = ^(VPDeviceConnectState state) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STVeepooBridge *owner = weakSelf;
            if (!owner || owner.stopped) return;
            if (state == VPDeviceConnectStateVerifyPasswordSuccess) [owner readHistory];
            else if (state == VPDeviceConnectStateVerifyPasswordFailure && owner.failed) owner.failed(@"设备验证未通过，未读取历史数据。");
            else if (state == VPDeviceConnectStateDisConnect && owner.reading && owner.failed) owner.failed(@"读取期间设备已断开，未保存本次不完整传输。");
        });
    };
    [self connectIfReady];
}

- (void)connectIfReady {
    if (self.stopped || self.connectionStarted || !self.pendingPeripheral) return;
    VPBleCentralManage *manager = [VPBleCentralManage sharedBleManager];
    if (manager.centralManager.state != CBManagerStatePoweredOn) {
        if (self.event) self.event(@"正在等待厂商蓝牙通道就绪…");
        return;
    }
    self.connectionStarted = YES;
    __weak typeof(self) weakSelf = self;
    [manager veepooSDKSelfScanConnectDevice:self.pendingPeripheral deviceConnectBlock:^(DeviceConnectState state) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STVeepooBridge *owner = weakSelf;
            if (!owner || owner.stopped) return;
            switch (state) {
                case 0: if (owner.failed) owner.failed(@"蓝牙未开启"); break;
                case 1: if (owner.event) owner.event(@"正在通过厂商接口连接戒指…"); break;
                case 2: if (owner.event) owner.event(@"已连接，正在验证设备…"); break;
                case 3: if (owner.failed) owner.failed(@"设备通道连接失败，请先结束其他 App 的同步再重试。"); break;
                case 4: [owner readHistory]; break;
                case 5: if (owner.failed) owner.failed(@"设备验证未通过。请保留原有绑定和历史记录，勿恢复出厂设置。"); break;
                case 6: case 7: if (owner.failed) owner.failed(@"设备连接或确认超时，请重新连接戒指。"); break;
                default: break;
            }
        });
    }];
}

- (void)readHistory {
    if (self.reading || self.stopped) return;
    self.reading = YES;
    VPPeripheralModel *device = [VPBleCentralManage sharedBleManager].peripheralModel;
    if (self.event) self.event([NSString stringWithFormat:@"设备验证通过 · 固件 %@ · 睡眠类型 %ld", device.deviceVersion ?: @"未知", (long)device.sleepType]);
    if (self.event) self.event(@"验证通过，正在读取历史睡眠与体征…");
    __weak typeof(self) weakSelf = self;
    [[[VPBleCentralManage sharedBleManager] peripheralManage]
        veepooSdkStartReadDeviceAllDataWithReadStateChangeBlock:^(VPReadDeviceBaseDataState state, NSUInteger total, NSUInteger day, NSUInteger percent) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STVeepooBridge *owner = weakSelf;
            if (!owner || owner.stopped) return;
            if (owner.progress) owner.progress(total, day, percent);
            if (state == VPReadDeviceBaseDataComplete) [owner readOxygen];
            else if (state == VPReadDeviceBaseDataInvalid && owner.failed) owner.failed(@"厂商 SDK 未能读取这版固件的历史数据。");
        });
    }];
}

- (void)readOxygen {
    if (self.stopped || self.oxygenReading) return;
    VPBleCentralManage *manager = [VPBleCentralManage sharedBleManager];
    if (manager.peripheralModel.oxygenType == 0) { [self readHrv]; return; }
    self.oxygenReading = YES;
    if (self.event) self.event(@"睡眠读取完成，正在读取可用的血氧与呼吸记录…");
    __weak typeof(self) weakSelf = self;
    self.oxygenDeadline = [NSTimer scheduledTimerWithTimeInterval:30 repeats:NO block:^(NSTimer *timer) {
        STVeepooBridge *owner = weakSelf;
        if (!owner || owner.stopped) return;
        if (owner.event) owner.event(@"血氧读取未完成，仅保留已读取的睡眠与其他可用体征。");
        [owner collectResults];
    }];
    [manager.peripheralManage veepooSdkStartReadDeviceOxygenData:^(VPReadDeviceBaseDataState state, NSUInteger total, NSUInteger day, NSUInteger percent) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STVeepooBridge *owner = weakSelf;
            if (!owner || owner.stopped) return;
            if (state == VPReadDeviceBaseDataComplete || state == VPReadDeviceBaseDataInvalid) [owner readHrv];
        });
    }];
}

- (void)readHrv {
    if (self.stopped || self.hrvReading) return;
    [self.oxygenDeadline invalidate];
    self.oxygenDeadline = nil;
    VPBleCentralManage *manager = [VPBleCentralManage sharedBleManager];
    if (manager.peripheralModel.hrvType == 0) { [self collectResults]; return; }
    self.hrvReading = YES;
    if (self.event) self.event(@"正在读取可用的 HRV 历史记录…");
    __weak typeof(self) weakSelf = self;
    self.oxygenDeadline = [NSTimer scheduledTimerWithTimeInterval:30 repeats:NO block:^(NSTimer *timer) {
        STVeepooBridge *owner = weakSelf;
        if (!owner || owner.stopped) return;
        if (owner.event) owner.event(@"HRV 传输未完成，仅保留已取得的数据。");
        [owner collectResults];
    }];
    [manager.peripheralManage veepooSdkStartReadDeviceHrvData:^(VPReadDeviceBaseDataState state, NSUInteger total, NSUInteger day, NSUInteger percent) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STVeepooBridge *owner = weakSelf;
            if (!owner || owner.stopped) return;
            if (state == VPReadDeviceBaseDataComplete || state == VPReadDeviceBaseDataInvalid) [owner collectResults];
        });
    }];
}

- (NSNumber *)meanOfPositiveValues:(id)values {
    if (![values isKindOfClass:[NSArray class]]) return @0;
    double sum = 0;
    NSUInteger count = 0;
    for (id item in values) {
        if (![item respondsToSelector:@selector(doubleValue)]) continue;
        double number = [item doubleValue];
        if (isfinite(number) && number > 0 && number != 255) { sum += number; count++; }
    }
    return count ? @(sum / count) : @0;
}

- (void)collectResults {
    if (self.stopped) return;
    [self.oxygenDeadline invalidate];
    self.oxygenDeadline = nil;
    VPPeripheralModel *device = [VPBleCentralManage sharedBleManager].peripheralModel;
    NSString *address = device.deviceAddress;
    if (!address.length) {
        if (self.failed) self.failed(@"设备验证后没有返回可用标识，未保存数据。");
        return;
    }
    NSMutableArray *sleeps = [NSMutableArray array];
    NSMutableArray *vitals = [NSMutableArray array];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    formatter.dateFormat = @"yyyy-MM-dd";
    NSCalendar *calendar = formatter.calendar;
    calendar.timeZone = [NSTimeZone localTimeZone];
    NSDate *today = [calendar startOfDayForDate:[NSDate date]];
    for (NSInteger offset = 0; offset <= MIN(MAX(device.saveDays, 1), 30); offset++) {
        NSString *day = [formatter stringFromDate:[calendar dateByAddingUnit:NSCalendarUnitDay value:-offset toDate:today options:0]];
        // The official demo treats every type except 0 and 2 as accurate sleep, including newer type 6.
        if (device.sleepType != 0 && device.sleepType != 2) {
            NSArray *models = [VPDataBaseOperation veepooSDKGetAccurateSleepDataWithDate:day andTableID:address];
            for (VPAccurateSleepModel *model in models) {
                if (![model isKindOfClass:[VPAccurateSleepModel class]]) continue;
                [sleeps addObject:@{@"format": @"accurate", @"start": model.sleepTime ?: @"", @"end": model.wakeTime ?: @"",
                    @"points": [model parseSleepLine] ?: @[], @"pointSeconds": model.onePointDuration ?: @"",
                    @"previous": model.lastType ?: @"0", @"next": model.nextType ?: @"0"}];
            }
        } else {
            NSArray *models = [VPDataBaseOperation veepooSDKGetSleepDataWithDate:day andTableID:address];
            for (NSDictionary *model in models) {
                if (![model isKindOfClass:[NSDictionary class]]) continue;
                [sleeps addObject:@{@"format": @"normal", @"start": model[@"SLEEP_TIME"] ?: @"", @"end": model[@"WAKE_TIME"] ?: @"",
                    @"line": model[@"SLE_LINE"] ?: @""}];
            }
        }
        NSDictionary *heart = [VPDataBaseOperation veepooSDKGetOriginalDataWithDate:day andTableID:address];
        for (NSString *clock in heart) {
            NSDictionary *value = heart[clock];
            if ([clock isKindOfClass:[NSString class]] && [value isKindOfClass:[NSDictionary class]]) {
                NSNumber *heartRate = value[@"heartValue"] ?: @0;
                NSString *origin = @"设备历史";
                if ([heartRate doubleValue] <= 0 || [heartRate doubleValue] == 255) {
                    heartRate = [self meanOfPositiveValues:value[@"ecgs"]];
                    if (heartRate.doubleValue == 0) heartRate = [self meanOfPositiveValues:value[@"ppgs"]];
                    origin = @"设备时段均值";
                }
                [vitals addObject:@{@"time": [NSString stringWithFormat:@"%@ %@", day, clock],
                    @"heart": heartRate, @"systolic": value[@"systolic"] ?: @0,
                    @"diastolic": value[@"diastolic"] ?: @0, @"stress": value[@"stress"] ?: @0, @"origin": origin}];
            }
        }
        NSArray *hrv = [VPDataBaseOperation veepooSDKGetDeviceHrvDataWithDate:day andTableID:address];
        for (NSDictionary *value in hrv) {
            if (![value isKindOfClass:[NSDictionary class]] || ![value[@"time"] isKindOfClass:[NSString class]]) continue;
            [vitals addObject:@{@"time": [NSString stringWithFormat:@"%@ %@", day, value[@"time"]], @"hrv": value[@"hrvValue"] ?: @0}];
        }
        NSArray *oxygen = [VPDataBaseOperation veepooSDKGetDeviceOxygenDataWithDate:day andTableID:address];
        for (NSDictionary *value in oxygen) {
            if (![value isKindOfClass:[NSDictionary class]] || ![value[@"Time"] isKindOfClass:[NSString class]]) continue;
            [vitals addObject:@{@"time": [NSString stringWithFormat:@"%@ %@", day, value[@"Time"]],
                @"oxygen": value[@"OxygenValue"] ?: @0, @"respiration": value[@"RespirationRate"] ?: @0}];
        }
    }
    self.stopped = YES;
    [[VPBleCentralManage sharedBleManager] veepooSDKDisconnectDevice];
    if (self.completed) self.completed(@{@"deviceID": address, @"firmware": device.deviceVersion ?: @"",
        @"sleepType": @(device.sleepType), @"sleeps": sleeps, @"vitals": vitals});
}

- (void)cancel {
    self.stopped = YES;
    self.pendingPeripheral = nil;
    [self.oxygenDeadline invalidate];
    self.oxygenDeadline = nil;
    [[VPBleCentralManage sharedBleManager] veepooSDKDisconnectDevice];
}
@end
#endif
