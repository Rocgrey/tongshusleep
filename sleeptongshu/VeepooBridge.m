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
@property(nonatomic) BOOL historyStarted;
@property(nonatomic, strong) NSTimer *batteryDeadline;
@property(nonatomic, strong) NSTimer *probeDeadline;
@property(nonatomic) BOOL probing;
@property(nonatomic) BOOL probeFinished;
@property(nonatomic) NSUInteger probeGeneration;
@property(nonatomic) NSUInteger probeDayIndex;
@property(nonatomic) NSUInteger probeBlocks;
@property(nonatomic) NSUInteger probeBytes;
@property(nonatomic, strong) NSMutableSet<NSString *> *probeKeys;
@property(nonatomic) NSUInteger wavePoints;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *inventory;
@property(nonatomic) BOOL inventoryTruncated;
@property(nonatomic, copy) NSString *baseReadStatus;
@property(nonatomic) BOOL collecting;
@property(nonatomic, strong) NSDictionary *pendingResult;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *sourceWindowCounts;
@end

@implementation STVeepooBridge
- (void)startWithPeripheral:(CBPeripheral *)peripheral {
    self.stopped = NO;
    self.reading = NO;
    self.oxygenReading = NO;
    self.hrvReading = NO;
    self.pendingPeripheral = peripheral;
    self.connectionStarted = NO;
    self.historyStarted = NO;
    self.probing = NO; self.probeFinished = NO; self.probeGeneration = 0;
    self.probeDayIndex = 0; self.probeBlocks = 0; self.probeBytes = 0; self.wavePoints = 0;
    self.probeKeys = [NSMutableSet set]; self.inventory = [NSMutableArray array];
    self.inventoryTruncated = NO; self.baseReadStatus = @"历史传输未完成";
    self.collecting = NO; self.pendingResult = nil;
    self.sourceWindowCounts = [NSMutableDictionary dictionary];
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
            else if (state == VPDeviceConnectStateDisConnect && owner.reading) {
                if (owner.probing && owner.pendingResult) [owner finishProbe:@"验证期间断开，已保留候选信号及此前完成的历史同步"];
                else if (owner.failed) owner.failed(@"读取期间设备已断开，未保存本次不完整传输。");
            }
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
    if (self.validationEnabled) {
        VPPeripheralModel *device = [VPBleCentralManage sharedBleManager].peripheralModel;
        if (self.validationData) self.validationData(@{@"kind": @"identity", @"firmware": device.deviceVersion ?: @"未知",
            @"capabilities": @{@"sleepType": @(device.sleepType), @"oxygenType": @(device.oxygenType), @"hrvType": @(device.hrvType),
                @"ecgType": @(device.ecgType), @"resRateType": @(device.resRateType), @"saveDays": @(device.saveDays)}});
        __weak typeof(self) weakOwner = self;
        // Passive callback only: do not enable a model-specific measurement mode.
        [VPBleCentralManage sharedBleManager].peripheralManage.ReceiveGreenLightData = ^(NSArray<NSNumber *> *values) {
            if (![values isKindOfClass:[NSArray class]] || !values.count) return;
            NSArray *copy = [values subarrayWithRange:NSMakeRange(0, MIN(values.count, 2048))];
            dispatch_async(dispatch_get_main_queue(), ^{
                STVeepooBridge *owner = weakOwner;
                if (!owner || owner.stopped || owner.wavePoints >= 20000) return;
                owner.wavePoints += copy.count;
                if (owner.validationData) owner.validationData(@{@"kind": @"wave", @"values": copy});
            });
        };
        if (self.validationData) self.validationData(@{@"kind": @"state", @"wave": @"正在观察设备主动回调，未开启定制测量模式"});
    }
    if (self.event) self.event(@"设备验证通过，正在读取电量…");
    __weak typeof(self) weakSelf = self;
    // A missing battery response must not block the existing history transfer.
    self.batteryDeadline = [NSTimer scheduledTimerWithTimeInterval:4 repeats:NO block:^(NSTimer *timer) {
        STVeepooBridge *owner = weakSelf;
        if (!owner || owner.stopped) return;
        if (owner.event) owner.event(@"暂未收到电量，继续同步睡眠与体征。");
        [owner readBaseHistory];
    }];
    [[VPBleCentralManage sharedBleManager].peripheralManage veepooSDKReadDeviceBatteryInfo:^(BOOL isPercent, BOOL isLow, NSUInteger level) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STVeepooBridge *owner = weakSelf;
            if (!owner || owner.stopped) return;
            if (level <= (isPercent ? 100 : 4) && owner.batteryChanged) owner.batteryChanged(isPercent, isLow, level);
            [owner readBaseHistory];
        });
    }];
}

