import Foundation
import XCTest
@testable import DisplayCore

final class DisplayCoreTests: XCTestCase {
    private func mode(
        _ width: Int = 1920,
        _ height: Int = 1080,
        scale: Int = 2,
        rate: Double = 60,
        id: UInt32 = 1
    ) -> DisplayModeSpec {
        DisplayModeSpec(
            width: width, height: height,
            pixelWidth: width * scale, pixelHeight: height * scale,
            refreshRate: rate, ioModeID: id
        )
    }

    func testDensityUsesLogicalAndPixelDimensions() {
        let retina = mode()
        XCTAssertTrue(retina.isHiDPI)
        XCTAssertEqual(retina.scale, 2)
        XCTAssertEqual(retina.resolutionLabel, "1920 × 1080")
        XCTAssertEqual(retina.pixelLabel, "3840 × 2160")
        XCTAssertFalse(mode(scale: 1).isHiDPI)
        XCTAssertFalse(DisplayModeSpec(width: 0, height: 0, pixelWidth: 0, pixelHeight: 0, refreshRate: 0, ioModeID: 0).isHiDPI)
    }

    func testRefreshLabelsPreserveFractionalTimingAndUnknownTiming() {
        XCTAssertEqual(mode(rate: 59.94).refreshLabel, "59.94 Hz")
        XCTAssertEqual(mode(rate: 120).refreshLabel, "120 Hz")
        XCTAssertEqual(mode(rate: 0).refreshLabel, "自适应 / 未报告")
    }

    func testSignaturesIgnoreDriverIDButIDsDoNot() {
        let first = mode(id: 1)
        let second = mode(id: 99)
        XCTAssertTrue(first.matches(second))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(ModeCatalog.unique([first, second]), [first])
    }

    func testCatalogKeepsPixelDimensionsAndRefreshVariants() {
        let modes = [mode(scale: 1), mode(scale: 2), mode(scale: 2, rate: 120), mode(scale: 2, rate: 59.94)]
        XCTAssertEqual(ModeCatalog.unique(modes).count, 4)
    }

    func testSignaturesQuantizeRefreshToHundredths() {
        XCTAssertTrue(mode(rate: 59.94001).matches(mode(rate: 59.93999)))
        XCTAssertFalse(mode(rate: 59.94).matches(mode(rate: 60)))
    }

    func testHiDPIFilterDoesNotIncludeStandardCurrentMode() {
        let standard = mode(scale: 1)
        let retina = mode()
        XCTAssertEqual(ModeCatalog.visible([standard, retina], current: standard, filter: .hiDPI, query: ""), [retina])
    }

    func testRecommendedPrefersHiDPIAndKeepsCurrent() {
        let current = mode(2560, 1440, scale: 1)
        let retina = mode()
        let standard = mode(scale: 1)
        let otherAspect = mode(1600, 1200)
        let result = ModeCatalog.visible([standard, otherAspect, retina, current], current: current, filter: .recommended, query: "")
        XCTAssertEqual(result, [retina, current])
    }

    func testRecommendedFallsBackToStandardModes() {
        let current = mode(2560, 1440, scale: 1)
        let smaller = mode(scale: 1)
        XCTAssertEqual(ModeCatalog.visible([current, smaller], current: current, filter: .recommended, query: ""), [smaller, current])
    }

    func testMissingCurrentModeIsIncludedAndUsesItsDriverID() {
        let current = mode(id: 77)
        let result = ModeCatalog.visible([mode(id: 1)], current: current, filter: .all, query: "")
        XCTAssertEqual(result, [current])
        let absent = mode(2560, 1440)
        XCTAssertEqual(ModeCatalog.visible([], current: absent, filter: .all, query: ""), [absent])
    }

    func testSearchUnderstandsResolutionWhitespaceDensityAndRefresh() {
        let target = mode(2560, 1440, rate: 59.94)
        let other = mode(2560, 1440, scale: 1)
        for query in ["2560", "2560×1440", "2560 x 1440", "2560×1440@59.94hz", "HiDPI 2560 59.94 Hz", "5120x2880"] {
            XCTAssertTrue(ModeCatalog.visible([target, other], current: nil, filter: .all, query: query).contains(target), query)
        }
        XCTAssertEqual(ModeCatalog.visible([target, other], current: nil, filter: .all, query: "hidpi 59.94hz"), [target])
        XCTAssertTrue(ModeCatalog.visible([target], current: target, filter: .all, query: "3840x2160").isEmpty)
    }

    func testSortOrdersSizeDensityAndRefresh() {
        let small = mode(1280, 720)
        let standard = mode(scale: 1)
        let retina60 = mode()
        let retina120 = mode(rate: 120)
        let result = ModeCatalog.visible([standard, retina60, retina120, small], current: nil, filter: .all, query: "")
        XCTAssertEqual(result, [small, retina120, retina60, standard])
    }

    func testSavedModeRoundTripKeepsStableDisplayIdentityAndFractionalRefresh() throws {
        let preset = SavedMode(displayUUID: "ABC-123", displayName: "外接屏", name: "写代码", mode: mode(2560, 1440, rate: 59.94))
        let decoded = try JSONDecoder().decode(SavedMode.self, from: JSONEncoder().encode(preset))
        XCTAssertEqual(decoded, preset)
        XCTAssertEqual(decoded.displayUUID, "ABC-123")
        XCTAssertEqual(decoded.mode.refreshRate, 59.94)
    }
}
