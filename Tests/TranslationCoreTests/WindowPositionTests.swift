import XCTest
import CoreGraphics
@testable import TranslationCore

final class WindowPositionTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 30, width: 1512, height: 900)
    private let size = CGSize(width: 420, height: 180)

    func testPrefersBottomRightWithGap() {
        let mouse = CGPoint(x: 400, y: 600)
        let frame = WindowLayout.positionedFrame(near: mouse, size: size, visible: visible)
        XCTAssertEqual(frame.origin, CGPoint(x: 416, y: 404))
        XCTAssertEqual(frame.size, size)
    }

    func testRightEdgeFlipsToLeftInsteadOfCoveringCursor() {
        let mouse = CGPoint(x: 1450, y: 600)
        let frame = WindowLayout.positionedFrame(near: mouse, size: size, visible: visible)
        XCTAssertEqual(frame.maxX, mouse.x - 16)
        XCTAssertEqual(frame.maxY, mouse.y - 16)
    }

    func testBottomEdgeFlipsAboveCursor() {
        let mouse = CGPoint(x: 400, y: 60)
        let frame = WindowLayout.positionedFrame(near: mouse, size: size, visible: visible)
        XCTAssertEqual(frame.minY, mouse.y + 16)
        XCTAssertEqual(frame.minX, mouse.x + 16)
    }

    func testAllFourCornersStayWithinUsableDesktop() {
        for x in [visible.minX + 1, visible.maxX - 1] {
            for y in [visible.minY + 1, visible.maxY - 1] {
                let frame = WindowLayout.positionedFrame(near: CGPoint(x: x, y: y), size: size, visible: visible)
                XCTAssertTrue(visible.contains(frame))
                XCTAssertEqual(frame.size, size)
            }
        }
    }

    func testDisplayWithNegativeOriginUsesItsOwnBounds() {
        let second = CGRect(x: -1920, y: -400, width: 1920, height: 1000)
        let mouse = CGPoint(x: -40, y: -350)
        let frame = WindowLayout.positionedFrame(near: mouse, size: size, visible: second)
        XCTAssertTrue(second.contains(frame))
        XCTAssertEqual(frame.maxX, mouse.x - 16)
        XCTAssertEqual(frame.minY, mouse.y + 16)
    }

    func testOversizedWindowFitsSmallDisplay() {
        let small = CGRect(x: 100, y: 50, width: 300, height: 150)
        let frame = WindowLayout.positionedFrame(near: CGPoint(x: 250, y: 100), size: size, visible: small)
        XCTAssertEqual(frame, small)
    }

    func testPointerOverDockStillKeepsWindowOnDesktop() {
        let frame = WindowLayout.positionedFrame(near: CGPoint(x: 700, y: 5), size: size, visible: visible)
        XCTAssertTrue(visible.contains(frame))
    }
}
