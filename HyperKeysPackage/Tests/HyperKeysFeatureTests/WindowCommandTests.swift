import CoreGraphics
import Testing
@testable import WindowEngine

@MainActor
struct WindowCommandTests {
    private let frame = CGRect(x: 0, y: 25, width: 1200, height: 800)

    @Test func newLayoutsCoverTheRightArea() {
        func rect(_ position: WindowPosition) -> CGRect {
            let (origin, size) = WindowManager.targetRect(for: position, in: frame)
            return CGRect(origin: origin, size: size)
        }
        #expect(rect(.centerHalf) == CGRect(x: 300, y: 25, width: 600, height: 800))
        #expect(rect(.centerTwoThirds) == CGRect(x: 200, y: 25, width: 800, height: 800))
        #expect(rect(.lastThreeFourths) == CGRect(x: 300, y: 25, width: 900, height: 800))
        #expect(rect(.almostMaximize) == CGRect(x: 60, y: 65, width: 1080, height: 720))
        // Raycast's Reasonable Size: 60% wide and 80% tall, capped at 1025 × 900.
        #expect(rect(.reasonableSize).size == CGSize(width: 720, height: 640))
    }

    @Test func movesHaveSymbolsInsteadOfAreas() {
        for position in WindowPositionCategory.move.positions {
            #expect(position.normalizedRect == nil)
            #expect(position.symbol != nil)
        }
        #expect(WindowPosition.leftHalf.symbol == nil)
    }

    @Test func repeatingAHalfCyclesItsWidth() {
        let half = CGRect(x: 0, y: 25, width: 600, height: 800)
        let (twoThirdsOrigin, twoThirds) = WindowManager.nextCycleRect(current: half, left: true, frame: frame)
        #expect(twoThirdsOrigin.x == 0 && twoThirds.width == 800)

        let (oneThirdOrigin, oneThird) = WindowManager.nextCycleRect(current: CGRect(origin: twoThirdsOrigin, size: twoThirds), left: true, frame: frame)
        #expect(oneThirdOrigin.x == 0 && oneThird.width == 400)

        let (_, backToHalf) = WindowManager.nextCycleRect(current: CGRect(origin: oneThirdOrigin, size: oneThird), left: true, frame: frame)
        #expect(backToHalf.width == 600)

        // A window somewhere else starts at a half; right halves sit on the right edge.
        let (rightOrigin, right) = WindowManager.nextCycleRect(current: CGRect(x: 100, y: 100, width: 500, height: 400), left: false, frame: frame)
        #expect(rightOrigin.x == 600 && right.width == 600)
    }

    @Test func keepsPlaceAndSizeAcrossDisplays() {
        let laptop = CGRect(x: 0, y: 25, width: 1200, height: 800)
        let monitor = CGRect(x: 1200, y: 0, width: 2400, height: 1600)
        let (origin, size) = WindowManager.mapRect(CGRect(x: 600, y: 25, width: 600, height: 400), from: laptop, to: monitor)
        #expect(origin == CGPoint(x: 2400, y: 0))
        #expect(size == CGSize(width: 1200, height: 800))
    }
}
