import XCTest
@testable import Znap

final class HotkeyServiceTests: XCTestCase {
    func testServiceIsSingleton() {
        let a = HotkeyService.shared
        let b = HotkeyService.shared
        XCTAssertTrue(a === b, "HotkeyService.shared should always return the same instance")
    }

    func testRegisterReturnsIncrementingIds() {
        let service = HotkeyService.shared
        let id1 = service.register(keyCode: 0, modifiers: 0) {}
        let id2 = service.register(keyCode: 0, modifiers: 0) {}
        XCTAssertEqual(id2, id1 + 1, "Each registered hotkey should receive an incrementing ID")
    }
}
