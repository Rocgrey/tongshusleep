# 账号与平台接口约定：0.3.4（18）

> 历史设计，已由 [0.3.5 实际后端对接](AUTH_BACKEND_V035.md) 取代。当前使用邮箱登录、snake_case 响应、注册后返回登录，不再按本文早期草案联调。

## 当前状态与交接

目标 Web 仓库：https://github.com/Rocgrey/sleep_tongshu_web 。2026-11-06 检查时该仓库为空；用户确认平台尚未部署。本文是 iOS 已实现的接口约定，供 WorkBuddy 实现服务端，不表示线上接口已经存在。没有部署地址时，App 显示登录、注册界面与“预览本机功能”，不会注册本地假账号，也不会向 GitHub 发送密码或健康信息。

平台配置就绪后，App 启动先检查登录。用户通过注册或登录获得会话，才能进入业务页面；已保存且未到期的会话需要通过 `/auth/me` 校验。登录到期或被撤销返回登录页。本版不实现刷新令牌，过期后重新登录。未配置服务时的本机预览入口在配置服务后消失。

## 部署与 Xcode 配置

部署一个可访问的 HTTPS API，将 Xcode 用户定义构建设置 `SLEEP_API_BASE_URL` 设置为真实 API 前缀，例如 `https://api.example.com/api/v1`。它通过 `Configuration/AppInfo.plist` 的 `SleepAPIBaseURL` 进入 App；不要填 GitHub 仓库地址。暂未配置时保持空值即可；手机和模拟器均不允许明文 HTTP、URL 用户名密码、查询参数或片段。服务端直接响应最终 URL，不重定向。

如果配置写入 `.xcconfig`，使用 `https:/$()/api.example.com/api/v1`，避免 `//` 被当作注释。也可以直接通过 Xcode 的 Build Settings 填完整 URL。配置值属于部署地址，不应包含 API 密钥或管理员凭据。

## 数据结构

请求与响应都是 JSON，键名使用 camelCase。时间用 UTC ISO 8601，可带毫秒。响应不加 `data` 包装。用户 ID 必须由服务器生成并稳定唯一。

账号：3～32 位小写英文字母、数字、下划线；大小写不敏感，App 提交前去除两端空白并转小写。密码：8～128 个字符，不裁剪、不转大小写。昵称选填，最多 40 个字符。服务端必须独立执行相同验证。

用户对象 `AccountUser`：

```json
{
  "id": "server-generated-user-id",
  "username": "sleeper",
  "displayName": "同书",
  "createdAt": "2026-11-06T08:00:00Z"
}
```

会话对象 `AccountSession`：

```json
{
  "user": {
    "id": "server-generated-user-id",
    "username": "sleeper",
    "displayName": "同书",
    "createdAt": "2026-11-06T08:00:00Z"
  },
  "accessToken": "opaque-random-example-token",
  "expiresAt": "2026-11-13T08:00:00Z"
}
```

示例令牌仅表示格式，不是真实凭据。令牌不得含空白。有效期由服务器设置并验证，App 不自行延长。建议首版不超过 7 天。

## 接口

| 方法 | 路径（相对 API 前缀） | 请求 | 成功响应 |
| --- | --- | --- | --- |
| POST | `/auth/register` | `{ "username": "sleeper", "password": "...", "displayName": "同书" }` | 201 + AccountSession；创建账号并登录 |
| POST | `/auth/login` | `{ "username": "sleeper", "password": "..." }` | 200 + AccountSession |
| GET | `/auth/me` | `Authorization: Bearer <accessToken>` | 200 + AccountUser |
| POST | `/auth/logout` | `Authorization: Bearer <accessToken>`，无请求体 | 204，无响应体；撤销本次会话 |

响应应使用 `Cache-Control: no-store`。当前没有验证码或短信接口，因此不需要手机号，不要在 Web 端强制增加未约定的手机号字段。

## 错误处理

| HTTP 状态 | 意义 | App 行为 |
| --- | --- | --- |
| 400 / 422 | 输入不合法 | 原页提示服务响应未能处理；用户可修改后重试 |
| 401（注册/登录） | 账号或密码不正确 | 原页提示，不进入业务页面 |
| 401（已有令牌） | 会话到期或撤销 | 清除本机会话，返回登录 |
| 409 | 账号已存在 | 原页提示换账号或改为登录 |
| 429 | 请求过于频繁 | 原页提示稍后再试 |
| 5xx / 网络故障 | 服务暂不可用 | 显示重试提示，不伪装登录成功 |

错误体可以使用 `{ "code": "USERNAME_TAKEN" }`；首版 App 按状态码给出固定通俗文案，不把服务器堆栈或内部原始信息显示给用户。服务器应统一登录失败响应，避免泄露账号是否存在。

## 平台中可见的信息

注册由服务器写库，所以未来平台可显示用户 ID、账号、昵称、注册时间、登录时间和账号状态。平台用户列表属于服务端管理员接口，本 App 不持有管理员密钥。服务端保存经 Argon2id / bcrypt 等成熟库处理的带盐密码哈希，任何列表、接口、日志都不得返回明文密码或密码哈希。

令牌在 App 中只保存到系统钥匙串，使用 `WhenUnlockedThisDeviceOnly`；不保存密码，不把令牌写进普通 JSON、偏好设置或仓库。服务端必须校验令牌身份、过期时间和撤销状态，并限制注册登录频率。上线前平台还需要补全密码找回、账号删除与隐私政策；这些功能当前不应假装可用。

## 健康记录与账号的边界

本轮账号接口不包含健康数据上传。睡眠、体征与 HealthKit 快照仍保存在当前手机，本机记录不会自动绑定或上传到新注册的账号。退出或切换账号保留本机记录，账号页明确说明。

未来若要平台查看健康记录，需要先实现按账号隔离的数据归属、用户主动开启的同步、上传与删除接口，再与 iOS 对接。不要把本机历史记录静默归到新登录的另一个账号，也不要将“注册信息可见”误解为“健康数据已同步”。

## iOS 实现与测试

- `AccountAPI.swift`：HTTPS JSON 请求、时间解析、错误映射；生产请求拒绝重定向。
- `AccountStore.swift`：钥匙串、恢复、到期检查、注册登录退出；配置为空时预览不保存会话。
- `AccountView.swift`：启动登录页、注册页、账号页；失败留在当前页，输入密码提交后清空。
- 自动化测试使用内存模拟服务和测试令牌，不访问线上平台、不写真实账号。只有 DEBUG 且带 UI 测试参数才能启用模拟账号服务。

接好平台后仍须联调：手机注册 → 平台数据库看到同一用户 → 退出 → 重新登录 → 杀进程恢复 → 服务端撤销令牌后拒绝登录。本文中的测试通过不能代替真实部署后的联调。
