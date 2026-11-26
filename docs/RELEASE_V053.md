# SleepGrove 0.5.3 (29)

基于 0.5.2 commit `cebf542e3ef00f53da15272d5f676e533cb0bc1e`，开发分支 `codex/psqi-cartoon-assessment`。同一 App 的增量更新，本地原有签名设置和未提交旧截图保留，不覆盖手机或部署 Web。

## 本次调整

- 科普 → 自测只保留 PSQI，移除“已有 AIS 自评”和睡眠页 AIS 入口，删除独立 AIS 填写页面；旧手动上传页也不再提供问卷分输入。
- 新的手动及自动睡眠上传均不包含 `ais_score`，不发送 0 或 null 占位。PSQI 分数仅在原有本机自测历史保存，不冒充 AIS 或发送到睡眠上传接口。
- `SleepMetadata.aisScore` 只作为历史兼容字段保留，设备更新不删除用户历史数据，无数据库破坏性迁移。旧服务器响应即使含 AIS/ISI 字段仍可读取，不展示或恢复自评功能。
- PSQI 每题均增加本机绘制的卡通小枕头；18 个题目主题分别关联床、沙漏、闹钟、时钟、入睡等待、夜醒、起夜、呼吸、鼾声、冷、热、梦境、不适、其他原因、整体感受、药物、白天困倦、精力。
- 使用现有珊瑚、薰衣草、薄荷、暖黄、天蓝色设计变量；插画主体和表情一致，不暗示应该选择哪个答案。全为原生 Canvas/SF Symbols，无网络图片请求，无新增外部素材或依赖。
- 下一项与上一项固定在安全区域内，切题回到题首，选中项有描边及颜色；深色、大字体、读屏和减弱动态效果适配沿用系统设置。
- PSQI 18 项、七维 0–21 计分、校验、改善方向和按账号隔离的本机历史规则不变。

## 涉及代码

- 新增 `sleeptongshu/PSQIQuestionArtwork.swift`。
- 修改 `PSQIView.swift`、`SleepClassroomView.swift`、`SleepDashboardView.swift`、`SleepGroveViews.swift`。
- 删除 `SleepAISView.swift`；调整 `SleepUpload.swift`、`SleepUploadView.swift` 和 `PhoneSleepData.swift` 历史字段注释。
- 更新上传测试、真机联调测试调用及账号/自测 UI 测试，以及版本配置。

## 验证

- 完整单元测试 246 项，0 失败，1 项按原有条件跳过。覆盖旧 AIS 本地保存兼容、手动/自动上传 JSON 不含 AIS/ISI、旧响应字段忽略和 PSQI 原计分规则。
- 小屏模拟器完整答完 18 项，逐题核对插画存在，结果页和既有 24 音色播放/停止检查通过。深色无障碍大字体及上一题返回也通过。
- 界面测试发现固定底栏遮挡位置不适合按元素中心点击，已按实际可见区域滚动后再答题；同步状态的读屏容器标识也补齐，避免被外层标识覆盖。
- 账号登录后新增睡眠记录、自动同步状态、AIS 输入及旧上传按钮不再出现的界面回归在修正读屏容器后通过。初次运行的两处界面定位失败已复测解决，未把失败结果算作通过。
- 普通工程模拟器与戒指工程 generic iOS arm64 无签名构建通过。界面截图位于 `docs/screenshots/v053/`，使用明确的测试答案，不表示真实健康结论。
- 本次未覆盖安装手机，未部署 Web；不需要新增服务端接口或数据库迁移。

## 使用与运行

Xcode 打开 `sleeptongshu.xcodeproj`，选择 `sleeptongshu` scheme 运行；戒指版工程及 scheme 为 `sleeptongshu-Ring`。在“科普 → 自测 → PSQI 睡眠自测 → 开始睡眠自测”查看新答题界面。无需后端配置，旧健康与设备功能保持原有接口。
