# 第二版验证记录

日期：2026-10-26。环境：Apple Silicon Mac，Xcode 27.2，iOS SDK/模拟器运行时 27.2。

## 已完成

- 普通 scheme：iOS Simulator Debug 构建、iOS 通用真机 Release 无签名构建、Mac Catalyst 构建及启动。
- 健康 scheme：通用 iOS 无签名构建，确认生成的 Info.plist 健康开关为 YES；不等同于真机 HealthKit 描述文件验证。
- 11 项单元测试通过，覆盖原有 5 项及新增 6 项：旧版无元数据 JSON、连续/中断/缺失手机窗口、手机备份与持久化、无虚构分期及体征、异常窗口拒绝、健康区间冲突与缺口、稳定 ID、8/16 位标准心率数据。
- 真正从 `v0.1.0` 编译并运行 App，在 iPhone 18 Pro 模拟器生成 30 条旧结构记录；覆盖安装第二版，数据库自动增加可选元数据列，30 条旧记录保留，ID、分期、心率数据逐条一致。
- iPhone 17e（390 × 844 点）与 iPhone 18 Pro（402 × 874 点）实际渲染截图检查。检查手机入口、穿戴入口、报告示例；没有用网页模型代替 App 截图。
- 确认本机 Apple SoundAnalysis version1 分类器包含 snoring 和 speech 标识。此检查不代表声音分类准确率评估。

## 未完成或受限

- UI 自动化：模拟器测试停在启动阶段；Mac Catalyst 明确返回 `Timed out while enabling automation mode`，测试 runner 未初始化成功。本机 Developer Tools 安全状态显示 developer mode disabled。未将这些测试记为通过；未修改系统安全设置。测试代码已加入双模式与报告图表操作，需在可用环境重跑。
- 尚未完成真实 iPhone 整夜采集、锁屏/后台连续性、耗电、温度、来电与音频路由变化测试。
- 没有真实鼾声/说话标注数据集，未验证准确率；手机睡眠规则为透明的实验性信号启发式方法。
- 未在授权后的真实健康数据库执行导入；HealthKit 签名、来源选择、权限拒绝/撤销和多设备样本仍需真机验收。
- 未验证任何具体厂商手环/戒指的睡眠同步。标准 BLE 心率解析有单测，物理设备通知仍待测试；专用历史睡眠协议尚未实现。

## 重跑命令

```sh
# 数据单测，无需 UI 自动化控制权限
xcodebuild -project sleeptongshu.xcodeproj -scheme sleeptongshu \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -only-testing:sleeptongshuTests CODE_SIGN_IDENTITY=- ENABLE_HARDENED_RUNTIME=NO test

# UI 测试需要本机测试工具能够启用自动化，并将名称改为实际模拟器
xcodebuild -project sleeptongshu.xcodeproj -scheme sleeptongshu \
  -destination 'platform=iOS Simulator,name=iPhone 17e' test
```

测试使用内存数据库，不删除正常安装的睡眠记录。手机整夜测试流程与功能边界见 [V2.md](V2.md)。
