# 实现架构

## 分层

| 模块 | 职责 |
| --- | --- |
| `DisplayCore` | 模式值对象、完整属性匹配、过滤排序、收藏序列化；不接触显示硬件 |
| `DisplayRuntime` | 公开 CoreGraphics 模式操作、UUID、桌面快照、恢复记录与文件锁、虚拟屏生命周期 |
| `VirtualDisplayBridge` | 使用 Objective-C 运行时动态解析四个 CGVirtualDisplay 私有类；独立的接口适配代码 |
| `ClearDisplay` | SwiftUI 原生界面、AppKit 菜单栏、用户确认与 CLI 诊断 |
| `DisplayVirtualHost` | 每块虚拟屏由一个独立子进程持有，父进程退出或关闭管道后自动退出并移除屏幕 |
| `DisplayRescue` | 独立超时恢复；另提供短生命周期的模式枚举/应用/快照服务，避免旧 CG 模式缓存 |

## 模式识别

通过 `CGDisplayCopyAllDisplayModes` 和 `kCGDisplayShowDuplicateLowResolutionModes` 读取模式。完整身份包含逻辑宽高、渲染像素宽高和精确到百分位的刷新率。数值显示器 ID 与 I/O 模式 ID 不作为跨重连的唯一身份。

HiDPI 要求两个维度的像素尺寸均大于逻辑尺寸，界面展示真实比值。零刷新率显示“自适应 / 未报告”，不把未知时序写成固定 60 Hz。

UI 合并属性相同的驱动变体，但底层应用时保留所有原始候选；某些公开属性相同的像素格式变体可能被 Quartz 拒绝。切换后再次读取当前模式校验结果。

## 切换和恢复

1. 拍摄所有在线显示器的模式、位置和镜像关系快照。
2. 原子保存带 UUID token 和截止时间的恢复记录，启动独立 `DisplayRescue`。若启动失败，不执行显示切换。
3. 使用 CoreGraphics 配置事务应用到当前登录会话。
4. 用户在 20 秒截止前确认，文件锁保护下删除恢复记录。
5. 取消或超时则恢复快照；UI 与恢复进程通过同一文件锁互斥。恢复失败时不删除记录。

恢复按稳定 UUID 解析当前连接，跳过已断开的屏幕，不对复用的数字 ID 操作。离线屏无法在离线期间设置；重连后的显示行为由系统管理。模式消失或系统拒绝恢复会保留错误和恢复记录。

独立进程覆盖 UI 崩溃与普通事件循环阻塞，不构成系统故障、WindowServer 故障或强制杀掉所有应用进程后的恢复保证。公开 API 不提供对任何硬件链路的绝对成功承诺，画面质量仍需实际观察。

## 自定义虚拟 HiDPI

Objective-C 桥检查类与必要选择器存在后，创建辅助进程拥有的 `CGVirtualDisplay`。逻辑模式对应 2× 最大渲染尺寸，独立使用本项目的 vendor/product 与按尺寸、刷新率和并发槽位计算的稳定非零 serial。通过独立持有进程退出移除，仅允许删除本项目持有的屏幕。

本机实测发现：主进程先读取物理屏模式、再自行创建虚拟屏后，新虚拟屏在线且 active，但该进程的 CG 模式查询为空；另一个全新进程能读到 1600×900 / 3200×1800 的真实 HiDPI 模式。于是把创建与持有放入独立进程，随后也复现了主进程提前查询模式后，对辅助进程新建屏幕的模式查询为空。因此所有显示模式枚举、应用和快照操作进一步改为一次性的 `DisplayRescue --request` 服务进程执行，只把可序列化值对象交给 UI；每次操作都使用新的 CoreGraphics 客户端。管道 EOF 与进程退出同时提供崩溃清理边界。

这是额外显示器，不是物理屏驱动覆盖。本版本没有提供镜像或串流；它们是后续独立功能。当前用户请求的物理屏分辨率与 HiDPI 切换依赖系统已提供模式。

## 资料与来源

接口行为参考 Apple 的 CoreGraphics 文档及本机 SDK 头文件。虚拟屏 ABI 与逻辑/像素关系同时核对了 Chromium 的公开测试实现和当前系统 Objective-C 选择器；这里的桥与生命周期逻辑为独立实现，没有包含 Chromium 或 BetterDisplay 实现代码。

- Apple：`CGDisplayCopyAllDisplayModes`、`kCGDisplayShowDuplicateLowResolutionModes`、`CGConfigureDisplayWithDisplayMode`、`CGCompleteDisplayConfiguration`。
- Chromium：`ui/display/mac/test/virtual_display_util_mac.mm`，查看 2026-10-31 的公开主线，仅用于接口交叉核对。
- BetterDisplay 官方功能说明与本机静态证据，用于确定功能范围，不作为内部实现恢复的证明。

来源页面通过研究工具查阅；本地本次实现的证据详见验收记录。未运行原应用的反编译调用链验证。

## 轻量常驻与状态栏

- 默认只保留原生 NSStatusItem 和数据缓存，不创建 SwiftUI 控制窗口。
- NSMenu 在打开时按缓存数据生成，显示器变化才重新枚举，不因打开菜单启动显示服务。
- 分辨率按逻辑尺寸分组，刷新率放在子菜单；常用尺寸外的模式折叠到“更多尺寸”。
- 从菜单切换时仅创建短生命周期的 AppKit 确认面板。完整窗口关闭时释放 NSHostingController。
- 无待确认更改时没有恢复定时器；切换期间才启动 1 秒 UI 倒计时，独立恢复进程只在本次切换期间运行。
- 默认空闲只有一个进程；每个正在使用的虚拟屏增加一个必要的独立持有进程。
- 不注册开机启动、守护服务或后台常驻网络任务。
