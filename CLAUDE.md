# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Maco Power Monitor 是 macOS 状态栏电源监控工具，SwiftPM 可执行包（无 Xcode 工程文件），Swift 6.2 工具链，目标 macOS 13+ / Apple Silicon `arm64`。以 `LSUIElement` 运行，无 Dock 图标、无主窗口，全部 UI 通过 `NSStatusItem` + 常驻 `NSPanel` 承载。UI 文案与日志均为中文。

## 常用命令

```bash
swift build                 # Debug 构建
swift run                   # 直接运行（状态栏出现图标）
swift build -c release
swift test                  # 见下方“测试环境限制”
swift test --filter PowerHistoryEngineTests/testAggregatesMinuteBuckets   # 单个测试
```

打包链（脚本之间有依赖关系，版本号唯一来源是 `AppConstants.appVersion`，脚本用 `awk` 从 `Sources/MacoPowerMonitor/Support/AppConstants.swift` 提取）：

```bash
./scripts/package_app.sh                # release 构建 → dist/MacoPowerMonitor.app（含 Info.plist + ad-hoc 签名）
./scripts/build_dmg.sh                  # 默认先调 package_app.sh；SKIP_PACKAGE_APP=1 可跳过
./scripts/build_portable_executable.sh  # 单文件 Mach-O → dist/MacoPowerMonitor-v<版本>-macos-arm64
./scripts/build_release_assets.sh       # 串起以上三者 + ZIP + sha256 → dist/releases/
```

脚本环境变量：`SKIP_BUILD=1`、`SKIP_PACKAGE_APP=1`、`MACO_BUILD_TRIPLE`、`MACO_DISABLE_SWIFTPM_SANDBOX=1`、`SDKROOT`。

## 测试环境限制

当前机器只有 Command Line Tools（`xcode-select -p` → `/Library/Developer/CommandLineTools`），没有可导入的 XCTest，`swift test` 在测试 target 报 `no such module 'XCTest'`。这是环境限制，不是源码错误；生产 target 的 `swift build` 正常通过。测试源里的条件编译外壳已被刻意移除，避免出现“零测试绿灯”，所以**不要**为了让 `swift test` 通过而重新加回 `#if canImport(XCTest)`。完整套件必须在带完整 Xcode 的环境补跑。

编译器为 Swift 6.3.3（默认 target `arm64-apple-macosx26.0`）。如需复现交接文档记录的固定 SDK 构建：

```bash
env SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
  swift build --disable-sandbox \
    --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
    --triple arm64-apple-macosx13.0
```

没有 XCTest 时，运行期行为靠内置自检钩子验证（`AppDelegate.applicationDidFinishLaunching` 读取）：

```bash
MACO_POWER_MONITOR_SELF_TEST=background-keepalive swift run       # 打印结果后自动退出
MACO_POWER_MONITOR_SELF_TEST=launch-at-login-roundtrip swift run  # 仅 .app 内有效，否则 SKIPPED
MACO_POWER_MONITOR_SELF_TEST=quit swift run                      # 验证退出路径
MACO_POWER_MONITOR_DEBUG_WINDOW=1 swift run                      # 启动后自动展开面板
MACO_DEBUG_PANEL=1 swift run                                     # 打印多屏定位诊断
```

## 架构

数据流（单向，采集永不回调视图层）：

```text
SystemPowerSnapshotCollector (IOKit / system_profiler / ps)
        │  Task.detached
        ▼
PowerMonitorStore  @MainActor ObservableObject  ← 唯一 @Published 真源
        │  bounded AsyncStream(capacity 120)
        ▼
PowerHistoryEngine  actor
        ├─→ 分层 JSONL 落盘（磁盘 = 历史真源）
        └─→ HistoryProjection（仅面板可见时按需生成）
```

- `PowerMonitorStore.shared` 是全局单例，`AppDelegate` 与 `ContentView` 都消费它；`live()` 组装真实依赖，测试用 `init(...)` 注入假实现并可 `startsScheduler: false`。
- 采集节奏由 `RepeatingTaskScheduler`（1 秒，`DispatchSourceTimer` + leeway 容忍）驱动，不用 `Timer`，以降低唤醒开销。
- 面板是常驻轻量 `NSPanel`：显示时先 `orderFront` 再异步挂载 `NSHostingController<ContentView>`，关闭时换回占位 VC 并清空 `chartSeriesByMetric` / `topProcesses` 释放内存。

### 面板刷新预算（产品硬约束）

`beginPanelPresentation(openedAt:)` 以真实 `orderFront` 时间为 T0，用 `withTaskGroup` 并行跑三件事——IOKit 快照、`ps` 进程排行、磁盘历史投影——完成一项发布一项。**350 ms 是数据预算，400 ms 是硬截止**；超时取消任务组并拒绝迟到结果，保留上一批缓存值。`panelRefreshGeneration` / `projectionTaskGeneration` 两个代次计数器保证关闭面板后的旧任务不会回写新面板。改动这条路径时不要引入同步的慢调用（`system_profiler` 已改为后台预热缓存，进程排行已从 ~630 ms 的 `top -l 1` 换成 ~30 ms 的 `ps`，因此当前按 CPU 百分比排序、`powerScore` 为 0）。

