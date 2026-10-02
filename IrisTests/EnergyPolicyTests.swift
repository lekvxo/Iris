import XCTest
@testable import Iris

@MainActor final class EnergyPolicyTests: XCTestCase {
    func testFilterBudgetTracksAllWindowsAndThermalRecovery() async {
        let blocker = BlockerController()
        let policy = EnergyPolicy { blocker.setWorkAllowed($0) }
        let first = UUID(), second = UUID()
        policy.updateThermalState(.nominal)
        policy.setForeground(true, window: first)
        policy.setForeground(true, window: second)
        policy.setForeground(false, window: first)
        XCTAssertTrue(blocker.workAllowed, "A second foreground window still permits refreshes")
        policy.updateThermalState(.serious)
        await blocker.refresh()
        XCTAssertFalse(blocker.isUpdating, "Do not download or convert while hot")
        XCTAssertTrue(blocker.refreshPending)
        XCTAssertEqual(policy.probeInterval, 2000)
        policy.setForeground(false, window: second)
        policy.updateThermalState(.nominal)
        XCTAssertFalse(blocker.workAllowed, "Cooling alone must not start work in the background")
        XCTAssertEqual(policy.probeInterval, 250)
        // A separate policy verifies foreground recovery without starting real network work.
        let recovered = EnergyPolicy { _ in }
        recovered.updateThermalState(.critical)
        recovered.setForeground(true, window: first)
        XCTAssertFalse(recovered.filterWorkAllowed)
        recovered.updateThermalState(.fair)
        XCTAssertTrue(recovered.filterWorkAllowed)
    }
}
