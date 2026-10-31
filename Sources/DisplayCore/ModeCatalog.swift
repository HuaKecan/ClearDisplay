import Foundation

public enum ModeFilter: String, CaseIterable, Identifiable, Sendable {
    case recommended
    case hiDPI
    case all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recommended: "推荐"
        case .hiDPI: "HiDPI"
        case .all: "全部"
        }
    }
}

public enum ModeCatalog {
    /// Deduplicates driver variants, preserving the first matching value.
    /// Pixel dimensions and refresh rates remain part of the signature.
    public static func unique(_ modes: [DisplayModeSpec]) -> [DisplayModeSpec] {
        var seen = Set<String>()
        return modes.filter { seen.insert($0.signature).inserted }
    }

    public static func visible(
        _ modes: [DisplayModeSpec],
        current: DisplayModeSpec?,
        filter: ModeFilter,
        query: String
    ) -> [DisplayModeSpec] {
        var available = unique(modes)
        if let current {
            if let index = available.firstIndex(where: { $0.matches(current) }) {
                available[index] = current
            } else {
                available.append(current)
            }
        }

        let filtered: [DisplayModeSpec]
        switch filter {
        case .all:
            filtered = available
        case .hiDPI:
            filtered = available.filter(\.isHiDPI)
        case .recommended:
            let reference = current ?? available.max(by: { area($0) < area($1) })
            let aspect = reference.flatMap(aspectRatio)
            let common = available.filter { mode in
                guard mode.width >= 1024, mode.width <= 3840, mode.height >= 600 else { return false }
                guard let aspect, let candidateAspect = aspectRatio(mode) else { return true }
                return abs(candidateAspect - aspect) / aspect <= 0.06
            }
            let highDensity = common.filter(\.isHiDPI)
            var recommended = highDensity.isEmpty ? common : highDensity
            // The active setting remains visible even outside the suggested range.
            if let current, !recommended.contains(where: { $0.matches(current) }) {
                recommended.append(current)
            }
            filtered = recommended
        }

        let tokens = normalizedQuery(query).split(whereSeparator: \.isWhitespace).map(String.init)
        return filtered.filter { mode in
            let haystack = searchableText(for: mode)
            return tokens.allSatisfy(haystack.contains)
        }.sorted(by: ordered)
    }

    private static func aspectRatio(_ mode: DisplayModeSpec) -> Double? {
        guard mode.width > 0, mode.height > 0 else { return nil }
        return Double(mode.width) / Double(mode.height)
    }

    private static func area(_ mode: DisplayModeSpec) -> Double {
        Double(mode.width) * Double(mode.height)
    }

    private static func ordered(_ lhs: DisplayModeSpec, _ rhs: DisplayModeSpec) -> Bool {
        if area(lhs) != area(rhs) { return area(lhs) < area(rhs) }
        if lhs.width != rhs.width { return lhs.width < rhs.width }
        if lhs.height != rhs.height { return lhs.height < rhs.height }
        if lhs.isHiDPI != rhs.isHiDPI { return lhs.isHiDPI }
        if lhs.refreshRate != rhs.refreshRate { return lhs.refreshRate > rhs.refreshRate }
        if lhs.pixelWidth != rhs.pixelWidth { return lhs.pixelWidth > rhs.pixelWidth }
        if lhs.pixelHeight != rhs.pixelHeight { return lhs.pixelHeight > rhs.pixelHeight }
        return lhs.id < rhs.id
    }

    private static func normalizedQuery(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"\s*[x×*]\s*"#, with: "x", options: .regularExpression)
            .replacingOccurrences(of: #"\s+hz"#, with: "hz", options: .regularExpression)
            .replacingOccurrences(of: "@", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func searchableText(for mode: DisplayModeSpec) -> String {
        let density = mode.isHiDPI ? "hidpi retina 高清" : "1x 标准"
        let scale = String(format: "%.2gx", locale: Locale(identifier: "en_US_POSIX"), mode.scale)
        let rate = mode.refreshLabel.replacingOccurrences(of: " ", with: "").lowercased()
        return "\(mode.width)x\(mode.height) \(mode.pixelWidth)x\(mode.pixelHeight) \(rate) \(density) \(scale)"
    }
}
