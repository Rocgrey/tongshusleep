# SleepGrove 0.5.6 (32)

基于 0.5.5 `95ed8fe51811a74d6a2c747ed0fa883d5dd2490c`，开发分支 `codex/swiss-temperature`。沿用同一个 App、Bundle ID、SwiftData 和本机数据，不修改服务端契约。

## 项目检查与技能安装

- 实际项目为 SwiftUI 原生 App，最低 iOS 17，工程 Swift 语言模式 5，使用 Xcode 27.2。SwiftUI、Swift Charts、SwiftData 与 HealthKit 跟随系统 SDK，没有 React、Tailwind 或 Web 样式依赖；本地 SwiftProtobuf 为 1.29.0。
- 保留睡眠、科普、助眠、产品、用户中心五个 Tab，以及监测、趋势、健康入口；登录、采集、蓝牙、课程播放与同步逻辑沿用现有实现。
- 官方 `ui-ux-pro-max-cli` 2.15.0 已安装在本机用户工具目录。执行了 `uipro init --ai codex --global --offline`，使用 npm 官方发布包内的模板生成全局技能，不依赖运行时下载。
- 全局技能：`/Users/ts/.agents/skills/ui-ux-pro-max`，Codex 技能目录中有相应链接。下一轮会话可自动识别；本轮已直接读取指南，并运行 Minimalism & Swiss Style、体温时间序列和 SwiftUI 可访问性搜索。
- 新开终端可使用 `uipro --version` 或在其他项目运行 `uipro init --ai codex`。用户本机的 CLI、运行时与技能数据不加入 App 源码仓库。

## 视觉与交互

复用 `SleepPalette`，增加其内部的布局、字体和交互语义变量，不另建平行主题。中性浅灰背景、黑白清晰文字、克制描边与阴影，搭配现有品牌色及睡眠阶段颜色。商务、清新、可爱三个外观选择保留。

- `GroveControls.swift`：主按钮实色、次按钮描边，统一圆角、最小触控尺寸、按压与悬停反馈；键盘焦点描边和输入框边界更清楚。输入框只读取焦点环境，不覆盖业务页面原有 FocusState。
- `GroveVisuals.swift`、`SleepGroveViews.swift`：共用间距与圆角，降低色块强度，取消辅助区的装饰阴影。
- `SleepTongshuApp.swift`：更新现有语义颜色，章节标题改用系统动态字体。
- 支持深浅色、提高对比度及减弱动态效果。保留原生 Button、Picker、TextField 的交互与可访问性，不给整个界面增加持续动画。

## 设备与体温

- 移除监测与设备中的导入／管理绑定凭证按钮、文件夹导入及手输凭证页面。既有 Keychain、设备历史、自动同步和底层协议保留；本次不删除用户已保存的凭证。
- `TemperatureTrendView.swift`：睡眠页设备体征区增加体温概览，体征详情选择“体温”后复用。显示最近值、实际记录日期、同设备均值和每日高低范围；支持点选及前后日期按钮。
- `TemperatureSummary`：按本地日历筛选近 7 / 30 天，去重后仅汇总同一设备实际有效体温。每日均值为当天已有记录的算术平均；周期均值为周期内已有记录的算术平均。缺测日期不补零，不连接成连续曲线，也不把估算值套入体温计的正常范围。
- 没有体温时不生成图表。蓝牙解析与后台体温同步协议保持原样；本次没有新增 Web 接口或部署需求。

## 修改文件

业务和界面：`SleepTongshuApp.swift`、`GroveControls.swift`、`GroveVisuals.swift`、`SleepGroveViews.swift`、`EncryptedBandView.swift`、`VitalInsights.swift`、`TemperatureTrendView.swift`、`DeviceStepsView.swift`、`WearableVitalsView.swift`。

测试：`TemperaturePresentationTests.swift`、`TemperatureStyleUITests.swift`、`EncryptedBandUITests.swift`、`SleepGroveUITests.swift`。普通工程与戒指版配置只更新版本号，保留原有本机签名修改；README 与本说明记录交付。

