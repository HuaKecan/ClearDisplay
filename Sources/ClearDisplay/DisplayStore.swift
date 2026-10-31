import AppKit
import DisplayCore
import DisplayRuntime
import Foundation
import Observation

struct PendingDisplayChange: Equatable {
    let secondsRemaining: Int
    let summary: String
}

@MainActor @Observable final class DisplayStore {
    var displays: [ConnectedDisplay] = []
    var selectedDisplayID: UInt32? {
        didSet {
            if oldValue != selectedDisplayID {
                selectedModeID = selectedDisplay?.currentMode?.id
                query = ""
            }
        }
    }
    var selectedModeID: String?
    var filter: ModeFilter = .recommended
    var query = ""
    var favorites: [SavedMode] = []
    var pending: PendingDisplayChange? {
        didSet { if oldValue != pending { onPendingChange?(pending) } }
    }
    @ObservationIgnored var onPendingChange: ((PendingDisplayChange?) -> Void)?
    var errorMessage: String?
    var statusMessage: String?
    var showVirtualSheet = false
    var virtualAvailable: Bool { virtual.available }
    var selectedDisplay: ConnectedDisplay? { displays.first { $0.id == selectedDisplayID } }
    var visibleModes: [DisplayModeSpec] {
        guard let display = selectedDisplay else { return [] }
        return ModeCatalog.visible(display.modes, current: display.currentMode, filter: filter, query: query)
    }
    var selectedMode: DisplayModeSpec? { selectedDisplay?.modes.first { $0.id == selectedModeID } }
    var canApply: Bool {
        guard pending == nil, let mode = selectedMode, let current = selectedDisplay?.currentMode else { return false }
        return !mode.matches(current)
    }

    @ObservationIgnored let backend = DisplayBackend(freshProcesses: true)
    @ObservationIgnored let virtual = VirtualDisplayManager()
    @ObservationIgnored let recovery = RecoveryStore(url: RecoveryStore.defaultURL)
    @ObservationIgnored private var receipt: RecoveryReceipt?
    @ObservationIgnored private var rescue: Process?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var displayObserver: NSObjectProtocol?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var lastRecoveryAttempt = Date.distantPast
    @ObservationIgnored private let favoritesURL = RecoveryStore.defaultURL.deletingLastPathComponent().appendingPathComponent("favorites.json")

