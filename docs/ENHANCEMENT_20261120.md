# 睡眠同书增强版

后续 0.4.1 已按所有者要求移除本机试看限制，直接完整播放提供的视频，加入已核实京东商品并优化同步性能。当前行为以 `RELEASE_V041.md` 为准；下文 60 秒限制和商品未核实描述保留为 0.4.0 的历史记录。

## 版本保护与项目

本文记录增强功能的隔离开发过程。用户随后确认作为原 sleeptongshu 的 0.4.0（21）升级，已整合回 main 与原工作区，使用原 Bundle ID 原位安装；不是独立 App。当前交付与 WorkBuddy 部署步骤以 `RELEASE_V040.md` 为准。仍不部署线上服务、不操作生产数据库。

| 项目 | 本地绝对路径 | 分支 | 增强前基线 / 稳定标签 |
|---|---|---|---|
| iOS | `/Users/ts/Documents/Codex/2026-10-23/tongshusleep-enhanced` | `codex/native-sleep-enhancement-20261120` | `19f6f89e` / `stable/pre-enhancement-20261120` |
| FastAPI / Web | `/Users/ts/Documents/Codex/2026-10-23/sleep-tongshu-web-enhanced` | `codex/native-content-enhancement-20261120` | `891aef31` / `stable/pre-content-enhancement-20261120` |
| 原工作区 | `/Users/ts/Documents/Codex/2026-10-23/app-10pro-app-ios-app-app` | 原分支保持不变 | 两个工程文件的原有未提交改动及原截图均未覆盖 |

上表为最初隔离开发的工作区与基线，不是不同产品。当前 iOS 主工作区为 `/Users/ts/Documents/Codex/2026-10-23/app-10pro-app-ios-app-app`，两个仓库均以 main 交付。
原工作区的跟踪文件补丁另存于忽略目录 `work/pre-enhancement-user-project-edits-20261120.patch`，原有两个工程设置与截图保持未提交，不混入版本提交。最终提交以各仓库 `git log -1` 为准。

## 页面映射

已阅读本机 `classroom-preview/classroom-preview.html`、`palm-sleep-site 2` 的文章、课程与素材，以及 `API_FOR_APP.md`。
没有连接 SSH、修改腾讯云文件或使用云服务器密码。

| 原栏目 / 内容 | App 模块 | 入口 | 内容接口 |
|---|---|---|---|
| 睡眠科普文章 | 原生阅读列表、文章正文、每日阅读 | 睡眠首页 / 课堂 → 阅读 | `GET /api/v1/content/items?kind=article`、详情 |
| 系列视频与科普视频 | 课程封面、详情、章节、原生播放器、本机进度 | 课堂 → 课程 | 列表、详情，章节通过 `parent_id` 关联 |
| 晚安内容 | 原生晚安卡 | 睡眠首页 / 课堂 → 助眠 | `kind=goodnight`，无已发布条目时使用 App 自带晚安文案 |
| 放松内容 | 4-7-8 呼吸、白噪音、已发布助眠内容 | 课堂 → 助眠 | `kind=breathing/noise`；内置呼吸与白噪音无需服务 |
| 商品介绍 | 已核实商品列表及外链 | 课堂 → 产品 | `kind=product`；当前明确空状态 |
| 内容通知 | 本地提醒 / 可选 APNs 与路由 | 设置 → 提醒 | `notifications/preferences`、`notifications/devices` |

网页不再作为主要界面，也不把页面塞进 WebView。原五个 Tab 保留；新增能力放入现有入口。

## 阶段状态