- (void)readBaseHistory {
    if (self.stopped || self.historyStarted) return;
    self.historyStarted = YES;
    [self.batteryDeadline invalidate];
    self.batteryDeadline = nil;
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
            if (state == VPReadDeviceBaseDataComplete) {
                owner.baseReadStatus = @"基础历史传输完成；字段快照仍可能含 SDK 此前缓存";
                if (owner.validationEnabled && owner.validationData) owner.validationData(@{@"kind": @"state", @"transport": owner.baseReadStatus});
                [owner readOxygen];
            }
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
            if (state == VPReadDeviceBaseDataComplete || state == VPReadDeviceBaseDataInvalid) {
                if (owner.event) owner.event(state == VPReadDeviceBaseDataComplete ? @"血氧历史传输完成" : @"血氧历史接口返回无效状态，仅检查已有缓存");
                [owner readHrv];
            }
        });
    }];
}

- (void)readHrv {
    if (self.stopped || self.hrvReading || self.probing || self.probeFinished) return;
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
            if (state == VPReadDeviceBaseDataComplete || state == VPReadDeviceBaseDataInvalid) {
                if (owner.event) owner.event(state == VPReadDeviceBaseDataComplete ? @"HRV 历史传输完成" : @"HRV 历史接口返回无效状态，仅检查已有缓存");
                [owner collectResults];
            }
        });
    }];
}

- (void)probeSignals {
    if (self.stopped || self.probing || self.probeFinished) return;
    self.probing = YES;
    [self.oxygenDeadline invalidate]; self.oxygenDeadline = nil;
    if (self.event) self.event(@"已保留历史结果，正在验证逐次心跳数据，最多约 45 秒…");
    if (self.validationData) self.validationData(@{@"kind": @"state", @"phase": @"signals"});
    [self readNextRRDay];
}

- (void)readNextRRDay {
    if (self.stopped || self.probeFinished) return;
    if (self.probeDayIndex >= 3) { [self finishProbe:@"最近三天读取结束，见已收到的数据块；空记录不代表不支持"]; return; }
    NSUInteger day = self.probeDayIndex;
    NSUInteger generation = ++self.probeGeneration;
    if (self.validationData) self.validationData(@{@"kind": @"state", @"rr": [NSString stringWithFormat:@"正在请求%@的逐次心跳记录", @[@"今天", @"昨天", @"前天"][day]]});
    __weak typeof(self) weakSelf = self;
    [self.probeDeadline invalidate];
    self.probeDeadline = [NSTimer scheduledTimerWithTimeInterval:15 repeats:NO block:^(NSTimer *timer) {
        STVeepooBridge *owner = weakSelf;
        if (!owner || owner.stopped || owner.probeFinished || owner.probeGeneration != generation) return;
        [owner finishProbe:@"等待回包超时，已保留收到的部分；尚不能确定是否支持。未继续发送其他日期请求"];
    }];
    [[VPBleCentralManage sharedBleManager].peripheralManage veepooSDK_readRRIntervalDataWithDayNumber:day blockNumber:1 result:^(id response, NSProgress *progress, NSError *error) {
        int64_t totalUnits = progress.totalUnitCount;
        int64_t completedUnits = progress.completedUnitCount;
        dispatch_async(dispatch_get_main_queue(), ^{
            STVeepooBridge *owner = weakSelf;
            if (!owner || owner.stopped || owner.probeFinished || owner.probeGeneration != generation) return;
            if (error) {
                if (owner.event) owner.event([NSString stringWithFormat:@"心跳间隔接口返回错误码 %ld", (long)error.code]);
                [owner finishProbe:[NSString stringWithFormat:@"接口返回错误码 %ld，尚不能确定是否支持；已保留部分数据", (long)error.code]];
                return;
            }
            if ([response isKindOfClass:[VPRRIntervalDataModel class]]) {
                VPRRIntervalDataModel *model = response;
                NSData *raw = model.dataStream ?: [NSData data];
                NSData *converted = model.dataConvertStream ?: [NSData data];
                NSString *key = [NSString stringWithFormat:@"%@|%@|%ld", model.date ?: @"", model.time ?: @"", (long)model.blockNumber];
                if ((raw.length || converted.length) && ![owner.probeKeys containsObject:key]) {
                    NSUInteger length = raw.length + converted.length;
                    if (owner.probeBlocks >= 180 || length > 32768 || owner.probeBytes + length > 500000) {
                        if (owner.validationData) owner.validationData(@{@"kind": @"state", @"rr": @"达到采集上限，保存部分数据", @"limit": @YES});
                        [owner finishProbe:@"达到采集上限，保存部分数据，未完成整晚读取"]; return;
                    }
                    [owner.probeKeys addObject:key]; owner.probeBlocks++; owner.probeBytes += length;
                    if (owner.validationData) owner.validationData(@{@"kind": @"rr", @"date": model.date ?: @"", @"time": model.time ?: @"",
                        @"number": @(model.blockNumber), @"raw": raw, @"converted": converted});
                }
            }
            if (totalUnits > 0 && completedUnits >= totalUnits) {
                owner.probeDayIndex++; [owner readNextRRDay];
            }
        });
    }];
}

