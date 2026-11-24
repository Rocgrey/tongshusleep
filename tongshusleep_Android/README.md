# tongshusleep_Android · 睡眠同书（安卓端）

与 iOS 端 `sleeptongshu 0.4.2`（`../` 目录）功能对齐的原生安卓客户端：Kotlin + Jetpack Compose，单模块工程。

## 功能对照（iOS → Android）

| 模块 | iOS | Android | 状态 |
|---|---|---|---|
| 账号 | 手机号/邮箱注册登录、JWT、钥匙串会话、找回密码（短信/邮件验证码）、统一 401 退出 | EncryptedSharedPreferences 会话 + 同一套 `/api/v1` 契约 | ✅ |
| 睡眠记录 | SwiftData 记录、手动记录、AIS 0-24、阶段时间线/环图/心率曲线、参考分、30 晚示例 | Room + Compose Canvas 图表，同口径派生指标 | ✅ |
| 步数 | 三来源（设备/云端/系统健康）、upsert 不累加、Asia/Shanghai 分日、7/30 天统计 | StepSync 同契约 + Room 设备步数 | ✅ |
| 健康概览 | HealthKit 18 项、90 天聚合（累计求和/样本中位数）、FRIEND 身体年龄、探索性年龄、覆盖日历 | Health Connect 同口径复刻 | ✅ |
| 睡眠课堂 | 内置目录兜底 + 后台内容、课程视频（进度/横屏/选集）、阅读、京东白名单、今日阅读 | Media3 ExoPlayer + 同一份 catalog.json 兜底 | ✅ |
| 放松 | 4-7-8 呼吸、白噪音（定时渐弱）、晚安卡 | 同逻辑自绘 | ✅ |
| 提醒 | 本地通知（睡前/每日内容）+ APNs 远程 | WorkManager 本地提醒；远程推送需集成 FCM（预留） | ✅/预留 |
| 手机监测 | 声音+体动估算（SoundAnalysis 打鼾/说话） | AudioRecord+传感器，静默窗启发式同口径；无声音分类器（明确降级） | ✅/降级 |
| 设备 | Veepoo 戒指 SDK、BIO IVSleep.a 本机算法、小米手环 freeband、加密手环 | **BIO-7349 已接入**：Iwown BLE SDK（`blesdk260618.aar`，见下方"设备支持"）；Veepoo/小米/加密手环仍为占位。标准 GATT（电量/型号/心率/血压/血氧）可用 | 部分 |
| 自动同步 | device-sync 幂等、revision_at 先持久化、sync-capabilities 门控 | 同语义复刻 | ✅ |
| 外观 | 三套主题（商务/清新/可爱）+ 深浅模式 | 同色板复刻 | ✅ |

## 构建

1. Android Studio Ladybug (2024.2) 或更新，JDK 17。
2. 打开本目录（`tongshusleep_Android/`）作为工程根，Gradle 同步。
3. `Run` 直接安装到设备/模拟器（Android 8.0 / API 26+）。

### 服务配置（与 iOS `Service.xcconfig` 同口径）

`app/build.gradle.kts` 中：

```kotlin
buildConfigField("String", "SLEEP_API_BASE_URL", "\"https://tongshusleep-backend.app.workbuddy.host/api/v1\"")
buildConfigField("String", "SLEEP_GATEWAY_SHARE_CODE", "\"\"")
```

- `SLEEP_GATEWAY_SHARE_CODE` 按仓库约定**不提交真实分享码**（iOS 端放本机 `ServiceLocal.xcconfig`）。本地调试时填入部署分享码即可；留空则不启用网关握手（直连自有域名时无需）。
- 网关行为与 iOS 一致：请求前对根路径握手一次、全部请求追加 `?sharecode=`、`Authorization` 被网关改写时回退 `X-Auth-Token`。

### Health Connect

健康页数据来自 Health Connect。测试设备需安装 Health Connect APK 并授权；Play 服务渠道的正式分发需按 Google 政策声明健康数据用途。

### 设备支持：BIO-7349（Iwown BLE SDK）

