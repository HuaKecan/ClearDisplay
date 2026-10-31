import AppKit
import Foundation

// Original vector artwork, rendered at each standard icon size.
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
func draw(_ pixels: Int) -> Data {
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / 1024)
    transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 205, yRadius: 205)
    NSGradient(starting: NSColor(red: 0.16, green: 0.48, blue: 0.97, alpha: 1),
               ending: NSColor(red: 0.11, green: 0.21, blue: 0.62, alpha: 1))!.draw(in: tile, angle: -65)
    let bezel = NSBezierPath(roundedRect: NSRect(x: 196, y: 300, width: 632, height: 442), xRadius: 46, yRadius: 46)
    NSColor.white.withAlphaComponent(0.96).setFill(); bezel.fill()
    let screen = NSBezierPath(roundedRect: NSRect(x: 221, y: 342, width: 582, height: 373), xRadius: 25, yRadius: 25)
    NSGradient(starting: NSColor(red: 0.61, green: 0.90, blue: 1, alpha: 1),
               ending: NSColor(red: 0.17, green: 0.52, blue: 0.96, alpha: 1))!.draw(in: screen, angle: -35)
    NSColor.white.withAlphaComponent(0.96).setFill()
    NSBezierPath(roundedRect: NSRect(x: 465, y: 217, width: 94, height: 91), xRadius: 10, yRadius: 10).fill()
    NSBezierPath(roundedRect: NSRect(x: 378, y: 202, width: 268, height: 32), xRadius: 16, yRadius: 16).fill()
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 157, weight: .bold),
        .foregroundColor: NSColor.white]
    let label = NSAttributedString(string: "2×", attributes: attributes)
    label.draw(at: NSPoint(x: 512 - label.size().width / 2, y: 440))
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return bitmap.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    try draw(size).write(to: destination.appendingPathComponent("icon_\(size)x\(size).png"))
    try draw(size * 2).write(to: destination.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
