import Foundation

/// Where a window was last seen, kept for as long as the window exists.
///
/// `AeroSpace` stops reporting a window the moment it is minimized and exposes
/// no placeholder to ask about one, so this is the only record that a minimized
/// window belongs to a workspace at all.
struct MinimizedWindowNote: Codable, Equatable {
    let id: Int
    let workspace: String
    let title: String
    let appName: String?
    let bundleID: String?
    let monitorScreenID: Int?
}

/// The bookkeeping behind minimized windows, with no window server and no
/// drawing in it.
enum MinimizedWindowLedger {
    /// What one pass over the notes decided.
    struct Outcome: Equatable {
        /// The notes to carry into the next pass. Windows that no longer exist
        /// are gone from it.
        let keep: [Int: MinimizedWindowNote]
        /// The notes to draw back into their workspaces, in a stable order.
        let restore: [MinimizedWindowNote]
    }

    /// Folds this pass's reported windows into the notes, overwriting whatever
    /// was known about each of them.
    static func noting(
        _ notes: [Int: MinimizedWindowNote], reported: [MinimizedWindowNote]
    ) -> [Int: MinimizedWindowNote] {
        var result = notes
        for note in reported { result[note.id] = note }
        return result
    }

    /// Decides which unreported windows are still real.
    ///
    /// `liveOwners` is every window on the system by identifier, with the name
    /// of the application that owns it. The owner is checked as well as the
    /// identifier because the window server reuses identifiers after a restart
    /// and these notes outlive one, so an identifier alone would eventually
    /// draw one application's icon for another's window.
    ///
    /// `minimizedTitles` is what each application says is minimized right now,
    /// by application name. This is the test that says a window is *minimized*
    /// rather than merely still allocated, and the window server cannot answer
    /// it: closing a window does not destroy it, so `Google Drive`'s main
    /// window sat in the list at layer zero and off screen for as long as the
    /// application ran, exactly like a minimized one. A note kept passing on
    /// that alone and its workspace grew a pill for a window that was not
    /// there and could not be clicked back. An application's own window list
    /// does not contain a closed window at all, so asking it settles the
    /// question.
    ///
    /// A note with no application name cannot be looked up that way and is
    /// matched on the identifier alone, which is the best that can be done for
    /// it.
    static func reconcile(
        notes: [Int: MinimizedWindowNote],
        reported: [MinimizedWindowNote],
        liveOwners: [Int: String],
        minimizedTitles: [String: Set<String>]
    ) -> Outcome {
        let updated = noting(notes, reported: reported)
        let listed = Set(reported.map(\.id))

        var keep: [Int: MinimizedWindowNote] = [:]
        var restore: [MinimizedWindowNote] = []
        for (id, note) in updated {
            if listed.contains(id) {
                keep[id] = note
                continue
            }
            guard let owner = liveOwners[id] else { continue }
            if let appName = note.appName {
                guard appName == owner else { continue }
                guard
                    minimizedTitles[appName]?.contains(note.title) == true
                else { continue }
            }
            keep[id] = note
            restore.append(note)
        }
        return Outcome(keep: keep, restore: restore.sorted { $0.id < $1.id })
    }

    /// Which applications own notes that were not reported this pass.
    ///
    /// Asking an application for its windows is not free, and the answer is
    /// only needed for the few that have a window missing, so the caller asks
    /// these and no others.
    static func unreportedOwners(
        notes: [Int: MinimizedWindowNote], reported: [MinimizedWindowNote]
    ) -> Set<String> {
        let listed = Set(reported.map(\.id))
        return Set(
            notes.values
                .filter { !listed.contains($0.id) }
                .compactMap(\.appName))
    }

    /// Whether the window server has to be asked at all.
    ///
    /// Listing every window on the system is not free and the usual answer is
    /// that nothing is missing, so the caller skips the call when this is false.
    static func hasUnreported(
        notes: [Int: MinimizedWindowNote], reported: [MinimizedWindowNote]
    ) -> Bool {
        let listed = Set(reported.map(\.id))
        return notes.keys.contains { !listed.contains($0) }
    }
}
