# sleeptongshu 0.4.0 (21)

## 同一个 App 升级

- 显示名称继续为 `sleeptongshu`，Bundle ID 继续为 `com.rocgrey.sleeptongshu`，沿用原签名团队。
- 普通与戒指工程均为 `0.4.0`，构建号 `21`。没有第二套产品、账号或数据库。
- iOS 原工作区：`/Users/ts/Documents/Codex/2026-10-23/app-10pro-app-ios-app-app`，仓库 `https://github.com/Rocgrey/tongshusleep`，交付分支 `main`。
- Web 工作区：`/Users/ts/Documents/Codex/2026-10-23/sleep-tongshu-web-enhanced`，仓库 `https://github.com/Rocgrey/sleep_tongshu_web`，交付分支 `main`。目录名称只是工作目录，不是另一套后台。
- 原 WorkBuddy 服务继续使用 `https://tongshusleep-backend.app.workbuddy.host`，App 统一 API 前缀仍为 `/api/v1`。分享网关配置保存在被忽略的本机配置，不能写入文档或 Git。
- 功能说明见 `ENHANCEMENT_20261120.md`；自动化记录与截图见 `VALIDATION_ENHANCED.md`。

增强功能最初通过 codex 分支隔离开发，现按用户确认整合到两个原仓库 main。
旧版本保留 `stable/pre-enhancement-20261120` 和 Web `stable/pre-content-enhancement-20261120`，不修改旧标签。
`tongshusleep-enhanced` 只是原仓库的开发 worktree，可以保留作比较，不是另一个 App。

## 构建和原位安装

```sh
export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
open sleeptongshu-Ring.xcodeproj
# 选择 sleeptongshu-Ring scheme 和原 iPhone，保持原 Bundle ID / Team，再运行。
# 普通工程和单元测试：
xcodebuild -project sleeptongshu.xcodeproj -scheme sleeptongshu \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

厂家 SDK 沿用原有 setup 脚本和忽略的 Vendor 目录，不提交 SDK 或本机签名配置。
更新不得卸载旧 App，不改 Bundle ID，不删除沙盒；原 SwiftData、设备记录、账号 Keychain 和同步设置沿用。
本机已在忽略的 `work/private-phone-backup-v040` 保存安装前 Application Support 副本，仅用于本机恢复核查，不上传 Git。这不是包含 Keychain 和全部录音的完整设备备份。

## 给 WorkBuddy 的提示词

请在现有 `Rocgrey/sleep_tongshu_web` 仓库拉取最新 `main`，不要新建服务；继续部署到现有 WorkBuddy 地址，保留现有账号、健康数据、原始信号和后台功能。先阅读 `docs/WORKBUDDY_DEPLOY_V040.md`、`docs/NATIVE_CONTENT_ENHANCEMENT.md`，审查 diff 后按现有流程部署。

部署前备份实际生产数据库，确认原 DATABASE_URL、持久化目录、云备份和管理员配置。增加的六张表不应删除或重建旧表。SECRET_KEY 和 ADMIN_PASSWORD 已移除源码默认值，必须从平台私密配置提供，不能复制真实值回源码或日志；轮换历史暴露凭据需安排旧会话失效。

部署后核对密码找回、原账号登录、睡眠/步数/原始信号接口和内容管理；素材先幂等导入草稿，经管理员审核后发布，App 刷新即可显示。不要自动发布内容或顺带发送通知。APNs 仍需独立配置，不把未配置状态显示为发送成功。请反馈部署 commit、接口验证和数据保留结果。

## 本轮发布验证

- 原工作区普通工程：210 项单元测试，0 失败，1 项明确的线上写入测试按条件跳过。此工作区已有私有 BIO 样本，可执行此前隔离工作区跳过的本机样本测试；不提交样本或测试日志。
- 戒指工程：面向已连接 iPhone 的自动签名构建通过；已核对相同 Bundle ID、团队、HealthKit entitlement 和原 WorkBuddy 主机。
- 已原位安装并启动；手机安装清单确认 `sleeptongshu 0.4.0 (21)`，启动后进程仍在。
- 安装前后只在本机核对数据库：旧睡眠记录主键均保留。没有卸载、清空记录或更换数据库。
- 后端 main 工作区重新运行 118 项单元测试，全部通过。先前小屏幕、深色大字体和 Web 测试见 `VALIDATION_ENHANCED.md`。
- 上述安装/启动检查不等于整夜采集、真实验证码或 APNs 验收。

## 待真实联调

后台新内容接口尚未部署，App 会明确显示随 App 内容，不冒充线上发布。
真实短信/邮件收取、APNs、整夜录音、锁屏及来电中断仍需验收；京东两个短链未确认具体商品，不发布猜测商品。
线上部署和生产数据库操作交给 WorkBuddy，本机没有执行。
