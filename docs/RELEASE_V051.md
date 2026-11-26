# SleepGrove 0.5.1 (27)

本次在现有 App 上升级，Bundle ID、Keychain、SwiftData、手机监测、系统健康导入、BIO/戒指同步、AIS、课程和账号功能保留。没有新增 ISI。用户已授权合并 main；原有 0.4.4 标签及 0.5.0 改版分支仍可追溯。开发起点为 `4fc8fdf`，本次开发分支 `codex/sleepgrove-visual-temperature`。开始前已有的 Xcode 工程本机设置和旧截图不随本次提交。

## 界面与音频

- 使用 finesse-ui 的原生 Apple app 设计方向，沿用三套主题与动态颜色，不新增持续运行的首页动画。
- 睡眠：来源/日期之后先展示阶段时间轴，再展示时长、解释、入口和其他内容；可点击阶段查看详情。只连接时间相邻的真实阶段，不跨越未记录区间。
- 夜间体征：指标选择与真实散点图在采样汇总之前。一般体征页的时间图、每日变化图在参考解释之前。
- 助眠：晚安卡图片先展示；呼吸动画先于说明。开始及每次阶段切换播放 0.9 秒柔和合成提示音，支持开关、试听与音量。使用媒体音频会话，静音开关不会代替媒体音量控制；耳机仍按系统路由输出。
- 手机录音或白噪音倒计时存在时不抢占音频。离开呼吸页、暂停、结束或进入后台停止提示音。此练习不承诺后台连续指导。
- 掌心安睡仪：原生产品图、2/5/10 Hz 频率、简要使用介绍、官方说明入口、原生产品视频。视频使用官网确切公布的 `https://vid.sleep.phoenixtreeai.com/video/product-promo.mp4`，不猜路径。用户点击后才建立播放器，退出即释放。商品与京东链接继续读取本平台发布目录。
- 实物图来自 `https://sleep.tongshugene.net/assets/banner/banner-product.jpg`，产品资料来源 `https://sleep.tongshugene.net/#product`；没有引用未核实的效果百分比。

## 体温口径

BIO9 / 103 已确认的历史健康包 `health.temperatureData`：存在 `type` 与 `estiArm`，且 `type=TPA_MEASURE_TYPE_AUTO(1)` 时，使用既有协议解码规则 `Double(estiArm >> 16) / 100`，低 16 位不混入估算体温。仅接收有限的 25–45℃；这是接收边界，不是正常范围。缺失、未知类型、无效数值、未知设备/时区不生成值。

体温作为 `VitalKind.temperature` 存入原体征文件，与既有记录兼容。夜间归日仍为北京时间前日 18:00 至当日 12:00、归结束日。已有睡眠结果时均值只使用真实睡眠阶段内采样，清醒、未记录区间和末端边界不参与；没有分期时明确为夜间采样均值。腕部估算不等于口温/腋温，不套用体温计正常范围，不插值或用零补齐。

上传复用 Bearer 账号鉴权、`health/device-sync` 和原幂等键/版本。逐点字段：`kind=temperature, value, unit=℃, recorded_at, id`；睡眠附加可选 `average_temperature`，无值时不发字段。没有自动开启用户关闭的同步。

旧后台未声明体温能力时，不发送被丢弃的部分快照，不确认同步完成，完整本机记录保留待部署后重试。Web main 增加 `supported_vital_kinds`、接收校验和按设备分离的体温窗口，不需生产数据库结构迁移。WorkBuddy 操作说明见 Web 仓库 `docs/WORKBUDDY_TEMPERATURE_V051.md`。

## 运行与真机验收

本机项目：`/Users/ts/Documents/Codex/2026-10-23/app-10pro-app-ios-app-app`。

```sh
env DEVELOPER_DIR=/Users/ts/Downloads/Xcode.app/Contents/Developer \
  xcodebuild -project sleeptongshu.xcodeproj -scheme sleeptongshu \
  -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)' \
  build CODE_SIGNING_ALLOWED=NO
```

戒指工程选 `sleeptongshu-Ring.xcodeproj` / `sleeptongshu-Ring`，使用已有本机厂家 SDK 配置；支持 arm64 iPhone。真机签名沿用当前团队设置。

1. 助眠 → 4-7-8 呼吸：调高媒体音量，点击试听，再开始，核对吸气/屏息/呼气阶段都能听见轻柔声音；暂停/结束即停止。测试耳机路由、来电、夜间录音保护。
2. 设备检测重连 BIO，等读取结束 → 体征记录 → 体温。设备未返回有效体温时不强行显示数值；保留接入报告排查。
3. 睡眠 → 设备记录，核对阶段图位于前部；夜间指标可选择体温时，散点只表示采样。切换日期无虚构阶段。
4. WorkBuddy 部署 Web main 后，在保持登录与用户自动同步开关开启时，检查同账号 Web 睡眠与步数页的体温窗口。当前没有执行生产部署。
5. 掌心安睡仪 → 观看介绍，核对真实 CDN 视频；商品封面仍跳转平台配置的京东商品。

构建、自动化测试和截图结果见本文件末尾。模拟器截图中的数据均明确标注测试来源，不能当作 BIO 已返回体温的证据。音色文件可解码不等于已完成手机扬声器试听；真实硬件体温、耳机/来电与 CDN 完整播放仍需真机验收。

## 验证结果（2026-11-26）

- iOS 236 项单元测试：0 失败，1 项现场服务测试跳过。新增音频 WAV 有效性、音色强度/边界、录音保护、体温协议高低位、无值处理、存储兼容和后台能力检查。
- 六项系统睡眠界面回归通过：导入与刷新去重、仅卧床、未分期、空记录、大字体和最新有效睡眠选择。
- 三项新版导航/外观界面测试通过：五分区与原有功能、深色/动态字体/通知入口、体温曲线。最终体征页进一步改为菜单选指标、图表在卡片与说明前。
- 两项最终体征回归通过：可用指标/血氧/HRV图表，以及进入体征时保持当前BIO设备，不被另一设备的新记录替换。新增图表前置后的菜单操作已同步更新到界面测试。
- 普通工程 SE、iPhone 17e 模拟器构建通过；戒指工程 arm64 iOS 无签名构建通过，版本为0.5.1（27）。
- Web：159项 Python 测试、2项 JavaScript 测试通过；独立本地数据库/API/真实 Chrome 联调通过，48条合成体温实际上传、重复请求不重复应用、1280/390宽度图表和空状态均检查。没有操作生产健康数据。
- 官网产品视频 HEAD 返回200，类型video/mp4；未声称已完成整段真机播放。
- 截图：`docs/screenshots/v051`，首页与体温截图均为明确测试来源；`.xcresult` 与运行日志仅保存在忽略的本机 `work/`。

Web 已推送 main，提交 `1bc8f00`。请让 WorkBuddy 读取其仓库内的部署说明，审查后发布到原服务；目前代码推送与生产部署是两件事。
