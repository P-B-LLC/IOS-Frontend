import Foundation
import XCTest
@testable import RepbaseAPI

final class VideoUploadBodyTests: XCTestCase {
    private func file(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testPullsBoundedChunksAndPreservesAllBytes() async throws {
        let bytes = Data(repeating: 42, count: 200_001)
        let url = try file(bytes)
        var received = Data()
        var chunks = 0
        for try await chunk in VideoUploadBody.file(url, size: bytes.count) {
            XCTAssertLessThanOrEqual(chunk.count, 65_536)
            received.append(contentsOf: chunk)
            chunks += 1
        }
        XCTAssertEqual(received, bytes)
        XCTAssertEqual(chunks, 4)
    }

    func testRejectsFilesChangedAfterValidation() async throws {
        for expectedSize in [2, 8] {
            let url = try file(Data(repeating: 1, count: 4))
            do {
                for try await _ in VideoUploadBody.file(url, size: expectedSize) {}
                XCTFail("Changed file must not produce a successful upload body")
            } catch { XCTAssertTrue(error is CocoaError) }
        }
    }
}
