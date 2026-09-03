import Foundation

/// What to write on a workspace card: the application's name, or the window's
/// own title when the name would not tell two windows apart.
///
/// The rule is the useful one, and it had a hole. With one window of an
/// application the name is what identifies it. With several, the name is the
/// same on all of them, so the title is the only thing that separates the one
/// in focus from its siblings.
///
/// The hole: a title is whatever the application chose to put there, and a
/// terminal puts its working directory. Open a second terminal window in the
/// same workspace and the card stopped saying `WezTerm` and started saying
/// `~`, which identifies nothing and reads as a glitch. A title that short is
/// not a title, so the name is better even when it is shared.
enum WindowLabel {
    /// The shortest a title can be and still be worth showing in place of the
    /// application's name. Two, so `~` and a bare `/` fall back and anything a
    /// person would recognise, `vi`, `Go`, does not.
    private static let shortestUsefulTitle = 2

    static func text(
        applicationName: String?, title: String?, hasSiblings: Bool,
        alwaysUseApplicationName: Bool
    ) -> String {
        let name = applicationName ?? ""
        guard hasSiblings, !alwaysUseApplicationName else { return name }

        let trimmed = (title ?? "").trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= shortestUsefulTitle else { return name }
        return trimmed
    }
}
