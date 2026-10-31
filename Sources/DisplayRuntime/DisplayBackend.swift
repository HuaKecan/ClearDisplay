import AppKit
import CoreGraphics
import DisplayCore
import Foundation

public struct ConnectedDisplay: Identifiable, Codable {
    public let id: UInt32
    public let uuid: String
    public let name: String
    public let isBuiltIn: Bool
    public let isMain: Bool
    public let isVirtual: Bool
    public let currentMode: DisplayModeSpec?
    public let modes: [DisplayModeSpec]
}

public enum DisplayRuntimeError: LocalizedError {
    case message(String)
    case quartz(String, Int32)
    public var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .quartz(let action, let code): return "\(action)失败（CoreGraphics \(code)）。"
        }
    }
}

public struct DisplaySnapshotEntry: Codable, Equatable {
    public let uuid: String
    public let displayID: UInt32
    public let mode: DisplayModeSpec
    public let x: Int32
    public let y: Int32
    public let mirrorUUID: String?
    public init(uuid: String, displayID: UInt32, mode: DisplayModeSpec,
                x: Int32, y: Int32, mirrorUUID: String? = nil) {
        self.uuid = uuid; self.displayID = displayID; self.mode = mode
        self.x = x; self.y = y; self.mirrorUUID = mirrorUUID
    }
}

public struct DesktopSnapshot: Codable, Equatable {
    public let displays: [DisplaySnapshotEntry]
    public init(displays: [DisplaySnapshotEntry]) { self.displays = displays }
}

public final class DisplayBackend {
    private let freshProcesses: Bool
    public init(freshProcesses: Bool = false) { self.freshProcesses = freshProcesses }

    public func onlineIDs() throws -> [UInt32] {
        var count: UInt32 = 0
        try check(CGGetOnlineDisplayList(0, nil, &count), "读取显示器列表")
        guard count > 0 else { return [] }
        var ids = [UInt32](repeating: 0, count: Int(count))
        try check(CGGetOnlineDisplayList(count, &ids, &count), "读取显示器列表")
        return Array(ids.prefix(Int(count)))
    }

    public func uuid(for id: UInt32) -> String {
        guard let value = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else {
            return "display-\(id)"
        }
        return CFUUIDCreateString(nil, value) as String
    }

    public func resolve(uuid: String) throws -> UInt32? {
        try onlineIDs().first { self.uuid(for: $0) == uuid }
    }

