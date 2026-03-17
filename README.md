<div align="center">

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

[Download Latest Release](https://github.com/LCYLYM/MacoPowerMonitor/releases/latest) • [Direct ZIP Download](https://github.com/LCYLYM/MacoPowerMonitor/releases/latest/download/MacoPowerMonitor-v0.1.0-macos.zip) • [Report Bug](https://github.com/LCYLYM/MacoPowerMonitor/issues/new?template=bug_report.md) • [Request Feature](https://github.com/LCYLYM/MacoPowerMonitor/issues/new?template=feature_request.md)

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
| Menu bar status icon | Open the dashboard instantly with one click |
| Compact glass panel | Feels native to macOS and stays out of the way |
| Multi-select chart toggles | Show `Power`, `Battery`, and `Current` together |
| Bidirectional power view | Separate `System Input`, `Battery Output`, and `Battery Recharge` clearly |
| Charge and discharge current | Understand battery flow direction without ambiguous mixed lines |
| Real battery health metrics | Design capacity, full charge capacity, cycle count, health, voltage and temperature |
| Background keepalive setting | Keep the app less likely to be automatically terminated while staying lightweight |
| Launch at login setting | Start the menu bar monitor automatically after user login |
| Top energy processes | Spot which apps are draining power right now |
| On-demand SoC sampling | CPU / GPU / ANE breakdown when you explicitly allow privileged sampling |

### Install

#### Option 1: Download the app

1. Open [Latest Release](https://github.com/LCYLYM/MacoPowerMonitor/releases/latest)
2. Download `MacoPowerMonitor-v0.1.0-macos.zip`
3. Unzip it
4. Move `MacoPowerMonitor.app` into `Applications`
5. Launch the app and click the menu bar icon

#### Option 2: Build from source

Requirements:

- macOS 13 or newer
- Xcode Command Line Tools or full Xcode

```bash
swift build
swift run
```

#### Option 3: Package locally

```bash
./scripts/package_app.sh
open dist/MacoPowerMonitor.app
```

To create the same release-style zip and checksum used for GitHub Releases:

```bash
./scripts/build_release_assets.sh
```

### Data Sources

All on-screen readings are backed by real macOS data sources.

- `IOPowerSources` / `IOPSGetPowerSourceDescription`
- `IOPSCopyExternalPowerAdapterDetails`
- `ioreg -r -c AppleSmartBattery -a`
- `system_profiler SPPowerDataType -json`
- `top -l 1 -stats pid,command,cpu,mem,power`
- `powermetrics`

Notes:

- `powermetrics` is only used for detailed CPU / GPU / ANE power when you explicitly trigger privileged sampling
- The app does not fill missing fields with fabricated estimates

### What The Charts Mean

- `Power`: system input, battery output and battery recharge are shown as separate flows
- `Battery`: battery percentage history
- `Current`: discharge current and charge current are separated instead of mixed together

This is intentional.  
Adapter rated wattage, actual system input and battery-side flow are not the same thing, so the app keeps them distinct.

### Privacy and Security

- No telemetry upload
- No third-party analytics SDK
- No cloud account requirement
- No hidden background elevation loop
- Local history stays on your Mac at `~/Library/Application Support/MacoPowerMonitor/power-history.json`

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
- 不造数据：电池、电源适配器、进程能耗等信息都来自 macOS 系统接口或系统命令
- 足够轻：常驻状态栏，点开即看，用完即关，不占 Dock，不打断工作流
- 信息更有用：把系统输入、电池输出、回充、电流、健康度和高耗电应用集中在一个面板里
- 对限制诚实：拿不到的数据不会用猜测值硬补，需要管理员权限的指标会明确说明

### 功能亮点

| 功能 | 价值 |
| --- | --- |
| 状态栏图标 | 一眼看到当前电池状态，点击即可展开面板 |
| 紧凑玻璃面板 | 更贴近 macOS 原生风格，视觉轻但信息密度高 |
| 多选图表切换 | `功耗 / 电量 / 电流` 可以同时显示，不用来回切图 |
| 双向功率视图 | 清晰区分 `系统输入`、`电池输出`、`电池回充` |
| 充放电电流拆分 | 不把正负方向混在一起，更容易理解当前流向 |
| 真实电池健康指标 | 设计容量、满充容量、循环次数、健康度、电压、温度 |
| 后台保活设置 | 在保持轻量的前提下，降低应用被系统自动终止的概率 |
| 开机自启设置 | 登录当前用户后自动启动状态栏监控 |
| 高耗电进程列表 | 更快定位当前最耗电的应用 |
| 按需 SoC 采样 | 在你主动授权时，获取 CPU / GPU / ANE 分项功耗 |

### 安装

#### 方式一：直接下载应用

1. 打开 [Latest Release](https://github.com/LCYLYM/MacoPowerMonitor/releases/latest)
2. 下载 `MacoPowerMonitor-v0.1.0-macos.zip`
3. 解压
4. 将 `MacoPowerMonitor.app` 移动到 `Applications`
5. 打开应用并点击状态栏图标

#### 方式二：从源码运行

要求：

- macOS 13 或更高版本
- Xcode Command Line Tools 或完整 Xcode

```bash
swift build
swift run
```

#### 方式三：本地打包 `.app`

```bash
./scripts/package_app.sh
open dist/MacoPowerMonitor.app
```

如果你想生成和 GitHub Release 相同格式的安装包与校验文件：

```bash
./scripts/build_release_assets.sh
```

### 数据来源

界面中的指标都基于真实 macOS 数据源。

- `IOPowerSources` / `IOPSGetPowerSourceDescription`
- `IOPSCopyExternalPowerAdapterDetails`
- `ioreg -r -c AppleSmartBattery -a`
- `system_profiler SPPowerDataType -json`
- `top -l 1 -stats pid,command,cpu,mem,power`
- `powermetrics`

说明：

- `powermetrics` 只在你主动触发管理员采样时用于补充 CPU / GPU / ANE 分项功耗
- 缺失字段不会用模拟值或伪造估算补齐

### 图表含义

- `功耗`：分别显示系统输入、电池输出和电池回充
- `电量`：展示电池百分比历史
- `电流`：把放电电流和充电电流分开，不混在一条线里

这是刻意设计。  
适配器额定功率、当前系统输入功率、电池侧功率流向，本来就不是同一个概念，所以界面不会把它们混为一谈。

### 隐私与安全

- 不上传遥测数据
- 不接入第三方分析 SDK
- 不需要云账号
- 不做隐藏的后台持续提权
- 历史样本默认保存在本机：`~/Library/Application Support/MacoPowerMonitor/power-history.json`

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
