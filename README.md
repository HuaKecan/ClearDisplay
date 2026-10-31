# ClearDisplay

一个以**分辨率和 HiDPI** 为重点的原生 macOS 显示器工具。提供 Swift 源码、可构建的 `.app`、原生菜单栏下拉框和独立超时恢复进程。默认仅菜单栏常驻；控制窗口按需创建，关闭即释放，空闲时无定时轮询。界面为简体中文，最低部署版本 macOS 14。

## 下载与兼容性

在本仓库的 **Releases** 中下载 `ClearDisplay-0.1.0-macOS-Universal.zip`。解压后将 `ClearDisplay.app` 拖入“应用程序”文件夹，双击打开，点击顶部菜单栏的显示器图标。

- 通用包包含 Apple 芯片 `arm64` 与 Intel `x86_64`，最低 macOS 14；不支持 Windows。
- Apple 芯片版已在本机验证。Intel 版已完成交叉编译和架构检查，尚未在 Intel 真机上验证。
- 发布包使用本地 ad-hoc 签名，未进行 Apple Developer ID 公证。首次打开如被阻止，在尝试打开后，前往“系统设置 → 隐私与安全性”，选择该应用对应的“仍要打开”。
- 可选模式由 macOS 和显示器连接链路决定，无法保证每台电脑都有相同的 HiDPI 或刷新率选项。

完整安装步骤见 [中文使用说明](docs/share-guide.zh-CN.txt)。

## 已实现

- 枚举所有在线显示器和系统支持的显示模式，包括被默认列表隐藏的低分辨率/HiDPI 变体。
- 分别展示桌面逻辑尺寸、渲染像素尺寸、缩放倍数和刷新率。
- 推荐 / HiDPI / 全部筛选，支持 `2560x1440`、`60hz`、`retina` 搜索。
- 切换分辨率与刷新率，20 秒内确认；超时由独立的 `DisplayRescue` 进程恢复原模式和布局。
- 绑定显示器 UUID 的常用模式收藏；重连后重新解析可用模式。
- 自定义独立虚拟 HiDPI 屏，逻辑尺寸 640–3840 × 400–2160，2× 渲染，30 / 60 Hz；退出自动移除。
- 原生状态栏下拉菜单：按显示器分组、当前模式勾选、HiDPI / 标准模式、刷新率子菜单、收藏、常用尺寸和更多尺寸。
- 菜单切换使用小型 AppKit 倒计时确认框，无需创建完整控制面板。
- 热插拔事件刷新、显示诊断导出和命令行恢复。

物理屏模式列表来自系统。虚拟屏是一个额外桌面，**创建它不会直接向物理屏注入任意自定义分辨率**。本版本没有实现原生物理屏 EDID/系统覆盖、虚拟屏镜像、串流、DDC、HDR 或 BetterDisplay 的全部功能。分辨率设置在当前登录会话内有效。

## 构建和打开

需要 Xcode 或包含 macOS SDK 的 Swift 工具链（Swift 6 或更新）；没有第三方包依赖。

```bash
# 在仓库根目录执行
bash scripts/build-app.sh --install
open "$HOME/Applications/ClearDisplay.app"
```

安装位置为 `~/Applications/ClearDisplay.app`。启动后点击顶部菜单栏的显示器图标；直接选择分辨率，或点击“打开控制面板…”进入详细窗口。若窗口已打开，可通过应用菜单的“打开状态栏菜单”查看相同下拉框。构建脚本产出 `dist/ClearDisplay-0.1.0.zip`，只保留 `~/Applications/ClearDisplay.app` 一个正式安装，不在 `dist/` 或 `.backups/` 中保留可启动的应用副本。安装时只临时保留回滚副本，验证成功即清理。脚本将构建输入与编译缓存置于本机用户缓存目录，避免云同步扩展属性和文件时间戳导致签名或编译失败；ZIP 在本地临时目录签名完成后打包。当前机器本地构建默认只包含本机架构；需要通用二进制时使用 `bash scripts/build-app.sh --universal`。

## 使用

1. 左侧选择物理显示器。
2. 选择“HiDPI”筛选；例如逻辑 `1920 × 1080`、渲染 `3840 × 2160` 表示 2× 模式。渲染尺寸不是线缆输出时序，最终画面取决于显示器与 macOS 缩放链路。
3. 选择模式并点击“应用分辨率”。看清画面后点击“保留更改”，否则等待自动恢复。
4. 使用星标收藏常用模式。收藏会记住这块显示器的稳定身份及完整模式属性。
5. 如需独立的自定义 HiDPI 桌面，点击“创建 HiDPI 虚拟屏”。右键虚拟屏可移除。

系统未提供 HiDPI 模式时，不会把 1× 模式伪装成 HiDPI。虚拟屏依赖动态探测的私有 `CGVirtualDisplay` 接口；系统更新后可能不可用，此时物理屏功能仍可使用。不需要管理员权限、关闭 SIP 或改动 BetterDisplay。

**实体屏设置后可退出：** 点击“保留更改”后，在菜单栏选择“退出 ClearDisplay”，当前分辨率仍由系统维持；以后需要调整时再打开。只关闭控制窗口仍会保留菜单栏进程。虚拟屏需要程序保持运行，退出时移除。程序不注册开机启动；重启、注销或重连后的模式由系统管理，本版本不自动重新应用收藏。

## 验证和恢复

```bash
bash scripts/swift-tool.sh test
"$HOME/Applications/ClearDisplay.app/Contents/MacOS/ClearDisplay" --list
"$HOME/Applications/ClearDisplay.app/Contents/MacOS/ClearDisplay" --self-test-read-only
"$HOME/Applications/ClearDisplay.app/Contents/MacOS/ClearDisplay" --menu-inspect
"$HOME/Applications/ClearDisplay.app/Contents/MacOS/ClearDisplay" --virtual-smoke
"$HOME/Applications/ClearDisplay.app/Contents/MacOS/ClearDisplay" --recover
```

`--virtual-smoke` 会临时创建一个 1600 × 900 / 3200 × 1800 HiDPI 屏，在这块临时屏上切换模式并验证独立超时恢复，最后移除并比较原显示器快照。它不会主动切换物理屏模式。运行期间桌面会短暂出现一块额外屏幕。

恢复记录：`~/Library/Application Support/ClearDisplay/recovery.json`。应用与恢复进程使用文件锁，确保确认和恢复不会同时生效；恢复失败时保留记录，以便重连显示器后 `--recover` 重试。收藏位于同目录的 `favorites.json`，每次保存前备份上一份到 `favorites.previous.json`。

## 轻量化实测

本机 Apple Silicon、macOS 27.0.1，菜单栏空闲时 10 秒只读采样：CPU 时间增长 0.00 秒，RSS 约 30.4 MiB，显示辅助进程 0 个。这是短时本机测量，RSS 不等于系统显示的物理内存占用，也不代表所有机器或长期运行。可使用 `python3 scripts/measure-idle.py <PID> 10` 进行只读采样。

## 分析与实现依据

- [实现架构及限制](docs/architecture.md)。
- [验收记录](docs/validation.md)。

本机原始诊断、显示器标识和第三方应用静态检查记录保留在本地，不随公开仓库发布。

独立实现，没有复制 BetterDisplay 的实现代码、图标、授权逻辑或资源。新项目代码使用 MIT 许可。BetterDisplay 是原作者的产品名称；本项目与其无隶属关系。
