import AppKit
import CoreGraphics
import Foundation
import VirtualDisplayBridge

// One owner process per screen isolates CoreGraphics's creator-mode cache and
// makes deletion reliable even after the virtual display's mode was changed.
let args = CommandLine.arguments
guard args.count == 6, let width = Int(args[1]), let height = Int(args[2]),
      let refresh = Double(args[3]), let slot = Int(args[4]), (0..<4).contains(slot),
      (640...3840).contains(width), (400...2160).contains(height) else { exit(64) }
let readyURL = URL(fileURLWithPath: args[5])
func publish(_ value: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
        try? data.write(to: readyURL, options: .atomic)
    }
}
// Reuse a stable monitor identity for each size, rate and simultaneous slot.
var serial: UInt32 = 2166136261
for byte in "ClearDisplay-\(width)x\(height)-\(refresh)-\(slot)".utf8 {
    serial = (serial ^ UInt32(byte)) &* 16777619
}
if serial == 0 { serial = 1 }
var display: CDVirtualDisplay?
do {
    // Do not query the existing display modes before creation in this process.
    display = try CDVirtualDisplay(name: "ClearDisplay HiDPI \(width)×\(height)",
        logicalWidth: UInt(width), logicalHeight: UInt(height), refreshRate: refresh,
        serialNumber: serial)
    guard let display else { throw NSError(domain: "ClearDisplay", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "虚拟屏对象未创建。"]) }
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    NSApp.finishLaunching()
    let deadline = Date().addingTimeInterval(3)
    while CGDisplayIsActive(display.displayID) == 0 && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
    }
    guard CGDisplayIsActive(display.displayID) != 0 else {
        throw NSError(domain: "ClearDisplay", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "系统没有激活虚拟屏幕。"])
    }
    publish(["id": display.displayID])
} catch {
    publish(["error": error.localizedDescription])
    exit(1)
}

// EOF also arrives when the parent crashes, because only that process owns the
// writer. WindowServer reclaims this process's screen on exit.
let source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO,
                                           queue: DispatchQueue.global(qos: .utility))
source.setEventHandler {
    var byte: UInt8 = 0
    if read(STDIN_FILENO, &byte, 1) <= 0 { exit(0) }
}
source.resume()
withExtendedLifetime(display) { NSApp.run() }
