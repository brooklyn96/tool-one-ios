import XCTest
@testable import AdminDomain

final class APIDateDecodingTests: XCTestCase {
    private struct Payload: Decodable {
        let expiresAt: Date
    }

    func testDecodesServerTimestampWithFractionalSeconds() throws {
        let data = Data(#"{"expiresAt":"2026-07-17T10:52:05.447Z"}"#.utf8)
        XCTAssertNoThrow(try JSONDecoder.api.decode(Payload.self, from: data))
    }

    func testDecodesTimestampWithoutFractionalSeconds() throws {
        let data = Data(#"{"expiresAt":"2026-07-17T10:52:05Z"}"#.utf8)
        XCTAssertNoThrow(try JSONDecoder.api.decode(Payload.self, from: data))
    }
}
