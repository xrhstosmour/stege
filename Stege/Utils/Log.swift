import os

/// Where the application says what went wrong.
///
/// These lines used to be `print`, which writes to standard output. A bundled
/// application launched from Finder has nowhere useful to send that, so every
/// one of them was written into the void: a window manager that is not running
/// printed once a second to nobody, and the one time a failure needed
/// diagnosing there was nothing to read.
///
/// The unified log is where macOS keeps this, and it can be read back with:
///
///     log stream --predicate 'subsystem == "com.xrhstosmour.stege"'
///
/// Interpolated values are redacted by default, which is the right way round:
/// window titles and network names pass through here and none of them belong
/// in a system-wide log. Only the parts that are safe to read are marked
/// public.
enum Log {
    private static let subsystem = "com.xrhstosmour.stege"

    static let configuration = Logger(
        subsystem: subsystem, category: "configuration")
    static let spaces = Logger(subsystem: subsystem, category: "spaces")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let shortcut = Logger(subsystem: subsystem, category: "shortcut")
}
