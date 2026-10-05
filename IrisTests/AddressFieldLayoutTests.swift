import XCTest
import SwiftUI
import UIKit
@testable import Iris

@MainActor final class AddressFieldLayoutTests: XCTestCase {
    func testLongAddressStaysInsideSpaceReservedBetweenControls() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = try XCTUnwrap(scene.windows.first)
        let address = "https://example.com/watch/" + String(repeating: "long-episode-name-", count: 80)
        for width in [600.0, 900.0, 1100.0] {
            let host = UIHostingController(rootView:
                HStack(spacing: 8) {
                    Color.clear.frame(width: 100)
                    AddressField(text: address) { _ in }
                        .frame(minWidth: 180, maxWidth: .infinity)
                        .frame(height: 44)
                        .layoutPriority(1)
                    Color.clear.frame(width: 200)
                }
                .frame(width: width, height: 60)
            )
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: 60)
            window.addSubview(host.view)
            defer { host.view.removeFromSuperview() }
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutIfNeeded()
            let field = try XCTUnwrap(textFields(in: host.view).first)
            let rect = field.convert(field.bounds, to: host.view)
            XCTAssertEqual(field.text, address)
            XCTAssertGreaterThanOrEqual(rect.minX, 108 - 1, "Leading controls at width \(width)")
            XCTAssertLessThanOrEqual(rect.maxX, width - 208 + 1, "Trailing controls at width \(width)")
            XCTAssertGreaterThanOrEqual(rect.width, 180, "Usable address at width \(width)")
        }
    }

    private func textFields(in view: UIView) -> [UITextField] {
        (view as? UITextField).map { [$0] } ?? view.subviews.flatMap { textFields(in: $0) }
    }
}
