import XCTest

@MainActor
func assertThrowsAsync<Value>(
    file: StaticString = #filePath, line: UInt = #line,
    _ operation: @MainActor () async throws -> Value
) async {
    do {
        _ = try await operation()
        XCTFail("Expected an error", file: file, line: line)
    } catch {}
}
