import XCTest
@testable import AdminDomain

final class ContractFixtureTests: XCTestCase {
    private struct TimestampFixture: Decodable {
        let timestamp: Date
    }

    private let contractFixtureNames = [
        "deal-sync-native", "error-conflict", "error-forbidden",
        "error-maintenance", "error-rate-limit", "error-unauthorized",
        "error-upstream-timeout", "external-sync-native", "health-online",
        "overview-stale", "services-empty",
    ]

    func testContractFixturesDecodeWithUTCTimestamps() throws {
        XCTAssertEqual(contractFixtureNames.count, 11)
        let bundle = Bundle(for: Self.self)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for name in contractFixtureNames {
            let fixture = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"), "Missing contract fixture: \(name).json")
            let data = try Data(contentsOf: fixture)
            XCTAssertNoThrow(try decoder.decode(TimestampFixture.self, from: data), fixture.lastPathComponent)
        }
    }

    func testSchemaSpecificDealSyncResourcesAreNotTimestampFixtures() throws {
        let bundle = Bundle(for: Self.self)
        for name in ["deal-sync-success"] {
            XCTAssertNotNil(bundle.url(forResource: name, withExtension: "json"))
            XCTAssertFalse(contractFixtureNames.contains(name))
        }
    }
}

final class NativeProgramFixtureTests: XCTestCase {
    func testDealSyncNativeFixtureDecodes() throws {
        let snapshot = try decodeFixture(ProgramSnapshot.self, named: "deal-sync-native")
        XCTAssertEqual(snapshot.id, .dealSync)
        XCTAssertEqual(snapshot.collections.first?.id, "destinations")
    }

    func testExternalSyncNativeFixtureDecodes() throws {
        let snapshot = try decodeFixture(ProgramSnapshot.self, named: "external-sync-native")
        XCTAssertEqual(snapshot.id, .externalSync)
        XCTAssertEqual(snapshot.collections.first?.id, "deal-lists")
    }

    private func decodeFixture<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
        let bundle = Bundle(for: NativeProgramFixtureTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))
        return try JSONDecoder.api.decode(type, from: Data(contentsOf: url))
    }
}
