import Foundation

extension UUID {
    /// The same id every time for a given server row.
    ///
    /// Models here carry a client-side UUID and take a fresh one whenever
    /// they are decoded, so reading a collection again renamed everything in
    /// it. Anything holding an id across that refetch lost what it was
    /// pointing at. The visible case was the meal page: applying a saved
    /// meal refetches the day, every meal came back with a new id, and the
    /// open page drew "Meal Not Found" over a meal that was still there.
    ///
    /// The quiet cases are worse, because they do not say anything. A
    /// `ForEach` rebuilds and re-animates rows that did not change. A sheet
    /// bound to `item:` closes because its item stopped existing. A
    /// selection clears itself.
    ///
    /// Derived rather than random: the same server row has to produce the
    /// same UUID on this launch and the next. The value is only ever
    /// compared, never parsed, so packing the integer into the low eight
    /// bytes is enough to be unique per row.
    ///
    /// Pass the id of the row the model *is*, which is not always the one it
    /// points at. Two of the same exercise in one workout are two rows; they
    /// share an exercise id and differ by the id joining each into the
    /// workout, so that is the one that identifies them.
    nonisolated static func stable(forServerID serverID: Int) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: UInt64(bitPattern: Int64(serverID)).bigEndian) { raw in
            bytes.replaceSubrange(8..<16, with: raw)
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