监测页的「BIO-7349（Iwown SDK）」卡片已接入厂商 SDK（`app/libs/blesdk260618.aar` + `libble-0.5.aar`，核心类 `com.zeroner.blemidautumn.*`，代码在 `core/ble/IwownSdkManager.kt` 与 `core/ble/IwownHistorySync.kt`）。

已实现能力：

- 扫描/连接/断开（WristBand + AbsBle 门面），连接状态、电量/充电、固件版本、型号、SN 展示；
- 连接后自动初始化（对时、硬件能力、电量、实时数据订阅）；
- 实时心率测量（一键测量结果心率/血氧/血压/压力/呼吸率写入设备体征）；
- 原始信号采集 20 秒（ACC/BIOZ/PPG，sensorType 映射 16/512/2 与 iOS 一致），登录态经 `health/raw-sensor-batches` 上传，未登录仅缓存；
- 历史同步最近 3 天（0x80 索引表→分段拉取，健康/RRI 两类）：步数按天入 Room 并上传 `health/step-record`，心率/HRV/血压/血氧写入设备体征，睡眠 Q/T/E 与 RRI 样本按天落盘 `filesDir/iwown/`；
- 同步完成后调用厂商 AI 睡眠算法（`NativeInvoker.calculateSleepFileWithAF`，JNI），结果转为 SleepRecord（source=band，externalSource=iwown-bio）入库，登录态经 device-sync 上传；未登录仅落本地并在界面提示"登录后可同步"。

边界（未做）：

- GNSS / ECG / PPG 历史数据不拉取、不存档（SDK 支持但未接入）；
- 固件升级 DFU（libdfu/libfastdfu）未集成；
- 杰理芯片（JL 系列 AAR）相关功能未集成；
- 手环历史步数与本地步数合并去重策略与 iOS 端保持一致的前提是设备侧按天累计，多设备同日并存时以最近写入为准。

### 推送（远程提醒）

后端当前推送通道为 APNs（iOS）。Android 远程推送需后端增加 FCM 支持并在本工程集成 `firebase-messaging`，当前界面已预留开关并如实提示"需集成 FCM 后启用"。

## 目录结构

```
app/src/main/java/com/rocgrey/sleeptongshu/
├── MainActivity.kt            # 5 Tab 导航 + 路由（对应 iOS RootTabView）
├── TongshuApplication.kt      # AppContainer 服务定位器
├── core/
│   ├── api/                   # ApiClient（sharecode 网关/X-Auth-Token/401）+ 20 个端点模型
│   ├── auth/                  # 会话存储 + AccountStore
│   ├── data/                  # Room（睡眠记录/学习进度/设备步数/设备体征）+ 偏好
│   ├── sleep/                 # 领域模型/派生指标/备份 v2
│   ├── steps/                 # 三来源步数同步
│   ├── sync/                  # device-sync 幂等自动同步 + 旧接口直传
│   ├── health/                # Health Connect 读取/聚合/身体年龄
│   ├── classroom/             # 内容目录（内置兜底+远端+缓存）
│   ├── audio/                 # 白噪音生成与播放
│   ├── reminders/             # WorkManager 提醒
│   ├── ble/                   # 标准 GATT + 厂商通道预留接口
│   └── monitor/               # 手机监测前台服务
└── ui/                        # 睡眠/监测/趋势/健康/课堂/账号 Compose 页面
```

## 边界说明（如实标注）

- **厂商设备**：BIO-7349 已通过厂商 BLE SDK 接入（见"设备支持"）；Veepoo 戒指睡眠、小米手环等仍依赖对应厂商 SDK，当前版本明确显示"未接入"，不伪造数据。
- **声音分类**：Android 无 SoundAnalysis 等价内置，打鼾/说话统计恒为 0 并在界面标注。
- **示例数据**：首次启动生成 30 晚示例记录（与 iOS 一致，标注"示例"），可一键删除。
- **上传回执/幂等**：revision_at 先持久化再发送，重复同步不累加，与 iOS/后端契约一致。
