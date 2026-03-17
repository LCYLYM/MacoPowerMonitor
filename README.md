# Maco Power Monitor

一个为 Apple Silicon Mac 设计的原生菜单栏电源监控工具。

它专注做三件事：

- 用真实系统数据展示电量、充电、适配器和功耗状态
- 保持低开销、轻量级的菜单栏常驻体验
- 在紧凑面板里提供高信息密度的可视化与解释

![Maco Power Monitor overview](docs/images/overview.png)
![Maco Power Monitor charts](docs/images/charts.png)

## 为什么值得安装

- 原生菜单栏应用。`SwiftUI + AppKit + IOKit`，不依赖 Electron 或 WebView。
- 无虚拟数据。界面里的指标全部来自真实系统接口或系统命令输出。
- 低干扰设计。驻留在状态栏，点击即看，不占 Dock，不打断当前工作流。
- 信息密度高。把电量、输入功率、电池输出、回充、电流、健康度和会话信息集中在一个轻量面板里。
- 真实可扩展。对拿不到的指标不造数，对需要管理员权限的 SoC 分项功耗明确说明并按需采样。

## 功能亮点

- 状态栏图标显示当前电池状态，点击展开监控面板
- 顶部摘要快速显示剩余时间、当前电量、系统输入、电池电流、适配器额定
- 1 小时 / 24 小时 / 10 天趋势范围切换
- `功耗 / 电量 / 电流` 多选显示，不需要反复切图
- 功耗图同时展示：
  - 系统输入
  - 电池输出
  - 电池回充
- 电流图同时展示：
  - 放电电流
  - 充电电流
- 电池详细数据：
  - 设计容量
  - 满充容量
  - 实际循环次数
  - 健康度
  - 电压
  - 温度
- 高耗电进程列表
- 管理员模式下按需采样 CPU / GPU / ANE 分项功耗

## 数据来源

以下信息均来自 macOS 公开或系统级真实接口，没有模拟值：

- `IOPowerSources` / `IOPSGetPowerSourceDescription`
- `IOPSCopyExternalPowerAdapterDetails`
- `ioreg -r -c AppleSmartBattery -a`
- `system_profiler SPPowerDataType -json`
- `top -l 1 -stats pid,command,cpu,mem,power`
- `powermetrics`
  - 仅在用户主动授权管理员采样时启用
  - 用于补充 CPU / GPU / ANE 分项功耗

## 截图说明

- README 里的截图来自真实运行中的应用界面
- 图表中的数值和走势来自当前机器的真实电源样本
- 透明背景为 macOS 菜单栏面板实际效果，不是设计稿拼图

## 安装方式

### 方式一：本地构建

要求：

- macOS 13 或更高版本
- Xcode Command Line Tools 或完整 Xcode

构建与运行：

```bash
swift build
swift run
```

### 方式二：打包为 `.app`

```bash
./scripts/package_app.sh
open dist/MacoPowerMonitor.app
```

## 权限与说明

- 普通模式下，不需要管理员权限即可读取大部分电池、电源和适配器信息。
- 更细的 SoC 分项功耗依赖 `powermetrics`，通常需要管理员授权。
- 设置页里的“管理员采样”是按需触发，不会默认后台持续提权。
- 适配器额定功率表示供电上限，不等于这一刻整机实际消耗。
- 系统输入和电池输出是两个方向不同的概念，所以图表会分开显示。

## 隐私与安全

- 不上传遥测数据
- 不接入第三方分析 SDK
- 不发送任何设备信息到远端服务
- 历史样本默认保存在本机：
  - `~/Library/Application Support/MacoPowerMonitor/power-history.json`

## 项目结构

```text
Sources/MacoPowerMonitor/App
Sources/MacoPowerMonitor/Core
Sources/MacoPowerMonitor/Services
Sources/MacoPowerMonitor/Support
Sources/MacoPowerMonitor/UI
scripts
docs/images
```

- `App`: 状态栏生命周期、面板与启动逻辑
- `Core`: 核心模型与图表序列定义
- `Services`: 系统采集、权限采样、历史存储、状态管理
- `Support`: 常量、路径、格式化、调度器
- `UI`: 面板布局、图表组件、玻璃化视觉和设置界面

## 开发原则

- 无硬编码模拟数据
- 真实 API 数据优先
- 低功耗和低唤醒优先
- 明确区分“当前输入”“电池输出”“额定上限”“管理员估算”
- 保持模块化，方便继续扩展更多面板与采样器

## Roadmap

- 开机自启动配置
- 电池事件时间线
- 历史数据导出
- 适配器异常与温度告警
- 更多 Apple Silicon 平台适配验证

## 参与贡献

欢迎提交 Issue 和 PR。

- 贡献指南见 [CONTRIBUTING.md](CONTRIBUTING.md)
- 安全问题见 [SECURITY.md](SECURITY.md)

## License

本项目采用 [MIT License](LICENSE) 开源。
