# 登录后闪退修复

## 原因

2026-11-18 从测试 iPhone 读取到五份同类崩溃记录，均为 `EXC_BAD_ACCESS / objc_retain`，调用栈进入 `WearableProbeWorker.localSleep(_:)`。登录成功进入主页面后，会自动分析本机已保存的 BIO 历史；因此表现为登录即退出，并非密码验证失败。

已找到与崩溃 UUID `DAAD790B-CE45-3533-8ED3-724EA3C8AB10` 一致的普通工程构建。其编译参数没有 `-fobjc-arc`，戒指工程则启用了 ARC。旧桥接在内部 `@autoreleasepool` 中直接返回自动释放的 `NSData`，普通工程中对象在 Swift 接收并 retain 前已经销毁；错误输出也存在跨池生命周期风险。

## 修改

- `Configuration/IwownSleep.xcconfig`：共享配置启用 `CLANG_ENABLE_OBJC_ARC = YES`，覆盖普通工程 Debug/Release，戒指工程沿用相同要求。
- `sleeptongshu/BIOLocalSleepBridge.mm`：编译时拒绝非 ARC 配置；在池外以强引用持有结果和错误，退出池之后才返回和赋值错误输出。保留串行调用、阶段数组 `delete[]`、异常处理和真实结果校验。
- `scripts/tests/bio-bridge-lifetime.mm`、`scripts/test-bio-bridge-lifetime.sh`：使用替代引擎调用生产桥接，开启 AddressSanitizer，覆盖结果、空结果、错误、Objective-C/C++ 异常及非 ARC 编译失败。替代引擎仅用于 Mac 命令行测试，不进入 App，也不生成用户睡眠记录。

未修改账号契约、SwiftData 模型、睡眠分期算法或上传字段。覆盖安装保留本机数据，不通过清库规避崩溃。

## 验证

```sh
export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
bash scripts/test-bio-bridge-lifetime.sh
```

该测试需要先按 `BIO_LOCAL_SLEEP.md` 安装厂家头文件；不链接厂家二进制。1000 次成功返回、空结果和全部错误路径通过 AddressSanitizer 检查，非 ARC 构建被明确阻止。它验证桥接所有权，不代表运行过真实厂家算法。

普通工程模拟器 193 项单元测试通过，1 项因可选私有材料缺失跳过，0 项失败；普通及戒指 iPhone 签名构建通过。普通工程的实际编译参数已确认包含 `-fobjc-arc`。

在同一台 iPhone 上先覆盖安装普通工程修复版并启动，保持已有登录和数据库。自动恢复登录后，真实 BIO 历史分析返回成功：输入 5983 条，11 月 17 日返回 37 段阶段，诊断更新时间为本次安装之后。App 仍在运行，没有新增同类崩溃。随后再次启动检查进程仍存在，最后覆盖安装支持戒指的同一修复版本。

私人崩溃文件、接入报告和运行回执仅在忽略的 `work/` 中，不提交仓库。此次未新采集整夜蓝牙数据，也未验证后台长时间运行或重新手动输入密码登录；已验证的是先前实际崩溃的登录恢复后历史计算路径。

## 手机上检查

直接打开 sleeptongshu；需要时正常登录，保持前台等待已有睡眠更新。进入“睡眠 → 设备记录”选择已有日期。不要删除 App 来排查，因为卸载可能删除本机记录；如仍出现新的闪退，需核对新的崩溃时间与调用栈。