## 尚存固定样式

本次先迁移共享控件和新图表，未全量改写既有业务页面。以下为静态扫描，列出固定字号、字面量圆角和直接 RGB 初始化出现次数；图标、插画和图表轴的固定尺寸并不都需要迁移。

| 文件 | 固定字号 | 字面量圆角 | RGB 初始化 |
| --- | ---: | ---: | ---: |
| AccountStepsView.swift | 7 | 0 | 0 |
| AccountView.swift | 15 | 1 | 0 |
| AppAppearance.swift | 0 | 0 | 5 |
| DeviceBatteryView.swift | 6 | 0 | 0 |
| DeviceStepsView.swift | 2 | 1 | 0 |
| DeviceValidationView.swift | 30 | 0 | 0 |
| GroveVisuals.swift | 1 | 0 | 0 |
| HealthMetricDetailView.swift | 19 | 3 | 0 |
| HealthOverviewView.swift | 61 | 4 | 2 |
| HealthSourceSelectionView.swift | 13 | 0 | 0 |
| LocalDataView.swift | 2 | 0 | 0 |
| MonitoringView.swift | 66 | 1 | 0 |
| PSQIQuestionArtwork.swift | 3 | 3 | 6 |
| PSQIView.swift | 0 | 2 | 0 |
| ProductIntroductionView.swift | 1 | 1 | 0 |
| SleepCharts.swift | 6 | 1 | 0 |
| SleepClassroomView.swift | 0 | 1 | 0 |
| SleepDashboardView.swift | 48 | 2 | 0 |
| SleepGroveViews.swift | 1 | 1 | 0 |
| SleepRelaxation.swift | 1 | 4 | 0 |
| SleepTongshuApp.swift | 6 | 0 | 4 |
| SleepUploadView.swift | 1 | 0 | 0 |
| SystemSleepImportView.swift | 0 | 1 | 0 |
| TemperatureTrendView.swift | 3 | 0 | 0 |
| WearableProbeView.swift | 27 | 0 | 0 |
| WearableVitalsView.swift | 23 | 3 | 0 |

## 验证与运行

已通过 38 项相关单元测试（体温筛选与去重、夏令时、颜色对比度、体温同步、体征和增强内容），以及 5 项界面测试（凭证入口移除、五个 Tab、账号表单、浅色体温交互、深色最大字号及三套外观切换）。分次执行，重复运行的测试不重复计数。普通工程模拟器测试构建、戒指工程通用 iOS arm64 无签名构建通过。

截图使用明确标注的界面测试数据：[首页](screenshots/v056/home-test-data.png)、[科普](screenshots/v056/classroom-test.png)、[助眠](screenshots/v056/relaxation-test.png)、[设备](screenshots/v056/devices-test.png)、[浅色体温图](screenshots/v056/temperature-light-test-data.png)、[深色大字号体温图](screenshots/v056/temperature-dark-large-test-data.png)。

本次没有验证真实 BIO 采样、外接键盘操作或真机安装；模拟器截图不代表读取了真实健康数据。不覆盖安装 iPhone，不修改线上服务。真机仍需检查体温采样、设备来源、系统字号和已有监测功能。

体温图表坐标采用紧凑字号，最大无障碍字号时减少日期刻度；完整日期和数值仍通过动态字体的逐日说明、前后按钮和 VoiceOver 提供。界面测试会把首页与弹出详情中的同名图表分别定位。

打开 `sleeptongshu.xcodeproj` 并运行 `sleeptongshu`；真机戒指版打开 `sleeptongshu-Ring.xcodeproj` 并选择对应 scheme。进入“监测与设备 → 设备检测”确认凭证入口已移除。连接有真实体温记录的设备，回睡眠页查看体温趋势，或进入“体征记录 → 体温”切换近 7 / 30 天。无记录不展示虚构体温。
