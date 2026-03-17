# MacoPowerMonitor

一个原生 macOS 状态栏电源监控小工具，目标是低开销、真实数据、可持续扩展。

## 当前方案

- 技术栈：`SwiftUI + MenuBarExtra + IOKit`
- 运行形态：仅驻留在菜单栏，不依赖 Electron，不常驻 Dock
- 数据来源：
  - `IOPowerSources`：电量、充电状态、剩余时间、适配器基础信息
  - `AppleSmartBattery` IORegistry：循环次数、设计容量、满充容量、电压、电流、温度、部分实时功率遥测
- 刷新策略：每 30 秒采样一次，并带 5 秒容差，减少无意义唤醒
- 历史缓存：保存到 `~/Library/Application Support/MacoPowerMonitor/power-history.json`

## 为什么这样做

这类工具如果要非常轻量，最稳妥的路线就是用原生菜单栏应用：

- `MenuBarExtra` 非常适合状态栏弹出面板
- `SwiftUI` 足够完成这种中小型信息密集型面板
- `IOPowerSources` 是 Apple 提供的正式电源接口
- `AppleSmartBattery` 能补到更多电池级硬件指标

相比 WebView/Electron，这个方案的内存和 CPU 占用会小很多，也更接近系统原生体验。

## 目前已实现

- 菜单栏图标显示当前电量和充电状态
- 点击状态栏图标可打开监控面板
- 顶部摘要区显示：
  - 预计剩余时间或预计充满时间
  - 当前系统功率
  - 当前电量
- 1 小时历史图：
  - 实时功耗
  - 电池电量
- 电池详细统计：
  - 当前连接会话时长
  - 会话期间电量变化
  - 会话期间容量变化
- 电池健康信息：
  - 设计容量
  - 满充容量
  - 循环次数
  - 健康度
- 实时电气指标：
  - 系统输入功率
  - 电池功率流
  - 电池电压
  - 电池电流
  - 适配器功率
  - 电池温度
- 最近采样记录网格，全部基于真实样本渲染

## 暂未实现的设计稿项

设计稿里有 CPU / GPU / NPU 分项功耗，这一类数据在普通轻量菜单栏应用里并没有稳定的公开系统 API 可直接拿到。

`powermetrics` 虽然在部分机器上可以输出估算的 SoC 分项功耗，但它更偏诊断工具，通常不适合作为默认无感常驻采样方案，原因包括：

- 某些更细采样需要更高权限
- 本身就是估算值，不适合作为“精确硬件拆分”
- 常驻频繁调用会违背“低消耗”目标

所以当前版本不会用模拟数据去补这些卡片。拿不到的维度就不展示，保证界面上的每一项都来自真实系统读数。

## 本地运行

命令行运行：

```bash
swift build
swift run
```

如果你的机器装了完整 Xcode，也可以直接用 Xcode 打开这个 Swift Package 调试。

## 目录结构

```text
Sources/MacoPowerMonitor/App
Sources/MacoPowerMonitor/Core
Sources/MacoPowerMonitor/Services
Sources/MacoPowerMonitor/Support
Sources/MacoPowerMonitor/UI
```

说明：

- `App`：应用入口和 AppKit 生命周期
- `Core`：核心数据模型
- `Services`：系统电源采集、历史存储、状态管理
- `Support`：格式化、路径、调度器、常量
- `UI`：菜单栏面板界面与组件

## 下一步建议

- 增加设置页：刷新周期、启动时自动运行、图表窗口长度
- 增加电池事件日志：接入/拔出电源、开始充电、充满
- 增加导出能力：CSV/JSON 历史记录
- 增加高级模式：显式开启后尝试接入 `powermetrics`
- 增加异常提醒：温度过高、适配器功率不足、健康度下滑
