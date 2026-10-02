import XCTest
@testable import Iris

final class SmokeTests: XCTestCase {
    func testAppModuleLoads() { XCTAssertEqual(2 + 2, 4) }
}