- [x] 稳定版本标签、独立分支、素材和接口盘点、共享外观变量。
- [x] 原生课程、文章、章节、视频、按服务和稳定 user ID 隔离的学习进度。
- [x] 内容后台、增量表、发布条件、分页、草稿预览、下架和管理员操作记录。
- [x] 本地提醒、远程推送客户端 / 后台代码、晚安卡、呼吸和定时白噪音。
- [x] 主动同意后的本地分段语音、筛选、回听、定位、删除、分享和存储限制。
- [x] 商品外链和复制能力；未核实商品不发布。
- [ ] 生产部署、生产数据库变更、APNs 配置与实际投递。
- [ ] 真机整夜录音、锁屏控制、来电中断和本人账号短信 / 邮件实际收取。
- [ ] 核实两个京东短链的具体商品、正式使用的素材权利及需要受限课程的授权。

## 内容与缓存

随 App 打包的是从所提供项目提取的 5 篇文章、3 组课程及 7 个视频条目，共 15 条真实源内容，不是虚构测试课程。
封面直接来自用户提供的 `assets/kepu`、`assets/video`。导入脚本记录在 `scripts/import-classroom-assets.py`，不抓取服务器私有文件。
原站第一讲完整开放，其余课程 / 科普视频保留 60 秒试看。没有新增购买、会员或绕过原平台付费授权。

实际视频使用业务域名 `vid.sleep.phoenixtreeai.com`，文件路径来自原站代码；不使用 CNAME 拼视频路径。
第一讲已通过真实 HTTP HEAD 确认 MP4，未下载大型视频文件。其他视频播放及版权仍应由内容管理员发布前逐项确认。
不向媒体服务器发送 App JWT、HealthKit 数据或设备原始包。私有媒体如需要新的签名/授权接口，应在服务端实现后另行接入，不能直接公开私有存储桶或发布永久签名地址。

课堂首次进入和首页按 15 分钟策略刷新，支持下拉手动刷新、分页、本地缓存、断网提示和空状态。
缓存按服务地址隔离；学习进度另按服务 + user ID + 章节 ID 隔离。
新内容接口尚未部署时显示明确标注的随 App 内容。收到任一服务端目录后，以服务端目录为准，空目录不会恢复内置课程；详情或播放前的 404 会移除该条目，不用内置内容代替下架结果。

## 账号找回

线上 OpenAPI 与 Web 基线已确认：

```text
POST /api/v1/auth/password-reset/request
{ "phone": "注册手机号" } 或 { "email": "注册邮箱" }
返回 request_id / expires_at(UTC Unix 秒) / retry_after / message

POST /api/v1/auth/password-reset/confirm
{ "request_id": "...", "code": "六位数字", "new_password": "..." }
返回 message
```

仅发送一种联系方式，不带 Bearer，不伪造邮箱。密码和验证码只在内存中，页面退出清空。
客户端验证密码一致、长度、验证码、有效期和重发冷却；错误展示服务端提示，不把请求成功当作收信成功。
重置成功返回登录，不创建新用户，不改原稳定 user ID。服务器沿用 token_version 使原凭证失效。
`Configuration/Service.xcconfig` 配置 baseURL；真实网关分享码只在忽略的 `ServiceLocal.xcconfig`。
网关要求每个 API 请求携带配置的查询参数，因此统一 APIClient 已补齐；不把该参数发给视频域名。

## 外观和音频

设置 → 通用 → 外观：商务、清新、可爱，共用页面与设计变量，主题持久化，保留统一睡眠分期语义颜色。
系统深浅色、动态字体继续生效；大字号课程切单列，呼吸页可滚动，减少动态效果设置生效。

4-7-8 为 4 秒吸气、7 秒屏息、8 秒呼气，可开始、暂停、结束。不适请停止，不作治疗承诺。
白噪音为本机程序生成的 6 秒短循环，没有外部音源授权或大下载问题。默认 30 分钟，可选 5/15/30/45/60/90 分钟，最后 10 秒渐弱至停止。
页面退出不销毁播放服务，暂停不延长原截止时间，支持锁屏播放 / 暂停及中断后手动继续。
统一音频协调器使课程、片段和白噪音互斥；手机监测会先停止播放，监测期间不开始其他播放。
当前不支持录音与白噪音同时使用，所以不会把本 App 播放的声音识别为候选梦话。

