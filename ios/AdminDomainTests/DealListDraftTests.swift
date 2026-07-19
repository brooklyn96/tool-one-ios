import XCTest
@testable import AdminDomain

final class DealListDraftTests: XCTestCase {
    func testRequiredFieldsMatchPrimaryWebWorkflow() {
        var draft = DealListDraft()
        XCTAssertFalse(draft.isReadyToSave)

        draft.input.name = "Diệp Lê"
        draft.input.sourceSpreadsheetId = "source"
        draft.input.sourceSheetName = "Update model level"
        draft.input.targetSpreadsheetId = "target"
        draft.input.targetSheetName = "25.07 Pool Deal INT"

        XCTAssertTrue(draft.isReadyToSave)
    }

    func testAdvancedMappingsAreOnlyAppliedWhenProvided() {
        var draft = DealListDraft()
        draft.sourceMappingText = "sku=SKU\nprice = Giá"
        draft.targetMappingText = "status=Trạng thái"

        draft.applyAdvancedMappings()

        XCTAssertEqual(draft.input.sourceColumnMapping?["sku"], "SKU")
        XCTAssertEqual(draft.input.sourceColumnMapping?["price"], "Giá")
        XCTAssertEqual(draft.input.targetColumnMapping?["status"], "Trạng thái")
    }
}
