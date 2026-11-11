import XCTest
@testable import MRTCore

final class WheelLandingTests: XCTestCase {
    func testTargetRotationLandsOnTheRequestedSegment() throws {
        let even = WheelGeometry(segmentCount: 4)
        for index in 0..<4 {
            let target = try XCTUnwrap(even.targetRotation(landingOn: index, from: 20, fullTurns: 5))
            XCTAssertEqual(even.segmentIndex(forRotation: target), index)
            XCTAssertGreaterThan(target, 20)
        }
        let weighted = WheelGeometry(weights: [1, 3])
        for index in 0..<2 {
            let target = try XCTUnwrap(weighted.targetRotation(landingOn: index, from: -15, fullTurns: 3))
            XCTAssertEqual(weighted.segmentIndex(forRotation: target), index)
        }
        XCTAssertNil(even.targetRotation(landingOn: 9, from: 0, fullTurns: 2))
        XCTAssertNil(even.targetRotation(landingOn: 0, from: .nan, fullTurns: 2))
    }
}
