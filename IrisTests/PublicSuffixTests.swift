import XCTest
@testable import Iris

final class PublicSuffixTests: XCTestCase {
    func testBundledList() {
        let list = PublicSuffix.bundled
        XCTAssertEqual(list.registrableDomain("news.bbc.co.uk"), "bbc.co.uk")
        XCTAssertEqual(list.registrableDomain("a.example.com"), "example.com")
        XCTAssertEqual(list.registrableDomain("a.foo.github.io"), "foo.github.io")
        XCTAssertNotEqual(list.registrableDomain("foo.github.io"), list.registrableDomain("bar.github.io"))
        XCTAssertEqual(list.registrableDomain("a.b.ck"), "a.b.ck")
        XCTAssertEqual(list.registrableDomain("a.www.ck"), "www.ck")
        XCTAssertEqual(list.registrableDomain("WWW.APPLE.COM."), "apple.com")
        XCTAssertEqual(list.registrableDomain("localhost"), "localhost")
        XCTAssertEqual(list.registrableDomain("127.0.0.1"), "127.0.0.1")
    }
}
