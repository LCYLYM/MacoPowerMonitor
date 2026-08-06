<div align="center">

<img src="docs/images/app-icon.png" alt="Maco Power Monitor icon" width="112" />

# Maco Power Monitor

Native macOS menu bar power monitor for Apple Silicon.  
面向 Apple Silicon 的原生 macOS 状态栏电源监控工具。

Real battery, adapter and power telemetry.  
真实电池、适配器与功耗遥测。

Compact glass panel. No fake data.  
紧凑液态玻璃面板，无虚拟数据。

[![Release](https://img.shields.io/github/v/release/LCYLYM/MacoPowerMonitor?display_name=tag&style=for-the-badge)](https://github.com/LCYLYM/MacoPowerMonitor/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/LCYLYM/MacoPowerMonitor/total?style=for-the-badge)](https://github.com/LCYLYM/MacoPowerMonitor/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-13%2B-1f6feb?style=for-the-badge)](https://github.com/LCYLYM/MacoPowerMonitor/releases/latest)
[![Swift](https://img.shields.io/badge/Swift-6.2-f05138?style=for-the-badge)](https://www.swift.org/)
[![License](https://img.shields.io/github/license/LCYLYM/MacoPowerMonitor?style=for-the-badge)](LICENSE)

[Download Latest Release](https://github.com/LCYLYM/MacoPowerMonitor/releases/latest) • [DMG Installer](https://github.com/LCYLYM/MacoPowerMonitor/releases/latest/download/MacoPowerMonitor-v0.3.0-macos.dmg) • [Portable Executable](https://github.com/LCYLYM/MacoPowerMonitor/releases/latest/download/MacoPowerMonitor-v0.3.0-macos-arm64.zip) • [ZIP Package](https://github.com/LCYLYM/MacoPowerMonitor/releases/latest/download/MacoPowerMonitor-v0.3.0-macos.zip) • [Report Bug](https://github.com/LCYLYM/MacoPowerMonitor/issues/new?template=bug_report.md) • [Request Feature](https://github.com/LCYLYM/MacoPowerMonitor/issues/new?template=feature_request.md)

<img src="docs/images/6.png" alt="Maco Power Monitor poster" width="420" />

</div>

---

## English

Maco Power Monitor is a lightweight macOS status bar utility that helps you understand where your battery and power budget are going in real time.

It focuses on three things:

- Real system data only
- Low overhead native menu bar UX
- Dense, readable power insights without fake precision

### Preview

<p align="center">
  <img src="docs/images/overview.png" alt="Overview screenshot" width="380" />
  <img src="docs/images/charts.png" alt="Charts screenshot" width="380" />
</p>

### Why It Feels Different

- Native all the way: built with `SwiftUI + AppKit + IOKit`, no Electron, no embedded browser runtime
- Real metrics only: battery, adapter and process-energy data come from macOS system interfaces and commands
- Compact by design: click the menu bar icon, inspect what matters, dismiss and move on
- High signal UI: system input, battery output, recharge flow, current, battery health and top energy users in one place
- Honest constraints: when a metric needs admin permission or cannot be read reliably, the app says so instead of inventing numbers

### Highlights

| Feature | Why it matters |
| --- | --- |
| Live menu bar battery indicator | Show the exact battery percentage and a continuously filled battery icon, including real charging progress |
| Compact glass panel | Feels native to macOS and stays out of the way |
| Formal app icon and DMG installer | Drag-to-Applications setup that feels ready for public release |
| Multi-select chart toggles | Show `Power`, `Battery`, and `Current` together |
| Adapter protocol and live power | Show USB PD / Apple private / QC only when macOS exposes evidence, together with live Mac-side input watts |
| Adapter power-time curve | Persist and chart live adapter input power at 1-second sampling with long-range downsampling |
| Bidirectional power view | Separate `Adapter Live Input`, `Battery Output`, and `Battery Recharge` clearly |
| Charge and discharge current | Understand battery flow direction without ambiguous mixed lines |
| Real battery health metrics | Design capacity, full charge capacity, cycle count, health, voltage and temperature |
| Background keepalive setting | Keep the app less likely to be automatically terminated while staying lightweight |
| Launch at login setting | Start the menu bar monitor automatically after user login |
| CPU-active processes | Spot which apps are using the most CPU right now |
| On-demand SoC sampling | CPU / GPU / ANE breakdown when you explicitly allow privileged sampling |

### Install

#### Option 1: Install with the DMG

1. Open [Latest Release](https://github.com/LCYLYM/MacoPowerMonitor/releases/latest)
2. Download `MacoPowerMonitor-v0.3.0-macos.dmg`
3. Open the DMG
4. Drag `MacoPowerMonitor.app` into `Applications`
5. Launch the app from `Applications` or Spotlight

#### Option 2: Download the ZIP

1. Open [Latest Release](https://github.com/LCYLYM/MacoPowerMonitor/releases/latest)
2. Download `MacoPowerMonitor-v0.3.0-macos.zip`
3. Unzip it
4. Double-click `MacoPowerMonitor.app` to run it directly, or move it into `Applications` if you prefer
5. Click the menu bar icon

#### Option 3: Use the portable executable (no installation)

For Apple Silicon Macs, download `MacoPowerMonitor-v0.3.0-macos-arm64.zip` from the release page and unzip it. Then run the single executable:

```bash
chmod +x MacoPowerMonitor-v0.3.0-macos-arm64
./MacoPowerMonitor-v0.3.0-macos-arm64
```

The menu bar monitor runs without being moved to `Applications`. Keep the Terminal session open while it is running; `Launch at login` remains available only in the `.app` build.

#### Option 4: Build from source

Requirements:

- macOS 13 or newer
- Xcode Command Line Tools or full Xcode

```bash
swift build
swift run
```

#### Option 5: Package locally

```bash
./scripts/package_app.sh
open dist/MacoPowerMonitor.app
```

To build the single-file portable executable locally:

```bash
./scripts/build_portable_executable.sh
```

To build the DMG installer locally:

```bash
./scripts/build_dmg.sh
open dist/MacoPowerMonitor.dmg
```

To create the same release-style DMG, ZIP and checksum files used for GitHub Releases:

```bash
./scripts/build_release_assets.sh
```

### Data Sources

All on-screen readings are backed by real macOS data sources.

- `IOPowerSources` / `IOPSGetPowerSourceDescription`
- `IOPSCopyExternalPowerAdapterDetails`
- `IORegistryEntryCreateCFProperties` for `AppleSmartBattery` (including `PowerTelemetryData`, `AdapterDetails`, and `FedDetails`)
- `system_profiler SPPowerDataType -json`
- `ps -axo pid=,%cpu=,rss=,comm=`
- `powermetrics`

Notes:

- `powermetrics` is only used for detailed CPU / GPU / ANE power after you explicitly authorize continuous sampling for the current app session
- The app does not fill missing fields with fabricated estimates

### What The Charts Mean

- `Power`: live adapter input, battery output and battery recharge are shown as separate flows
- `Battery`: battery percentage history
- `Current`: discharge current and charge current are separated instead of mixed together

This is intentional.  
Adapter contract wattage, live Mac-side input and battery-side flow are not the same thing, so the app keeps them distinct. macOS does not expose wall-socket losses, and protocol labels remain unknown when the OS provides no reliable evidence.

### Local History Engine

History collection and chart projection are handled by a dedicated actor outside the main UI path. Samples are submitted through a bounded single-consumer queue, aggregated incrementally, and appended to disk in batches instead of rewriting the complete history file.

```text
~/Library/Application Support/MacoPowerMonitor/power-history/
├── manifest.json
├── raw/YYYY-MM-DDTHH.jsonl
├── minute/YYYY-MM-DDTHH.jsonl
└── five-minute/YYYY-MM-DD.jsonl
```

- Raw 1-second samples are retained for 6 hours, 1-minute aggregates for 24 hours, and 5-minute aggregates for 10 days
- Aggregate records store `sum/count`, so longer-range averages remain correctly weighted
- Missing, invalid, dropped, or delayed samples remain gaps; the app does not insert zeros or estimates
- Pending records are appended every 30 seconds; normal app termination waits up to 2 seconds for a final flush
- Disk is the history source of truth; the background process keeps only bounded pending records and active aggregate buckets, then streams the selected UTC slices into fixed chart buckets on demand
- Chart projections are generated only while the panel is visible, while collection and aggregation continue in the background
- Legacy `power-history.json` is migrated through a validated temporary directory; malformed legacy data is preserved and reported
- Incomplete final JSONL lines are trimmed, while damaged interior records are quarantined without discarding other valid records

### Privacy and Security

- No telemetry upload
- No third-party analytics SDK
- No cloud account requirement
- Continuous privileged sampling starts only after explicit authorization and stops when the app exits
- Local history stays on your Mac at `~/Library/Application Support/MacoPowerMonitor/power-history/`
- History uses versioned, segmented JSON Lines files: 1-second samples for 6 hours, 1-minute aggregates for 24 hours, and 5-minute aggregates for 10 days
- Queries enforce those windows exactly; disk cleanup removes whole UTC slices after every record in the boundary slice has expired
- Existing `power-history.json` data is migrated automatically; generated segments are validated before the legacy file is removed
- History files are never uploaded and are not used for telemetry or third-party analytics

### Project Structure

```text
Sources/MacoPowerMonitor/App
Sources/MacoPowerMonitor/Core
Sources/MacoPowerMonitor/Services
Sources/MacoPowerMonitor/Support
Sources/MacoPowerMonitor/UI
scripts
docs/images
```

- `App`: menu bar lifecycle, floating panel and app startup behavior
- `Core`: core models and chart series definitions
- `Services`: system collectors, persistence, scheduling and privileged sampling
- `Support`: constants, formatting, paths and helpers
- `UI`: dashboard layout, charts, settings and reusable components

### Development Principles

- No mocked battery or power data
- Public or system-backed data sources first
- Low wake-up cost and lightweight background behavior
- Clear distinction between rated power, current input and battery flow
- Modular architecture for future expansion

### Roadmap

- Battery event timeline
- Historical export
- Adapter mismatch and thermal alerts
- Broader Apple Silicon validation

### Contributing

- Contribution guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- Security policy: [SECURITY.md](SECURITY.md)

### License

Released under the [MIT License](LICENSE).

---

## 中文

Maco Power Monitor 是一个轻量级 macOS 状态栏电源监控工具，重点是让你快速看懂电池、充电器和整机功耗到底发生了什么。

它专注三件事：

- 只展示真实系统数据
- 保持低开销、原生状态栏体验
- 用紧凑但高信息密度的方式呈现功耗细节

### 预览

<p align="center">
  <img src="docs/images/overview.png" alt="总览截图" width="380" />
  <img src="docs/images/charts.png" alt="图表截图" width="380" />
</p>

### 为什么它更值得装

- 完全原生：基于 `SwiftUI + AppKit + IOKit`，不是 Electron，也不是网页壳
- 不造数据：电池、电源适配器、进程 CPU 活跃度等信息都来自 macOS 系统接口或系统命令
- 足够轻：常驻状态栏，点开即看，用完即关，不占 Dock，不打断工作流
- 信息更有用：把适配器实时功率、充电协议、电池输出、回充、电流、健康度和 CPU 活跃应用集中在一个面板里
- 对限制诚实：拿不到的数据不会用猜测值硬补，需要管理员权限的指标会明确说明

### 功能亮点

| 功能 | 价值 |
| --- | --- |
| 状态栏图标 | 一眼看到当前电池状态，点击即可展开面板 |
| 紧凑玻璃面板 | 更贴近 macOS 原生风格，视觉轻但信息密度高 |
| 正式 App 图标与 DMG 安装包 | 拖入 `Applications` 即可安装，公开发布更完整 |
| 多选图表切换 | `功耗 / 电量 / 电流` 可以同时显示，不用来回切图 |
| 充电协议与实时功率 | 仅在 macOS 提供可靠字段时显示 USB PD / Apple 私有 / QC，并注明实时 Mac 侧输入功率 |
| 适配器功率-时间曲线 | 以 1 秒间隔记录实时输入功率，并为长时间历史自动降采样 |
| 双向功率视图 | 清晰区分 `适配器实时输入`、`电池输出`、`电池回充` |
| 充放电电流拆分 | 不把正负方向混在一起，更容易理解当前流向 |
| 真实电池健康指标 | 设计容量、满充容量、循环次数、健康度、电压、温度 |
| 后台保活设置 | 在保持轻量的前提下，降低应用被系统自动终止的概率 |
| 开机自启设置 | 登录当前用户后自动启动状态栏监控 |
| CPU 活跃进程列表 | 更快定位当前 CPU 占用较高的应用 |
| 按需 SoC 采样 | 在你主动授权时，获取 CPU / GPU / ANE 分项功耗 |

### 安装

#### 方式一：使用 DMG 安装包

1. 打开 [Latest Release](https://github.com/LCYLYM/MacoPowerMonitor/releases/latest)
2. 下载 `MacoPowerMonitor-v0.3.0-macos.dmg`
3. 打开 DMG
4. 将 `MacoPowerMonitor.app` 拖动到 `Applications`
5. 在 `Applications` 或 Spotlight 中启动应用

#### 方式二：下载 ZIP 压缩包

1. 打开 [Latest Release](https://github.com/LCYLYM/MacoPowerMonitor/releases/latest)
2. 下载 `MacoPowerMonitor-v0.3.0-macos.zip`
3. 解压
4. 可以直接双击 `MacoPowerMonitor.app` 运行；也可以按需要移动到 `Applications`
5. 点击状态栏图标

#### 方式三：使用免安装可执行文件

Apple Silicon Mac 可下载 Release 中的 `MacoPowerMonitor-v0.3.0-macos-arm64.zip`，解压后直接运行其中的单文件：

```bash
chmod +x MacoPowerMonitor-v0.3.0-macos-arm64
./MacoPowerMonitor-v0.3.0-macos-arm64
```

程序会显示在菜单栏中；运行期间请保持对应的终端会话开启。免安装可执行文件不能使用“开机自启”，该功能仅支持 `.app` 版本。

#### 方式四：从源码运行

要求：

- macOS 13 或更高版本
- Xcode Command Line Tools 或完整 Xcode

```bash
swift build
swift run
```

#### 方式五：本地打包 `.app`

```bash
./scripts/package_app.sh
open dist/MacoPowerMonitor.app
```

如果你想在本地生成免安装单文件可执行程序：

```bash
./scripts/build_portable_executable.sh
```

如果你想在本地生成 DMG 安装包：

```bash
./scripts/build_dmg.sh
open dist/MacoPowerMonitor.dmg
```

如果你想生成和 GitHub Release 相同格式的 DMG、ZIP 以及校验文件：

```bash
./scripts/build_release_assets.sh
```

### 数据来源

界面中的指标都基于真实 macOS 数据源。

- `IOPowerSources` / `IOPSGetPowerSourceDescription`
- `IOPSCopyExternalPowerAdapterDetails`
- `IORegistryEntryCreateCFProperties` for `AppleSmartBattery` (including `PowerTelemetryData`, `AdapterDetails`, and `FedDetails`)
- `system_profiler SPPowerDataType -json`
- `ps -axo pid=,%cpu=,rss=,comm=`
- `powermetrics`

说明：

- `powermetrics` 只在你主动授权后用于持续补充本次 App 运行期间的 CPU / GPU / ANE 分项功耗
- 缺失字段不会用模拟值或伪造估算补齐

### 图表含义

- `功耗`：分别显示适配器实时输入、电池输出和电池回充
- `电量`：展示电池百分比历史
- `电流`：把放电电流和充电电流分开，不混在一条线里

这是刻意设计。  
适配器协商上限、Mac 侧实时输入功率、电池侧功率流向，本来就不是同一个概念，所以界面不会把它们混为一谈。macOS 不公开墙插侧转换损耗；系统没有可靠字段时，协议会显示为未知而不是猜测。

### 本地历史引擎

历史采集和图表投影由独立 actor 处理，不占用主界面执行路径。采样通过有界单消费者队列顺序提交，聚合以增量方式完成，磁盘使用批量追加，不再反复重写整份历史文件。

```text
~/Library/Application Support/MacoPowerMonitor/power-history/
├── manifest.json
├── raw/YYYY-MM-DDTHH.jsonl
├── minute/YYYY-MM-DDTHH.jsonl
└── five-minute/YYYY-MM-DD.jsonl
```

- 1 秒原始样本保留 6 小时、1 分钟聚合保留 24 小时、5 分钟聚合保留 10 天
- 聚合记录保存 `sum/count`，保证长时间范围仍使用正确的加权平均
- 缺失、无效、队列丢弃或延迟样本保持为空洞，不补零，也不生成估算值
- 待写记录每 30 秒批量追加；应用正常退出时最多等待 2 秒完成最终 flush
- 磁盘是历史数据真源；后台只保留有界待写记录和活动聚合桶，面板打开时才流式读取所选范围的 UTC 切片并投影到固定图表桶
- 仅在面板显示时生成图表投影；面板关闭后仍继续采集和聚合
- 旧 `power-history.json` 通过临时目录迁移并完整校验；旧数据损坏时保留原文件并报告错误
- JSONL 尾部不完整记录会被截断；中间损坏记录会隔离，其余有效记录继续使用

### 隐私与安全

- 不上传遥测数据
- 不接入第三方分析 SDK
- 不需要云账号
- 持续管理员采样只在用户明确授权后启动，并在 App 退出时停止
- 历史样本默认保存在本机：`~/Library/Application Support/MacoPowerMonitor/power-history/`
- 历史数据使用带版本的分段 JSON Lines：1 秒样本保留 6 小时、1 分钟聚合保留 24 小时、5 分钟聚合保留 10 天
- 查询会严格执行上述时间窗口；磁盘清理按 UTC 整片进行，边界切片中的记录全部过期后才删除该切片
- 现有 `power-history.json` 会自动迁移；新分段通过完整校验后，旧文件才会被删除
- 历史文件不会上传，也不会用于遥测或第三方分析

### 项目结构

```text
Sources/MacoPowerMonitor/App
Sources/MacoPowerMonitor/Core
Sources/MacoPowerMonitor/Services
Sources/MacoPowerMonitor/Support
Sources/MacoPowerMonitor/UI
scripts
docs/images
```

- `App`：状态栏生命周期、浮动面板与启动逻辑
- `Core`：核心模型和图表序列定义
- `Services`：系统采集、持久化、调度与管理员采样
- `Support`：常量、格式化、路径和辅助工具
- `UI`：面板布局、图表、设置页与复用组件

### 开发原则

- 不使用模拟电池或功耗数据
- 优先使用公开接口或系统级真实数据源
- 优先保证低唤醒和低开销
- 明确区分额定功率、当前输入和电池流向
- 保持模块化，方便后续继续扩展

### 路线图

- 电池事件时间线
- 历史数据导出
- 适配器不匹配与温度告警
- 更广泛的 Apple Silicon 机型验证

### 参与贡献

- 贡献指南：[CONTRIBUTING.md](CONTRIBUTING.md)
- 安全策略：[SECURITY.md](SECURITY.md)

### 许可证

本项目基于 [MIT License](LICENSE) 开源。