- (void)finishProbe:(NSString *)status {
    if (self.stopped || self.probeFinished) return;
    self.probeFinished = YES; self.probing = NO; self.probeGeneration++;
    [self.probeDeadline invalidate]; self.probeDeadline = nil;
    if (self.validationData) self.validationData(@{@"kind": @"state", @"rr": status,
        @"wave": self.wavePoints > 0 ? @"已收到主动回调；单位、采样率及信号质量待确认" : @"未观察到主动回调；未主动开启型号专用测量"});
    [self deliverResults];
}

- (BOOL)excludeDiagnosticKey:(NSString *)key {
    NSString *lower = key.lowercaseString;
    for (NSString *word in @[@"glucose", @"bloodsugar", @"cholesterol", @"triglycer", @"uric", @"hdl", @"ldl", @"lipid", @"password", @"token", @"secret", @"address", @"mac", @"deviceid", @"uuid", @"血糖", @"血脂", @"尿酸"]) {
        if ([lower containsString:word]) return YES;
    }
    return NO;
}

- (void)captureWindow:(NSDictionary *)window source:(NSString *)source {
    if (!self.validationEnabled) return;
    NSUInteger sourceCount = self.sourceWindowCounts[source].unsignedIntegerValue;
    if (self.inventory.count >= 2000 || sourceCount >= 300) { self.inventoryTruncated = YES; return; }
    self.sourceWindowCounts[source] = @(sourceCount + 1);
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    for (id key in window) {
        if (![key isKindOfClass:[NSString class]] || [self excludeDiagnosticKey:key]) continue;
        id value = window[key];
        if ([value isKindOfClass:[NSArray class]]) {
            NSMutableArray *samples = [NSMutableArray array];
            if ([value count] > 256) self.inventoryTruncated = YES;
            for (id item in [value subarrayWithRange:NSMakeRange(0, MIN([value count], 256))]) {
                if ([item isKindOfClass:[NSNumber class]]) [samples addObject:item];
            }
            fields[key] = samples;
        } else if ([value isKindOfClass:[NSNumber class]]) fields[key] = value;
        else if ([value isKindOfClass:[NSString class]]) fields[key] = [value substringToIndex:MIN([value length], 100)];
        else fields[key] = [NSString stringWithFormat:@"未解析类型：%@", NSStringFromClass([value class])];
    }
    [self.inventory addObject:@{source: fields}];
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
    if (self.stopped || self.collecting) return;
    self.collecting = YES;
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
                [self captureWindow:@{@"sleepTime": model.sleepTime ?: @"", @"wakeTime": model.wakeTime ?: @"", @"pointSeconds": model.onePointDuration ?: @"", @"returnedStageCount": @([model parseSleepLine].count)} source:@"sleep"];
                for (NSDictionary *point in [[model parseSleepLine] subarrayWithRange:NSMakeRange(0, MIN([model parseSleepLine].count, 60))]) {
                    if ([point isKindOfClass:[NSDictionary class]]) [self captureWindow:point source:@"sleepStage"];
                }
                if ([model parseSleepLine].count > 60 && self.validationEnabled) self.inventoryTruncated = YES;
                [sleeps addObject:@{@"format": @"accurate", @"start": model.sleepTime ?: @"", @"end": model.wakeTime ?: @"",
                    @"points": [model parseSleepLine] ?: @[], @"pointSeconds": model.onePointDuration ?: @"",
                    @"previous": model.lastType ?: @"0", @"next": model.nextType ?: @"0"}];
            }
        } else {
            NSArray *models = [VPDataBaseOperation veepooSDKGetSleepDataWithDate:day andTableID:address];
            for (NSDictionary *model in models) {
                if (![model isKindOfClass:[NSDictionary class]]) continue;
                [self captureWindow:model source:@"sleep"];
                [sleeps addObject:@{@"format": @"normal", @"start": model[@"SLEEP_TIME"] ?: @"", @"end": model[@"WAKE_TIME"] ?: @"",
                    @"line": model[@"SLE_LINE"] ?: @""}];
            }
        }
        NSDictionary *heart = [VPDataBaseOperation veepooSDKGetOriginalDataWithDate:day andTableID:address];
        for (NSString *clock in [heart.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            NSDictionary *value = heart[clock];
            if ([clock isKindOfClass:[NSString class]] && [value isKindOfClass:[NSDictionary class]]) {
                [self captureWindow:value source:@"history"];
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
            [self captureWindow:value source:@"hrv"];
            [vitals addObject:@{@"time": [NSString stringWithFormat:@"%@ %@", day, value[@"time"]], @"hrv": value[@"hrvValue"] ?: @0}];
        }
        NSArray *oxygen = [VPDataBaseOperation veepooSDKGetDeviceOxygenDataWithDate:day andTableID:address];
        for (NSDictionary *value in oxygen) {
            if (![value isKindOfClass:[NSDictionary class]] || ![value[@"Time"] isKindOfClass:[NSString class]]) continue;
            [self captureWindow:value source:@"oxygen"];
            [vitals addObject:@{@"time": [NSString stringWithFormat:@"%@ %@", day, value[@"Time"]],
                @"oxygen": value[@"OxygenValue"] ?: @0, @"respiration": value[@"RespirationRate"] ?: @0}];
        }
    }
    if (self.validationEnabled && self.validationData) self.validationData(@{@"kind": @"inventory", @"windows": self.inventory, @"truncated": @(self.inventoryTruncated)});
    self.pendingResult = @{@"deviceID": address, @"firmware": device.deviceVersion ?: @"",
        @"sleepType": @(device.sleepType), @"sleeps": sleeps, @"vitals": vitals};
    if (self.validationEnabled) { [self probeSignals]; return; }
    [self deliverResults];
}

- (void)deliverResults {
    if (self.stopped || !self.pendingResult) return;
    self.stopped = YES;
    if (self.validationEnabled) [VPBleCentralManage sharedBleManager].peripheralManage.ReceiveGreenLightData = nil;
    [[VPBleCentralManage sharedBleManager] veepooSDKDisconnectDevice];
    if (self.completed) self.completed(self.pendingResult);
}

- (void)cancel {
    self.stopped = YES;
    [self.probeDeadline invalidate]; self.probeDeadline = nil; self.probeGeneration++;
    if (self.validationEnabled) [VPBleCentralManage sharedBleManager].peripheralManage.ReceiveGreenLightData = nil;
    [self.batteryDeadline invalidate];
    self.batteryDeadline = nil;
    self.pendingPeripheral = nil;
    [self.oxygenDeadline invalidate];
    self.oxygenDeadline = nil;
    [[VPBleCentralManage sharedBleManager] veepooSDKDisconnectDevice];
}
@end
#endif
