import Darwin
import DisplayCore
import Foundation

public struct RecoveryReceipt: Codable, Equatable {
    public let token: UUID
    public let snapshot: DesktopSnapshot
    public let expiresAt: Date
    public let summary: String
    public init(token: UUID = UUID(), snapshot: DesktopSnapshot, expiresAt: Date, summary: String) {
        self.token = token; self.snapshot = snapshot; self.expiresAt = expiresAt; self.summary = summary
    }
    public func secondsRemaining(at now: Date = Date()) -> Int {
        max(0, Int(ceil(expiresAt.timeIntervalSince(now))))
    }
}

/// Serializes the UI and detached rescue process with a POSIX advisory lock.
/// A receipt is removed only after confirmation or a successful restoration.
public final class RecoveryStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClearDisplay/recovery.json")
    }

    public func read() throws -> RecoveryReceipt? {
        try locked { try readUnlocked() }
    }

    public func begin(_ receipt: RecoveryReceipt) throws {
        try locked {
            guard try readUnlocked() == nil else {
                throw DisplayRuntimeError.message("上次显示切换尚待确认或恢复，请先处理它。")
            }
            let data = try JSONEncoder().encode(receipt)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    @discardableResult public func confirm(token: UUID, now: Date = Date()) throws -> Bool {
        try locked {
            guard let receipt = try readUnlocked(), receipt.token == token else { return false }
            guard receipt.expiresAt > now else {
                throw DisplayRuntimeError.message("确认时间已结束，正在恢复原显示配置。")
            }
            try FileManager.default.removeItem(at: url)
            return true
        }
    }

    @discardableResult public func restore(token: UUID, onlyIfExpired: Bool = false, now: Date = Date(),
                                         action: (DesktopSnapshot) throws -> Void) throws -> Bool {
        try locked {
            guard let receipt = try readUnlocked(), receipt.token == token else { return false }
            if onlyIfExpired && receipt.expiresAt > now { return false }
            try action(receipt.snapshot)
            try FileManager.default.removeItem(at: url)
            return true
        }
    }

    private func readUnlocked() throws -> RecoveryReceipt? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(RecoveryReceipt.self, from: Data(contentsOf: url))
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let fd = Darwin.open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw DisplayRuntimeError.message("无法打开显示恢复锁。") }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw DisplayRuntimeError.message("无法锁定显示恢复记录。") }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }
}
