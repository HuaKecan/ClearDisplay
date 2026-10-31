import Darwin
import DisplayCore
import Foundation

public struct DisplayWorkerRequest: Codable {
    public enum Operation: String, Codable { case probe, snapshot, apply, restore }
    public let operation: Operation
    public var displayID: UInt32?
    public var expectedUUID: String?
    public var mode: DisplayModeSpec?
    public var snapshot: DesktopSnapshot?
    public init(operation: Operation, displayID: UInt32? = nil, expectedUUID: String? = nil, mode: DisplayModeSpec? = nil,
                snapshot: DesktopSnapshot? = nil) {
        self.operation = operation; self.displayID = displayID; self.expectedUUID = expectedUUID; self.mode = mode; self.snapshot = snapshot
    }
}

public struct DisplayWorkerResponse: Codable {
    public var displays: [ConnectedDisplay]?
    public var snapshot: DesktopSnapshot?
    public var error: String?
    public init(displays: [ConnectedDisplay]? = nil, snapshot: DesktopSnapshot? = nil, error: String? = nil) {
        self.displays = displays; self.snapshot = snapshot; self.error = error
    }
}

extension DisplayBackend {
    /// A fresh CoreGraphics client prevents stale display-mode caches after
    /// hot-plug or virtual-screen creation. Only value objects cross the pipe.
    func worker(_ request: DisplayWorkerRequest) throws -> DisplayWorkerResponse {
        let process = Process()
        process.executableURL = try HelperLocator.executable(named: "DisplayRescue")
        process.arguments = ["--request"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        try input.fileHandleForReading.close()
        try output.fileHandleForWriting.close()
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10, execute: timeout)
        defer { timeout.cancel() }
        try input.fileHandleForWriting.write(contentsOf: JSONEncoder().encode(request))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard !data.isEmpty else { throw DisplayRuntimeError.message("显示服务未响应或已超时，原配置由恢复进程保护。") }
        let response = try JSONDecoder().decode(DisplayWorkerResponse.self, from: data)
        if let error = response.error { throw DisplayRuntimeError.message(error) }
        guard process.terminationStatus == 0 else { throw DisplayRuntimeError.message("显示服务提前退出。") }
        return response
    }
}
