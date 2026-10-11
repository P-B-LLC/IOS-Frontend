import Foundation
import OpenAPIRuntime

/// Pull-based file reads keep a bounded upload from becoming a large Data allocation.
public enum VideoUploadBody {
    public static func file(_ url: URL, size: Int) -> HTTPBody {
        HTTPBody(FileBytes(url: url, size: size), length: .known(Int64(size)), iterationBehavior: .single)
    }

    private struct FileBytes: AsyncSequence, Sendable {
        typealias Element = ArraySlice<UInt8>
        let url: URL
        let size: Int

        func makeAsyncIterator() -> Iterator { Iterator(url: url, remaining: size) }

        struct Iterator: AsyncIteratorProtocol {
            let url: URL
            var remaining: Int
            private var reader: Reader?

            init(url: URL, remaining: Int) { self.url = url; self.remaining = remaining }

            mutating func next() async throws -> Element? {
                try Task.checkCancellation()
                if reader == nil { reader = try Reader(url: url) }
                guard let reader else { return nil }
                guard remaining >= 0 else { throw CocoaError(.fileReadCorruptFile) }
                if remaining == 0 {
                    guard try reader.handle.read(upToCount: 1)?.isEmpty != false else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    return nil
                }
                guard let bytes = try reader.handle.read(upToCount: Swift.min(65_536, remaining)), !bytes.isEmpty else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                remaining -= bytes.count
                return Array(bytes)[...]
            }
        }

        private final class Reader {
            let handle: FileHandle
            init(url: URL) throws { handle = try FileHandle(forReadingFrom: url) }
            deinit { try? handle.close() }
        }
    }
}