## 夜间语音隐私与限制

先打开手机监测中的“保存候选语音”，阅读同意提示，再主动开始监测。关闭该项仍保留原有声音 / 体动分析，不保存片段。
麦克风音频按约 15 秒分段；只保留本机 SoundAnalysis 对语音置信度 ≥ 75% 的候选段，其余丢弃。
这不是梦话鉴定，也不能识别人。回听页显示时间、时长、置信度和来源，可拖动定位、删除和主动分享。
与本机睡眠记录按时间重叠标注，不据此生成深睡、浅睡、REM 或疾病结论。
默认 7 天 / 200 MB；低空间停止语音保存而继续原有监测，异常退出产生的临时孤立文件可清理。
片段使用文件保护；没有加入上传请求或服务器同步。退出账号不删除共享手机本地记录，需设备主人在本机管理。
后台音频声明与麦克风用途已配置。锁屏、电话、蓝牙音频切换和整夜耗电需真机验收，系统强制终止后不能承诺继续采集。

## 通知

两个提醒开关及各自时间可设置。默认用本地通知，未来两周的每日内容尽量不重复，打开 App 时续排；睡前提醒为每日重复。
锁屏只放普通提醒文案，不放个人健康结论。没有数据时不编造睡眠质量提示。
若选择远程模式，不再安排重复本地通知；需要有效推送能力、设备 token、服务器配置及后台排程全部就绪。
token 注册/变化/注销复用 JWT API。退出先清空本机会话，再用捕获的原 token 尝试注销设备与服务端登出，断网不阻塞本地退出。
通知和 URL 路由使用白名单，登录后继续原目标；内容不存在/下架回退晚安入口。

`Configuration/APNs.example.entitlements` 只是模板，尚未修改两个正式 target 的 HealthKit entitlement 或强行启用推送。
需付费开发者账号、Push Notifications App ID 能力、正确描述文件，并把 aps-environment 合并到实际签名 entitlements。
后端需要 APNS_KEY_ID / APNS_TEAM_ID / APNS_TOPIC / APNS_PRIVATE_KEY_PATH，密钥文件不放仓库。
远程 worker 为独立可审查进程，发布内容不会自动启动 worker 或发送通知。

## 构建与验证

```sh
export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
open sleeptongshu.xcodeproj
xcodebuild -project sleeptongshu.xcodeproj -scheme sleeptongshu \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
# 厂家 SDK 在忽略目录，由原有 setup 脚本配置；戒指真机工程：
xcodebuild -project sleeptongshu-Ring.xcodeproj -scheme sleeptongshu-Ring \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

模拟器测试使用现有显式 `-ui-testing` 测试记录，不宣称采到真实睡眠。
普通模拟器构建、戒指真机目标无签名构建、单元与新增界面测试见 `VALIDATION_ENHANCED.md`。
初始隔离验收没有覆盖安装手机；后续用户已要求原位升级，版本号、签名与安装核对见 `RELEASE_V040.md`。

## 后端部署前必须审查

Web 分支交付文档：`docs/NATIVE_CONTENT_ENHANCEMENT.md`。
生产暂未包含新内容接口，App 当前不会把本地内容伪装成线上发布结果。
新表共 6 张：content_items、content_audit、push_devices、notification_preferences、push_plans、push_deliveries。
部署会沿用原有启动迁移/create_all，因此必须先备份生产库并审查，再执行；本次仅在独立本地数据库运行。

发现上游已有凭据默认值，本次删除代码中的真实密码/签名密钥默认值，改为环境配置。
**旧仓库历史中的值没有因本次删除而消失，应由平台管理员轮换 JWT 签名密钥、管理员密码、邮件授权和云备份凭据。**
没有擅自改写既有 Git 历史，也没有修改线上配置。轮换 JWT 密钥会使旧会话失效，需事先安排。
