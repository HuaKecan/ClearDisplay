import Foundation

/// A value snapshot of a display mode, independent of the CoreGraphics object lifetime.
public struct DisplayModeSpec: Codable, Hashable, Identifiable, Sendable {
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double
    public let ioModeID: UInt32

    public init(
        width: Int,
        height: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double,
        ioModeID: UInt32
    ) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.ioModeID = ioModeID
    }

    /// Includes every stored field; unlike `signature`, it distinguishes driver IDs.
    public var id: String {
        "\(width):\(height):\(pixelWidth):\(pixelHeight):\(refreshRate.bitPattern):\(ioModeID)"
    }

    /// Identifies an equivalent mode across display reconnections and driver IDs.
    public var signature: String {
        "\(width)x\(height):\(pixelWidth)x\(pixelHeight):\(Self.rateString(refreshRate))"
    }

    public var isHiDPI: Bool {
        width > 0 && height > 0 && pixelWidth > width && pixelHeight > height
    }

    public var scale: Double {
        guard width > 0, pixelWidth > 0 else { return 1 }
        return Double(pixelWidth) / Double(width)
    }

    public var resolutionLabel: String { "\(width) × \(height)" }
    public var pixelLabel: String { "\(pixelWidth) × \(pixelHeight)" }

    /// CoreGraphics reports zero for displays whose timing is adaptive or unspecified.
    public var refreshLabel: String {
        guard refreshRate.isFinite, refreshRate > 0 else { return "自适应 / 未报告" }
        return "\(Self.rateString(refreshRate)) Hz"
    }

    public func matches(_ other: Self) -> Bool {
        signature == other.signature
    }

    private static func rateString(_ value: Double) -> String {
        let rate = value.isFinite && value > 0 ? value : 0
        let formatted = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), rate)
        return formatted.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
}
