import DisplayRuntime
import Foundation

// Independent process: restoration still runs if the main UI crashes or stops
// servicing its run loop. It only accepts an explicit receipt and token.
let arguments = CommandLine.arguments
if arguments.count == 2 && arguments[1] == "--request" {
    let response: DisplayWorkerResponse
    do {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let request = try JSONDecoder().decode(DisplayWorkerRequest.self, from: input)
        let backend = DisplayBackend()
        switch request.operation {
        case .probe:
            response = try MainActor.assumeIsolated { DisplayWorkerResponse(displays: try backend.connected()) }
        case .snapshot:
            response = DisplayWorkerResponse(snapshot: try backend.snapshot())
        case .apply:
            guard let mode = request.mode, let id = request.displayID, let uuid = request.expectedUUID else {
                throw DisplayRuntimeError.message("显示服务请求缺少模式或显示器。")
            }
            try backend.apply(mode, to: id, expectedUUID: uuid)
            response = DisplayWorkerResponse()
        case .restore:
            guard let snapshot = request.snapshot else { throw DisplayRuntimeError.message("显示服务请求缺少快照。") }
            try backend.restore(snapshot)
            response = DisplayWorkerResponse()
        }
    } catch { response = DisplayWorkerResponse(error: error.localizedDescription) }
    if let encoded = try? JSONEncoder().encode(response) { FileHandle.standardOutput.write(encoded) }
    exit(0)
}
guard arguments.count == 3, let token = UUID(uuidString: arguments[2]) else {
    fputs("Usage: DisplayRescue /absolute/recovery.json TOKEN\n", stderr)
    exit(64)
}
let store = RecoveryStore(url: URL(fileURLWithPath: arguments[1]))
let backend = DisplayBackend()
var failures = 0
while true {
    do {
        guard let receipt = try store.read(), receipt.token == token else { exit(0) }
        if receipt.expiresAt <= Date() {
            try store.restore(token: token, onlyIfExpired: true) { try backend.restore($0) }
            exit(0)
        }
    } catch {
        failures += 1
        fputs("DisplayRescue: \(error.localizedDescription)\n", stderr)
        // Keep the receipt on failure for explicit recovery after reconnection.
        if failures >= 5 { exit(1) }
    }
    Thread.sleep(forTimeInterval: 0.25)
}
