# SleepGrove 0.5.4 (30)

基于 0.5.3 commit `4ab0d92a6dbfd05b7a8e57998b8f950714b3904a`，开发分支 `codex/result-course-visual-polish`。继续使用现有 App、账号、SwiftData 和平台内容接口。本机未提交的签名设置及旧截图独立保留。

## 使用变化

- 科普 → 自测 → PSQI：结果显示本机历史曲线、上次日期、总分变化和七个方面的前后分数。分数下降表示自述困扰减少，分数上升表示自述困扰增加，不将变化解释为一天内身体状态的变化。每次仍回顾近一个月，近期自测的覆盖期会重叠。
- 历史仅比较当前账号/服务地址下、同一计分版本、早于当前自测的记录；查看旧记录不包含未来的自测。图表最多展示截至当前的八次记录；首次说明没有可比较记录，不生成历史数据。变化以分数表达，前次为零也不会产生无效百分比。
- “咨询睡眠顾问”打开 `https://sleep.tongshugene.net/#contact`。已核对官网联系区及原自测模块中的 `#contact` 链接。该用户主动打开的网页不接收 App 的自测答案或账号数据；课程主体仍是原生页面。
- 科普 → 课程：每个系列下面直接列出所有已发布章节，每节有封面与播放入口。章节没有独立封面时沿用系列封面；没有视频地址时显示“视频正在准备”，不伪造视频。继续使用既有动态目录、发布/下架规则、完整视频、横屏及学习进度功能。
- 助眠 → 4-7-8 呼吸：从手机已安装的中文女声中选择，普通话优先，再按优质/增强/标准质量排序。适当放慢语速并调整停顿；4/7/8 秒阶段仍与原倒计时共用时钟。声音列表只在初始化或返回前台时刷新，不在每秒画面刷新时反复查询。
- 找不到中文女声时明确说明下载路径，不用男声冒充女声。标准声音可用时说明如何下载更高质量声音；不把系统合成语音描述为真人录音。自然程度取决于设备实际安装的声音，需在 iPhone 上试听确认。
- 掌心安睡仪：内嵌产品视频封面，点击播放，单独的全屏及横屏按钮。内嵌和全屏共用一个播放器及播放位置。视频地址是厂家实际提供的 `https://vid.sleep.phoenixtreeai.com/video/product-promo.mp4`，封面为既有 `palm-device-official` 资源。
- 视频首次加载前不自动请求媒体；离开页面、转入后台、音频中断或开始监测录音时停止播放。播放失败提供重试，不能抢占夜间录音。

## 统一视觉

- 新增 `GroveControls.swift`：主要按钮采用同色系细微渐变、两层柔和阴影及单像素内侧高光；按压缩至 0.98，悬停抬升 2pt，反馈为 180ms ease-out。没有常驻光泽循环或装饰动画。
- 主要/次要按钮、图像/列表按钮、内容卡片、商品及登录输入框复用同一套 8pt 圆角、细描边与层次规格。图像和列表按钮保留已有尺寸和语义，删除操作保留醒目颜色；禁用、加载与点击处理沿用原有逻辑。
- 保留商务/清新/可爱、系统深浅色和原睡眠阶段颜色，减弱动态效果时关闭位移与缩放；提高对比度时加粗细边框。浅深色主按钮所有渐变端点纳入文字对比度测试。
- Finesse 的网页 CSS/DOM 检查不适用于本项目原生 SwiftUI；对应使用 Xcode 构建、XCUITest、原生截图及颜色对比测试。未引入 WebView、第三方 UI 或动画框架。
- 保留睡眠采集、蓝牙、HealthKit、本机记录和自动同步；不恢复 AIS/ISI，也不改变后端契约。

## 文件

主要新增：`GroveControls.swift`、`PSQIComparison.swift`、`ResultPresentationTests.swift`、`ResultCoursePolishUITests.swift`。

主要修改：`PSQIView.swift`、`SleepClassroomView.swift`、`BreathingCue.swift`、`SleepRelaxation.swift`、`ProductIntroductionView.swift`、`GroveVisuals.swift`、`AccountView.swift`；其余现有页面仅替换共用按钮/输入样式。更新版本配置、颜色与 UI 回归测试及 Finesse 记录。

## 验证与配置

- 最终完整单元测试 253 项，0 失败，1 项线上写入测试按既有条件跳过。覆盖原睡眠、蓝牙、健康、上传与账号功能，以及新增历史对照、中文女声排序、录音抢占和重复播放不创建多个播放器。主按钮的三套主题及五种强调色在深浅色、两种背景上的渐变端点均通过 4.5:1 文字对比度检查。
- 普通工程模拟器构建及戒指工程 generic iOS arm64 无签名构建通过。现有依赖的非阻塞警告仍保留，不宣称零警告。
- iPhone SE 尺寸界面回归通过：逐节课程、原课程选集及横屏、产品封面/全屏/横屏返回、五分区导航、三套主题、健康年龄与体温测试图、大字体与深色模式、18 项自测、历史说明、顾问链接、24 音色播放和停止；登录/注册/个人资料/退出使用原测试后端完成回归。线上内容写入检查没有启用，未将模拟器目录当作线上内容联调。
- 顾问入口的测试初次误按普通按钮定位，已按其实际 Link 语义修正，完整自测与声音流程复测通过。
- 视频业务域名的实际资源返回 HTTP 200，类型为 video/mp4，支持 Range 请求；真机长视频播放、音频听感与设备中断仍需实际 iPhone 验收。
- 截图位于 `docs/screenshots/v054/`，均来自明确的 UI 测试与测试答案，不代表真实健康结论：[课程章节](screenshots/v054/course-chapters-test.png)、[产品内嵌视频](screenshots/v054/product-inline-test.png)、[产品大字体深色](screenshots/v054/product-dark-large-test.png)、[自测结果](screenshots/v054/psqi-result-test.png)、[自测历史](screenshots/v054/psqi-history-test.png)、[睡眠顾问入口](screenshots/v054/psqi-advisor-test.png)。

未覆盖安装 iPhone，未部署 Web；本次不需要新增接口、数据库迁移、云密钥或语音服务。课程封面和视频继续由已有内容后台发布后刷新。

Xcode 打开 `sleeptongshu.xcodeproj`，运行 `sleeptongshu` scheme；设备 SDK 工程为 `sleeptongshu-Ring.xcodeproj` / `sleeptongshu-Ring` scheme。开发工具路径为本机 `/Users/ts/Downloads/Xcode.app/Contents/Developer`，命令行可设置 `DEVELOPER_DIR` 后运行构建或测试。

真机重点：在“助眠 → 4-7-8 呼吸”试听女声与倒计时，必要时先从系统辅助功能下载中文高质量女声；检查耳机、扬声器、电话中断与录音互斥。在产品页面点击封面，检查画面、声音、全屏横屏、返回后的进度以及失败重试。模拟器界面/测试答案不表示真实健康结论。
