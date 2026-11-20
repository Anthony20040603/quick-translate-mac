import XCTest
import CoreGraphics
@testable import TranslationCore

final class WindowLayoutTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 30, width: 1512, height: 900)
    private let compact = CGRect(x: 300, y: 500, width: 640, height: 180)

    func testShortTranslationKeepsCompactHeightAndExistingWidth() {
        let result = WindowLayout.frame(current: compact, visible: screen, contentHeight: 45,
                                        titlebarHeight: 28, newDocument: true)
        XCTAssertEqual(result.size, CGSize(width: 640, height: 180))
        XCTAssertEqual(result.maxY, compact.maxY)
    }

    func testTranslationGrowsThenStopsAtFortyPercent() {
        let growing = WindowLayout.frame(current: compact, visible: screen, contentHeight: 230,
                                         titlebarHeight: 28, newDocument: false)
        XCTAssertEqual(growing.height, 258)
        let capped = WindowLayout.frame(current: growing, visible: screen, contentHeight: 2000,
                                        titlebarHeight: 28, newDocument: false)
        XCTAssertEqual(capped.height, screen.height * 0.4)
        XCTAssertEqual(capped.width, compact.width)
        XCTAssertEqual(capped.maxY, compact.maxY)
    }

    func testNewTranslationResetsHeightButRevisionsDoNotJitter() {
        let tall = CGRect(x: 300, y: 320, width: 700, height: 360)
        let revision = WindowLayout.frame(current: tall, visible: screen, contentHeight: 50,
                                          titlebarHeight: 28, newDocument: false)
        XCTAssertEqual(revision.height, 360)
        let next = WindowLayout.frame(current: tall, visible: screen, contentHeight: 50,
                                      titlebarHeight: 28, newDocument: true)
        XCTAssertEqual(next.height, 180)
        XCTAssertEqual(next.width, 700)
    }

    func testGrowthNearBottomStaysOnSecondScreen() {
        let second = CGRect(x: -1920, y: -400, width: 1920, height: 1000)
        let current = CGRect(x: -1800, y: -390, width: 640, height: 180)
        let result = WindowLayout.frame(current: current, visible: second, contentHeight: 2000,
                                        titlebarHeight: 28, newDocument: false)
        XCTAssertEqual(result.height, 400)
        XCTAssertEqual(result.width, 640)
        XCTAssertGreaterThanOrEqual(result.minY, second.minY)
        XCTAssertLessThanOrEqual(result.maxY, second.maxY)
    }
}
