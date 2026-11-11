# 给 WorkBuddy：部署 BIO 原始数据接收服务

以下内容可以直接作为任务提示词。

---

请直接在 https://github.com/Rocgrey/sleep_tongshu_web.git 的现有 FastAPI 服务上开发和部署，不另建不兼容平台。先拉取 main 最新代码，保留账号/JWT、睡眠、步数、设备自动同步、BIO 云算法接口及已有数据库。iOS App 仓库是 https://github.com/Rocgrey/tongshusleep.git，不要混淆。

目标：让厂家 Android 测试 App IWBle（截图版本 1.30.0626）及我们的 iOS App 上传 BIO-7349 的原始传感器包，服务端可靠保存，网页能够查看和下载。用户确认 IWBle 有服务器地址设置；请部署成功后返回可填写的完整 HTTPS 地址和具体填写步骤。

## 已有代码，优先部署和复用

- `app/schemas/raw_sensor.py`：原始包/批次校验和传感器编号表。
- `app/api/v1/raw_sensor.py`：JWT 上传、Android 专用上传、当前用户列表和详情。
- `app/models/models.py`：独立 `raw_sensor_batches` 表，启动自动建表，不清空历史。
- `static/index.html`：原始批次列表、包切换、包内原值图与下载 JSON。
- `tests/test_raw_sensor.py`：合成输入的接收、去重、账号隔离和权限测试。
- `docs/RAW_SENSOR_INGEST.md`：完整字段及限制。

## 事实与边界

厂家 `realtime_data.proto` 的明确枚举为：16=ACC（加速度）、512=BIOZ（生物电阻抗）、2=PPG（光学脉搏波）。不能把 512 标为 PPG。类型号可能是位标志；未知或组合值不能任意归成一种传感器。

每个 Android 解码对象为 `ProtoBufRealTimeData`，字段是 `sensorType/sensorSeconds/sensorSeq/sensorDataList`。它是 SDK 解码对象名，不证明网络上传就是 Protobuf 二进制。当前截图不含完整原始日志文件。

`sensorSeconds` 先保存为设备原始秒数，不擅自转换成 UTC 或推断采样率。数值是 32 位原始编码；Android 的 int 可能显示负数。保留数组原顺序和符号，不能删负数、按长度猜频率、直接按三轴拆分或换算物理单位。保存 `received_at` 与设备时间分别展示。

原始传感器信号不是睡眠分期。当前数据接收服务不根据这些值生成深睡、浅睡、快速眼动、睡眠评分或临床指标。厂家截图另有真实睡眠结果，需要分开接入。

## 固定接口

1. iOS：`POST /api/v1/health/raw-sensor-batches`，沿用 JWT Bearer。用户归属取认证用户，不接收 user_id。
2. Android：`POST /api/v1/device-ingest/iwble`，Header `X-Device-Ingest-Key` 为专用上传密钥，不是管理员密码。服务端环境配置 `IWBLE_INGEST_KEY`、`IWBLE_INGEST_USER_ID`、`IWBLE_INGEST_DEVICE_ID`，把该密钥固定绑定到一个现有用户和一个设备。默认未配置返回 503，不开放匿名写入。
3. 查询：`GET /api/v1/health/raw-sensor-batches` 及 `GET /api/v1/health/raw-sensor-batches/{id}`。当前用户只能查看自己的原始数据。
4. 旧设备快照、睡眠算法接口不改路径和 DTO。不把 raw 数据塞入睡眠结果表。

JSON 批次示例（明确为合成测试值）：

```json
{
  "upload_id": "synthetic-capture-001|0",
  "capture_id": "synthetic-capture-001",
  "device_id": "SYNTHETIC_DEVICE",
  "device_name": "BIO test only",
  "source": "iwble_android",
  "timestamp_encoding": "device_seconds_unverified",
  "packets": [{
    "sensorType": 16,
    "sensorSeconds": 1794390000,
    "sensorSeq": 37,
    "sensorDataList": [101, -1001, 201, 102, -1002, 202]
  }]
}
```

可选 `receivedAt` 为客户端收到包时的 UTC Unix 秒；`notificationBase64` 为 iOS 已校验的整条 RtNotification Protobuf 原文，不含 BLE 分帧头。Android 没有这两个字段时不要伪造。

同一用户+upload_id 同内容重试返回原记录，`applied=false`；同键不同内容 409。一次采集使用稳定 capture_id，重启采集换新 ID，避免设备序号归零发生冲突。批次间边界不能重叠，不能每次重试随机换 upload_id。

## 必须先核对 IWBle 实际网络行为

“有服务器地址设置”不等于它支持任意接口。请先确认设置是完整 URL 还是 Host、实际请求方法/路径/Content-Type、请求体和可配置请求头，以及该设置是否只影响睡眠算法服务。

如果 IWBle 发的是四字段对象、数组、包装 JSON、日志文本或二进制，请增加独立的 Android 格式适配层，保存原文后严格解析，转换为上述规范；不要改变 iOS 已实现契约。没有收到完整包就不能宣称解析成功。截图/OCR 不能当作原始数据导入依据。

如果它不能配置请求头，不要简单移除鉴权。请说明限制，再为它实现范围受限、可撤销的临时上传凭证方案，并避免访问日志记录凭证。用户只应拿到测试设备的上传权限，不能拿管理员 token。不要猜测它支持哪种鉴权。

HTTPS 网关必须允许该 API 的 POST 请求进入 FastAPI；不要返回分享页、登录 HTML、302 或“sharecode”网页作为上传成功。JSON POST 的地址不能用网站首页代替。

## 部署、验证和交付

- 先备份生产数据库，部署 main 最新提交并重启，确认新表创建且旧睡眠/步数不丢失。
- 配置专用上传密钥与真实用户/设备绑定，密钥只存服务器环境，不提交 GitHub，不在聊天或日志里公开。
- 跑 `python -m unittest discover -s tests -v`。通过 curl 测试真实 HTTPS 的 401、422、成功写入、重复请求不新增、同键冲突 409、另一用户不可读取。
- 在网页同账号看到服务接收时间、设备、传感器类型、包数及数据长度，能查看原值和下载 JSON。原始值不能冒充心率、血氧或睡眠阶段。
- 必须用 IWBle 实际发包完成一次联调；若只能完成 curl，清楚标注“IWBle 尚未联调”，列出缺少的请求格式/设置资料，不能用合成数据宣称真实设备接入成功。
- 将所有改动提交并推送到 `Rocgrey/sleep_tongshu_web`，返回 commit、线上验证结果和完整上传 URL。

预期上传 URL（只有部署并核对格式后才可使用）：
`https://tongshusleep-backend.app.workbuddy.host/api/v1/device-ingest/iwble`

不要只给一个地址；同时告诉我 IWBle 的地址输入框具体填什么、是否另外设置请求头及服务是否确实收到真实包。

附：现有公共算法账号使用真实设备 MAC 测试仍返回 10403“设备归属未确认”。厂家 IWBle 截图已显示 11 月 10 日 23:49 至 11 日 06:56 的分期，但无法仅凭截图判断结果由本地 SDK 还是云端产生。请核对 IWBle 实际睡眠调用、设备绑定和授权，不能假设演示平台账号等于算法服务已开通。
