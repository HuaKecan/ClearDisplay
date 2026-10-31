import AppKit
import DisplayCore
import DisplayRuntime
import Foundation

@MainActor enum DiagnosticCommands {
    static func report(backend: DisplayBackend, virtualIDs: Set<UInt32> = []) throws -> Data {
        let displays = try backend.connected(ownedVirtualIDs: virtualIDs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        struct DisplayReport: Encodable {
            let id: UInt32; let uuid: String; let name: String
            let builtIn: Bool; let main: Bool; let ownedVirtual: Bool
            let current: DisplayModeSpec?; let modes: [DisplayModeSpec]
        }
        struct Report: Encodable {
            let application: String; let system: String; let virtualAPIAvailable: Bool
            let displays: [DisplayReport]
        }
        return try encoder.encode(Report(application: "ClearDisplay 0.1.0",
            system: ProcessInfo.processInfo.operatingSystemVersionString,
            virtualAPIAvailable: VirtualDisplayManager().available,
            displays: displays.map { DisplayReport(id: $0.id, uuid: $0.uuid, name: $0.name,
                builtIn: $0.isBuiltIn, main: $0.isMain, ownedVirtual: $0.isVirtual,
                current: $0.currentMode, modes: $0.modes) }))
    }

    static func handleArguments() -> Bool {
        let args = Set(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else { return false }
        if args.contains("--list") || args.contains("--self-test-read-only") {
            do { print(String(decoding: try report(backend: DisplayBackend()), as: UTF8.self)) }
            catch { fail(error) }
            return true
        }
        if args.contains("--recover") {
            do {
                let store = RecoveryStore(url: RecoveryStore.defaultURL)
                if let receipt = try store.read() {
                    try store.restore(token: receipt.token) { try DisplayBackend().restore($0) }
                    print("已恢复记录中的显示配置。")
                } else { print("没有待恢复的显示切换。") }
            } catch { fail(error) }
            return true
        }
        if args.contains("--menu-inspect") {
            _ = NSApplication.shared
            let store = DisplayStore()
            let delegate = AppDelegate()
            let menu = NSMenu()
            delegate.buildStatusMenu(menu, store: store)
            func serialize(_ menu: NSMenu) -> [[String: Any]] {
                menu.items.map { item in
                    var value: [String: Any] = ["title": item.title, "enabled": item.isEnabled,
                        "checked": item.state == .on, "separator": item.isSeparatorItem]
                    if let action = item.action {
                        value["action"] = NSStringFromSelector(action)
                        value["actionConnected"] = (item.target as? NSObject)?.responds(to: action) == true
                    }
                    if let submenu = item.submenu { value["children"] = serialize(submenu) }
                    return value
                }
            }
            do {
                let data = try JSONSerialization.data(withJSONObject: serialize(menu), options: [.prettyPrinted, .sortedKeys])
                print(String(decoding: data, as: UTF8.self))
            } catch { fail(error) }
            return true
        }
        if args.contains("--virtual-smoke") {
            do { try virtualSmoke() } catch { fail(error) }
            return true
        }
        if args.contains("--help") {
            print("ClearDisplay [--list | --self-test-read-only | --menu-inspect | --virtual-smoke | --recover]\n无参数：打开原生显示器控制窗口。")
            return true
        }
        // Launch Services can supply arguments; do not interpret them as CLI.
        return false
    }

    private static func virtualSmoke() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.finishLaunching()
        let backend = DisplayBackend(freshProcesses: true)
        let before = try backend.snapshot()
        let manager = VirtualDisplayManager()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ClearDisplaySmoke-\(UUID().uuidString)")
        let store = RecoveryStore(url: folder.appendingPathComponent("recovery.json"))
        defer {
            manager.removeAll()
            spin(0.8)
            try? FileManager.default.removeItem(at: folder)
        }
        let id = try manager.create(width: 1600, height: 900, refreshRate: 60)
        spin(5)
        guard let current = backend.currentMode(for: id), current.isHiDPI,
              current.width == 1600, current.pixelWidth == 3200 else {
            let observed = backend.currentMode(for: id).map { "\($0.resolutionLabel) / \($0.pixelLabel)" } ?? "nil"
            let choices = (try backend.connected(ownedVirtualIDs: manager.ids).first { $0.id == id }?.modes ?? []).map { "\($0.resolutionLabel)/\($0.pixelLabel)" }.joined(separator: "; ")
            throw DisplayRuntimeError.message("虚拟屏 \(id) 初始模式：\(observed)；在线 ID：\(try backend.onlineIDs())；active=\(CGDisplayIsActive(id)) asleep=\(CGDisplayIsAsleep(id)) bounds=\(CGDisplayBounds(id)) mirror=\(CGDisplayMirrorsDisplay(id))；可选：\(choices)")
        }
        let smaller = (try backend.connected(ownedVirtualIDs: manager.ids).first { $0.id == id }?.modes ?? []).first {
            $0.width == 1280 && $0.height == 720 && $0.isHiDPI
        }
        guard let smaller else { throw DisplayRuntimeError.message("虚拟测试屏缺少第二个 HiDPI 模式。") }
        let receipt = RecoveryReceipt(snapshot: try backend.snapshot(), expiresAt: Date().addingTimeInterval(4),
                                      summary: "temporary virtual display recovery smoke")
        try store.begin(receipt)
        let rescue = try launchRescue(receiptURL: store.url, token: receipt.token)
        defer {
            // Keep recovery material until the helper exits; clean up even when
            // validation fails after the mode has been switched.
            if (try? store.read()) != nil {
                _ = try? store.restore(token: receipt.token) { try backend.restore($0) }
            }
            withExtendedLifetime(rescue) {}
        }
        try backend.apply(smaller, to: id)
        spin(5)
        guard let restored = backend.currentMode(for: id), restored.matches(current),
              try store.read() == nil else {
            throw DisplayRuntimeError.message("独立进程没有在期限内恢复虚拟屏模式。")
        }
        manager.removeAll()
        spin(1)
        let after = try backend.snapshot()
        guard after == before else {
            throw DisplayRuntimeError.message("虚拟屏测试后物理屏快照发生差异，请检查显示配置。")
        }
        print("{\"virtualHiDPI\":true,\"logical\":\"1600x900\",\"rendering\":\"3200x1800\",\"modeSwitch\":true,\"detachedRecovery\":true,\"physicalSnapshotUnchanged\":true,\"cleanup\":true}")
    }

    private static func spin(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    private static func fail(_ error: Error) -> Never {
        fputs("ClearDisplay: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}
