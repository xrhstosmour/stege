import Testing

@testable import StegeCore

struct WorkspaceOrderTests {
    /// Plain string comparison sorts "10" before "2" and "6", which is the
    /// bug this exists to fix.
    @Test func numericIdentifiersSortNumerically() {
        let sorted = ["10", "6", "2", "1"].sorted(
            by: WorkspaceOrder.areInIncreasingOrder)
        #expect(sorted == ["1", "2", "6", "10"])
    }

    /// Aerospace lets a workspace be renamed to any string, so the compare
    /// must not crash or misbehave on non-numeric identifiers.
    @Test func nonNumericIdentifiersFallBackToTextOrder() {
        let sorted = ["work", "code", "browser"].sorted(
            by: WorkspaceOrder.areInIncreasingOrder)
        #expect(sorted == ["browser", "code", "work"])
    }

    @Test func aMixOfNumericAndNamedWorkspacesDoesNotCrash() {
        let sorted = ["10", "work", "2"].sorted(
            by: WorkspaceOrder.areInIncreasingOrder)
        #expect(sorted.count == 3)
    }
}
