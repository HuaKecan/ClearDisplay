import Darwin
import Foundation
import VirtualDisplayBridge

public enum HelperLocator {
    public static func executable(named name: String) throws -> URL {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let sibling = executable.deletingLastPathComponent().appendingPathComponent(name)
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(name)")
        guard let helper = [bundled, sibling].first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw DisplayRuntimeError.message("找不到 \(name)。请使用完整应用包或先运行构建脚本。")
        }
        return helper
    }
}

@MainActor public final class VirtualDisplayManager {
    private struct Owned {
        let process: Process
        let input: Pipe
        let folder: URL
        let slot: Int
    }
    private struct Ready: Decodable { let id: UInt32?; let error: String? }
    private var owned: [UInt32: Owned] = [:]
    public let available: Bool
    public init() { available = CDVirtualDisplay.available }
    public var ids: Set<UInt32> { Set(owned.filter { $0.value.process.isRunning }.keys) }

    @discardableResult public func create(width: Int, height: Int, refreshRate: Double) throws -> UInt32 {
        guard (640...3840).contains(width), (400...2160).contains(height), [30.0, 60.0].contains(refreshRate) else {
            throw DisplayRuntimeError.message("虚拟屏尺寸或刷新率超出支持范围。")
        }
        guard available else { throw DisplayRuntimeError.message("当前系统不支持虚拟 HiDPI 屏幕接口。") }
        for (id, item) in owned where !item.process.isRunning { remove(id) }
        let helper = try HelperLocator.executable(named: "DisplayVirtualHost")
        let slot = (0..<4).first { candidate in !owned.values.contains { $0.slot == candidate } }
        guard let slot else { throw DisplayRuntimeError.message("最多同时创建 4 个虚拟屏幕。") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ClearDisplayHost-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let readyFile = folder.appendingPathComponent("ready.json")
        let input = Pipe()
        // Later children must not inherit this writer: EOF follows UI death.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETFD, FD_CLOEXEC)
        let process = Process()
        process.executableURL = helper
        process.arguments = [String(width), String(height), String(refreshRate), String(slot), readyFile.path]
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            try input.fileHandleForReading.close()
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if let data = try? Data(contentsOf: readyFile), let ready = try? JSONDecoder().decode(Ready.self, from: data) {
                    if let error = ready.error { throw DisplayRuntimeError.message(error) }
                    if let id = ready.id, id != 0, process.isRunning {
                        owned[id] = Owned(process: process, input: input, folder: folder, slot: slot)
                        return id
                    }
                }
                if !process.isRunning { throw DisplayRuntimeError.message("虚拟屏持有进程提前退出。") }
                Thread.sleep(forTimeInterval: 0.03)
            }
            throw DisplayRuntimeError.message("虚拟屏未在期限内上线，已取消创建。")
        } catch {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    public func remove(_ id: UInt32) {
        guard let item = owned.removeValue(forKey: id) else { return }
        try? item.input.fileHandleForWriting.close()
        if item.process.isRunning { item.process.terminate() }
        try? FileManager.default.removeItem(at: item.folder)
    }
    public func removeAll() { for id in Array(owned.keys) { remove(id) } }
}
