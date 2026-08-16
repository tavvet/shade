import XCTest
@testable import Shade

final class ConnectionsSettingsErrorPresentationTests: XCTestCase {
    func testPublishedSaveProblemDoesNotProduceDuplicateOperationMessage() {
        let message = "The disk is full."
        let problem = SSHConnectionsProblem(kind: .save, message: message)

        XCTAssertTrue(
            ConnectionsSettingsErrorPresentation.isMatchingSaveProblem(
                message,
                reportedProblem: problem
            )
        )
        XCTAssertNil(
            ConnectionsSettingsErrorPresentation.operationMessage(
                message,
                reportedProblem: problem
            )
        )
    }

    func testUnreportedOrDifferentOperationProblemRemainsVisible() {
        XCTAssertFalse(
            ConnectionsSettingsErrorPresentation.isMatchingSaveProblem(
                "The selected connection no longer exists.",
                reportedProblem: nil
            )
        )
        XCTAssertEqual(
            ConnectionsSettingsErrorPresentation.operationMessage(
                "The selected connection no longer exists.",
                reportedProblem: nil
            ),
            "The selected connection no longer exists."
        )
        XCTAssertEqual(
            ConnectionsSettingsErrorPresentation.operationMessage(
                "The selected connection no longer exists.",
                reportedProblem: SSHConnectionsProblem(
                    kind: .save,
                    message: "The disk is full."
                )
            ),
            "The selected connection no longer exists."
        )
    }
}