### 历史引擎

`Services/PowerHistoryStore.swift`（文件名沿用旧称，实际类型是 `PowerHistoryEngine` actor）负责聚合、保留、查询、迁移和持久化，位置 `~/Library/Application Support/MacoPowerMonitor/power-history/`：

| 层 | 粒度 | 保留 | 切片 |
|---|---|---|---|
| `raw/` | 1 秒 | 6 小时 | UTC 小时 |
| `minute/` | 1 分钟 | 24 小时 | UTC 小时 |
| `five-minute/` | 5 分钟 | 10 天 | UTC 日 |

- 聚合记录存 `sum/count`，跨桶查询用加权平均；查询按范围选层（1 小时→raw，24 小时→minute，10 天→five-minute）。
- 每 30 秒批量 append，不重写整份文件；异常退出最多丢最近约 30 秒待写数据（为降低写入量的明确取舍）。
- 目录 `0700`、文件 `0600`；原始记录只存时间、供电来源和六项图表指标，不落序列号等静态信息。
- 缺失/无效/乱序/队列丢弃的样本保持为空洞——**不补零、不插值、不估算**。
- 旧 `power-history.json` 首次启动经临时目录迁移并完整重读校验后才删除；JSONL 尾部残行截断，中间坏行隔离并保留其余有效记录。

### 目录职责

`Sources/MacoPowerMonitor/` 下 `App/`（状态栏生命周期、面板、图标渲染）、`Core/`（`PowerSnapshot` 及图表序列/枚举定义）、`Services/`（系统采集、历史、提权采样）、`Support/`（常量、路径、格式化、命令执行）、`UI/`（面板布局与复用组件）。新增系统采集逻辑放 `Services/` 并通过协议注入，不要写进 `UI/`。

## 不可违反的设计约定

- **不造数据。** 拿不到的指标显示为未知并说明原因，不用推测值填补界面。这是项目的核心承诺，`CONTRIBUTING.md` 明确拒绝此类 PR。
- **三种功率概念不可混用。** 适配器协商额定（`adapterWatts`）、Mac 侧实时输入（`adapterRealtimePowerWatts`）、电池流向（`batteryPowerWatts` / `batteryFlowWatts`）是不同东西，UI 与图表必须分开呈现。macOS 不公开墙插侧损耗。
- **PowerUI 是私有 API，只读。** `ChargeLimitStatusProvider` 全部 selector 运行期检查。macOS 26 上从 Swift 协作线程调用 `PowerUISmartChargeClient` 会触发 Objective-C 释放崩溃，因此真实读取固定在主队列预热任务，后台快照只读纯 Swift 的 `ChargeLimitStatus` 缓存——不要把 PowerUI 对象跨线程传递，不要加入写系统电源策略的 selector，必须保留 IOKit 回退路径。
- **`powermetrics` 只在用户显式授权后采样**，且不计入 400 ms 预算（面板先显示最近缓存值）。不要改成默认后台持续提权。
- **`build_portable_executable.sh` 有符号门禁**：产物中出现 `PowerHistoryStore` / `prunedHistory` / `chartBuckets` 会构建失败，缺少 `PowerHistoryEngine` 也会失败。重命名或重构历史引擎时要同步更新该检查。产物还必须是纯系统依赖（`otool -L` 只允许 `/System/Library/` 与 `/usr/lib/`）。
- 涉及采样、历史存储或后台任务的改动，需记录改动前后的内存、CPU 唤醒和磁盘写入量。

## 陷阱

- **`package_app.sh` 每次都会跑 `scripts/generate_brand_assets.swift`**，无条件覆盖 `Assets/Brand/AppIcon.iconset/*.png`、`AppIcon.icns`、`VolumeIcon.icns`、`dmg-background.png` 和 `docs/images/app-icon.png`。`HANDOFF.MD` 记录用户手改过其中四个图片文件，打包后提交时要逐个确认，不要误纳入或覆盖。
- **`ORIGIN/MacoPowerMonitor/` 是带独立 `.git` 的旧快照**（含自己的 `.build`/`dist`），不是活跃代码。所有改动都在仓库根的 `Sources/` 下进行。
- **版本号只改 `AppConstants.appVersion`**（当前 `0.4.0`），打包脚本与 Info.plist 都从它派生。README 里的下载链接仍写 `0.3.0`，发布前需要一并更新。
- **`HANDOFF.MD` 在 `.gitignore` 里但内容关键**：记录当前分支状态、已验证项、性能实测数字和待办风险。接手前先读它。
- 测试新构建前先退出旧版应用实例，否则旧进程可能继续重写 `power-history.json`，干扰迁移判断。