    init() {
        loadFavorites()
        refresh()
        pollRecovery()
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh() }
            }
    }

    func refresh() {
        do {
            let oldSelection = selectedMode
            displays = try backend.connected(ownedVirtualIDs: virtual.ids)
            if !displays.contains(where: { $0.id == selectedDisplayID }) {
                selectedDisplayID = displays.first?.id
            }
            if let oldSelection, let updated = selectedDisplay?.modes.first(where: { $0.matches(oldSelection) }) {
                selectedModeID = updated.id
            } else if !(selectedDisplay?.modes.contains(where: { $0.id == selectedModeID }) ?? false) {
                selectedModeID = selectedDisplay?.currentMode?.id
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func applySelected() {
        guard canApply, let display = selectedDisplay, let mode = selectedMode else { return }
        errorMessage = nil
        statusMessage = nil
        do {
            let previous = try backend.snapshot()
            guard previous.displays.contains(where: { $0.uuid == display.uuid }) else {
                throw DisplayRuntimeError.message("目标显示器不在恢复快照中，已取消切换。请刷新后重试。")
            }
            let newReceipt = RecoveryReceipt(snapshot: previous, expiresAt: Date().addingTimeInterval(20),
                summary: "\(display.name) · \(mode.resolutionLabel) · \(mode.isHiDPI ? "HiDPI" : "标准")")
            try recovery.begin(newReceipt)
            do { rescue = try launchRescue(receiptURL: recovery.url, token: newReceipt.token) }
            catch {
                // No display mutation has occurred yet.
                _ = try? recovery.restore(token: newReceipt.token) { _ in }
                throw error
            }
            receipt = newReceipt
            pending = PendingDisplayChange(secondsRemaining: newReceipt.secondsRemaining(), summary: newReceipt.summary)
            startRecoveryTimer()
            do {
                try backend.apply(mode, to: display.id, expectedUUID: display.uuid)
                refresh()
                pollRecovery()
            } catch {
                let switchFailure = error.localizedDescription
                do {
                    try recovery.restore(token: newReceipt.token) { try backend.restore($0) }
                    receipt = nil; pending = nil; stopRecoveryTimer(); refresh()
                    errorMessage = switchFailure + " 已恢复原显示配置。"
                } catch {
                    errorMessage = switchFailure + " 恢复尚未成功：" + error.localizedDescription
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func confirmChange() {
        guard let receipt else { return }
        do {
            guard try recovery.confirm(token: receipt.token) else {
                pollRecovery(); return
            }
            self.receipt = nil; pending = nil
            stopRecoveryTimer()
            statusMessage = "已保留当前分辨率。本次设置在当前登录会话有效。"
            refresh()
        } catch { errorMessage = error.localizedDescription; revertChange() }
    }

    func revertChange() {
        guard let receipt else { return }
        do {
            try recovery.restore(token: receipt.token) { try backend.restore($0) }
            self.receipt = nil; pending = nil; errorMessage = nil
            stopRecoveryTimer()
            statusMessage = "已恢复切换前的分辨率与屏幕布局。"
            refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    private func pollRecovery() {
        do {
            guard let active = try recovery.read() else {
                if pending != nil {
                    statusMessage = "确认已超时，原显示配置已由恢复进程还原。"
                    refresh()
                }
                if receipt != nil || pending != nil { receipt = nil; pending = nil }
                stopRecoveryTimer()
                return
            }
            receipt = active
            let updated = PendingDisplayChange(secondsRemaining: active.secondsRemaining(), summary: active.summary)
            if pending != updated { pending = updated }
            startRecoveryTimer()
            // The detached process normally handles expiry. This also supports
            // recovery if a previous launch left a receipt without a live helper.
            if active.expiresAt.timeIntervalSinceNow < -2 && Date().timeIntervalSince(lastRecoveryAttempt) > 5 {
                lastRecoveryAttempt = Date()
                revertChange()
            }
        } catch { errorMessage = "无法读取恢复记录：" + error.localizedDescription }
    }

    private func startRecoveryTimer() {
        guard timer == nil else { return }
        let activeTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollRecovery() }
        }
        activeTimer.tolerance = 0.15
        timer = activeTimer
        RunLoop.main.add(activeTimer, forMode: .common)
    }

    private func stopRecoveryTimer() {
        timer?.invalidate()
        timer = nil
        rescue = nil
    }

    func toggleFavorite(_ mode: DisplayModeSpec) {
        guard let display = selectedDisplay else { return }
        if let existing = favorites.first(where: { $0.displayUUID == display.uuid && $0.mode.matches(mode) }) {
            removeFavorite(existing.id)
        } else {
            favorites.append(SavedMode(displayUUID: display.uuid, displayName: display.name,
                name: "\(mode.resolutionLabel) · \(mode.isHiDPI ? "HiDPI" : "标准") · \(mode.refreshLabel)", mode: mode))
            saveFavorites()
        }
    }

    func isFavorite(_ mode: DisplayModeSpec) -> Bool {
        favorites.contains { $0.displayUUID == selectedDisplay?.uuid && $0.mode.matches(mode) }
    }

    func removeFavorite(_ id: UUID) { favorites.removeAll { $0.id == id }; saveFavorites() }

    func applyFavorite(_ saved: SavedMode) {
        guard pending == nil else { return }
        refresh()
        guard let display = displays.first(where: { $0.uuid == saved.displayUUID }),
              let mode = display.modes.first(where: { $0.matches(saved.mode) }) else {
            errorMessage = "收藏对应的显示器或模式当前不可用。"; return
        }
        selectedDisplayID = display.id
        selectedModeID = mode.id
        applySelected()
    }

    func createVirtual(width: Int, height: Int, refreshRate: Double) {
        guard pending == nil else { return }
        guard virtual.ids.count < 4 else { errorMessage = "最多同时创建 4 个虚拟屏幕。"; return }
        do {
            errorMessage = nil
            let id = try virtual.create(width: width, height: height, refreshRate: refreshRate)
            showVirtualSheet = false
            refresh()
            selectedDisplayID = id
            statusMessage = "已创建独立的 2× HiDPI 虚拟屏幕。退出应用后会自动移除。"
            scheduleRefresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func removeVirtual(_ id: UInt32) {
        guard pending == nil, virtual.ids.contains(id) else { return }
        virtual.remove(id)
        scheduleRefresh()
        statusMessage = "已移除虚拟屏幕。"
    }

    private func loadFavorites() {
        guard FileManager.default.fileExists(atPath: favoritesURL.path) else { return }
        do { favorites = try JSONDecoder().decode([SavedMode].self, from: Data(contentsOf: favoritesURL)) }
        catch { errorMessage = "收藏文件无法读取，原文件已保留：" + error.localizedDescription }
    }

    private func saveFavorites() {
        do {
            try FileManager.default.createDirectory(at: favoritesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: favoritesURL.path) {
                let backup = favoritesURL.deletingPathExtension().appendingPathExtension("previous.json")
                // Preserve the prior contents with an atomic replacement.
                try Data(contentsOf: favoritesURL).write(to: backup, options: .atomic)
            }
            try JSONEncoder().encode(favorites).write(to: favoritesURL, options: .atomic)
        } catch { errorMessage = "无法保存收藏：" + error.localizedDescription }
    }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ClearDisplay-diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DiagnosticCommands.report(backend: backend, virtualIDs: virtual.ids).write(to: url, options: .atomic)
            statusMessage = "诊断已导出。"
        } catch { errorMessage = error.localizedDescription }
    }

    func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
    }

    func shutdown() -> Bool {
        if pending != nil { revertChange() }
        guard pending == nil else { return false }
        virtual.removeAll()
        timer?.invalidate()
        return true
    }
}

func launchRescue(receiptURL: URL, token: UUID) throws -> Process {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let sibling = executable.deletingLastPathComponent().appendingPathComponent("DisplayRescue")
    let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/DisplayRescue")
    guard let helper = [bundled, sibling].first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
        throw DisplayRuntimeError.message("找不到 DisplayRescue 恢复进程。请使用完整的应用包，或先运行构建脚本。")
    }
    let process = Process()
    process.executableURL = helper
    process.arguments = [receiptURL.path, token.uuidString]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    return process
}
