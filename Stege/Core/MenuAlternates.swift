import Foundation

/// Which menu entries are the Option-key version of the one above them.
///
/// The Accessibility API publishes no `isAlternate`, so this infers it from
/// what it does publish: an alternate carries the Option bit in
/// `AXMenuItemCmdModifiers` and shares its command character with the entry
/// immediately above, which does not carry that bit. That is exactly the
/// arrangement `NSMenuItem.isAlternate` is defined for, so the inference and
/// the drawing agree by construction.
enum MenuAlternates {
    /// Only what the decision needs. Titles are here for one reason: an empty
    /// one is a separator.
    struct Item: Equatable {
        let title: String
        let character: String
        let modifiers: Int

        init(title: String, character: String = "", modifiers: Int = 0) {
            self.title = title
            self.character = character
            self.modifiers = modifiers
        }
    }

    /// The Option bit of `AXMenuItemCmdModifiers`.
    static let option = 2

    static func flags(for items: [Item]) -> [Bool] {
        var result = [Bool](repeating: false, count: items.count)
        var previous: Item?
        for (index, item) in items.enumerated() {
            // A separator carries no title, no character and no modifiers, so
            // without this the entry after one would be read as its alternate
            // and hidden behind a key nothing tells the user to hold.
            guard !item.title.isEmpty else {
                previous = nil
                continue
            }
            if let previous, previous.character == item.character,
                item.modifiers & option != 0, previous.modifiers & option == 0
            {
                result[index] = true
            }
            previous = item
        }
        return result
    }
}