    public func rawModes(for id: UInt32) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        return CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? []
    }

    public func spec(_ mode: CGDisplayMode) -> DisplayModeSpec {
        DisplayModeSpec(width: mode.width, height: mode.height,
                        pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                        refreshRate: mode.refreshRate, ioModeID: UInt32(bitPattern: mode.ioDisplayModeID))
    }

    public func currentMode(for id: UInt32) -> DisplayModeSpec? {
        if freshProcesses {
            return (try? worker(DisplayWorkerRequest(operation: .probe)))?.displays?.first { $0.id == id }?.currentMode
        }
        return CGDisplayCopyDisplayMode(id).map(spec)
    }

    @MainActor public func connected(ownedVirtualIDs: Set<UInt32> = []) throws -> [ConnectedDisplay] {
        if freshProcesses {
            return try (worker(DisplayWorkerRequest(operation: .probe)).displays ?? []).map { display in
                ConnectedDisplay(id: display.id, uuid: display.uuid, name: display.name, isBuiltIn: display.isBuiltIn,
                    isMain: display.isMain, isVirtual: ownedVirtualIDs.contains(display.id),
                    currentMode: display.currentMode, modes: display.modes)
            }
        }
        let names = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (UInt32, String)? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (id.uint32Value, screen.localizedName)
        })
        return try onlineIDs().map { id in
            var modes = ModeCatalog.unique(rawModes(for: id).filter { $0.isUsableForDesktopGUI() }.map(spec))
            let current = currentMode(for: id)
            if let current {
                modes.removeAll { $0.signature == current.signature }
                modes.append(current)
            }
            return ConnectedDisplay(id: id, uuid: uuid(for: id),
                name: names[id] ?? "显示器 \(id)", isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                isMain: CGDisplayIsMain(id) != 0,
                isVirtual: ownedVirtualIDs.contains(id), currentMode: current,
                modes: modes.sorted { ($0.width * $0.height) < ($1.width * $1.height) })
        }.sorted { a, b in
            if a.isMain != b.isMain { return a.isMain }
            return a.id < b.id
        }
    }

    public func snapshot() throws -> DesktopSnapshot {
        if freshProcesses {
            guard let snapshot = try worker(DisplayWorkerRequest(operation: .snapshot)).snapshot else {
                throw DisplayRuntimeError.message("显示服务没有返回快照。")
            }
            return snapshot
        }
        return DesktopSnapshot(displays: try onlineIDs().map { id in
            guard let mode = currentMode(for: id) else {
                throw DisplayRuntimeError.message("显示器 \(id) 的原模式暂不可读，已取消切换以保留恢复能力。请稍后刷新。")
            }
            let bounds = CGDisplayBounds(id)
            let mirror = CGDisplayMirrorsDisplay(id)
            return DisplaySnapshotEntry(uuid: uuid(for: id), displayID: id, mode: mode,
                x: Int32(bounds.minX), y: Int32(bounds.minY),
                mirrorUUID: mirror == kCGNullDirectDisplay ? nil : uuid(for: mirror))
        })
    }

    public func apply(_ requested: DisplayModeSpec, to id: UInt32, expectedUUID: String? = nil) throws {
        if freshProcesses {
            _ = try worker(DisplayWorkerRequest(operation: .apply, displayID: id, expectedUUID: expectedUUID ?? uuid(for: id), mode: requested)); return
        }
        guard try onlineIDs().contains(id) else { throw DisplayRuntimeError.message("所选显示器已断开。") }
        if let expectedUUID, uuid(for: id) != expectedUUID {
            throw DisplayRuntimeError.message("显示器连接已改变，已取消切换。请刷新后重新选择。")
        }
        // Keep *all* raw equivalent candidates. Quartz can expose duplicate
        // public mode properties where only one underlying pixel format works.
        let candidates = rawModes(for: id).filter { spec($0).matches(requested) }.sorted {
            (UInt32(bitPattern: $0.ioDisplayModeID) == requested.ioModeID ? 0 : 1) < (UInt32(bitPattern: $1.ioDisplayModeID) == requested.ioModeID ? 0 : 1)
        }
        guard !candidates.isEmpty else { throw DisplayRuntimeError.message("此模式已不可用，请刷新模式列表。") }
        var lastError = CGError.failure
        for mode in candidates {
            var config: CGDisplayConfigRef?
            try check(CGBeginDisplayConfiguration(&config), "开始切换")
            let configured = CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
            if configured != .success {
                CGCancelDisplayConfiguration(config); lastError = configured; continue
            }
            lastError = CGCompleteDisplayConfiguration(config, .forSession)
            if lastError == .success {
                guard let actual = currentMode(for: id), actual.matches(requested) else {
                    throw DisplayRuntimeError.message("系统未切换到请求的模式，正在恢复原配置。")
                }
                return
            }
        }
        throw DisplayRuntimeError.quartz("切换分辨率", lastError.rawValue)
    }

    /// Restores all still-connected displays, including layout and mirror sets.
    /// UUID matching avoids applying a saved mode to a reused numerical ID.
    public func restore(_ snapshot: DesktopSnapshot) throws {
        if freshProcesses {
            _ = try worker(DisplayWorkerRequest(operation: .restore, snapshot: snapshot)); return
        }
        let ids = try onlineIDs()
        let uuidMap = Dictionary(uniqueKeysWithValues: ids.map { (uuid(for: $0), $0) })
        let entries = snapshot.displays.compactMap { entry -> (DisplaySnapshotEntry, UInt32, CGDisplayMode)? in
            guard let id = uuidMap[entry.uuid] else { return nil }
            let raw = rawModes(for: id)
            let exact = raw.first { UInt32(bitPattern: $0.ioDisplayModeID) == entry.mode.ioModeID && spec($0).matches(entry.mode) }
                ?? raw.first { spec($0).matches(entry.mode) }
            guard let mode = exact else { return nil }
            return (entry, id, mode)
        }
        let connectedSaved = snapshot.displays.filter { uuidMap[$0.uuid] != nil }
        guard entries.count == connectedSaved.count else {
            throw DisplayRuntimeError.message("部分原始模式暂不可用，恢复记录已保留。请重连显示器后重试。")
        }
        guard !entries.isEmpty else { return }
        var config: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&config), "开始恢复")
        // A transaction is either committed or cancelled; never partially apply.
        do {
            for (entry, id, mode) in entries {
                try check(CGConfigureDisplayWithDisplayMode(config, id, mode, nil), "恢复分辨率")
                if entry.mirrorUUID == nil {
                    try check(CGConfigureDisplayOrigin(config, id, entry.x, entry.y), "恢复屏幕位置")
                }
            }
            for (entry, id, _) in entries {
                let master = entry.mirrorUUID.flatMap { uuidMap[$0] } ?? kCGNullDirectDisplay
                try check(CGConfigureDisplayMirrorOfDisplay(config, id, master), "恢复镜像设置")
            }
        } catch {
            CGCancelDisplayConfiguration(config)
            throw error
        }
        try check(CGCompleteDisplayConfiguration(config, .forSession), "恢复显示配置")
        for (entry, id, _) in entries {
            guard let actual = currentMode(for: id), actual.matches(entry.mode) else {
                throw DisplayRuntimeError.message("系统未完整恢复原分辨率，恢复记录已保留。")
            }
        }
    }

    private func check(_ error: CGError, _ action: String) throws {
        if error != .success { throw DisplayRuntimeError.quartz(action, error.rawValue) }
    }
}
