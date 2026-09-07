import Foundation

/// Where a workspace pill sorts among the others, by its own identifier.
///
/// Window managers hand out identifiers as plain digits, "1" through whatever
/// is configured, and Aerospace additionally lets a workspace be renamed to
/// any string. Plain string comparison sorts "10" before "6", so this reads
/// digits as a number, the same way Finder already sorts file names, and
/// falls back to ordinary text order for anything that is not one.
enum WorkspaceOrder {
    static func areInIncreasingOrder(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
}
