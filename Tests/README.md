# Tests

Runs with the Swift toolchain alone, no Xcode:

```bash
cd Tests && swift test
```

On a machine with only Command Line Tools installed, the `Testing` framework is
not on the default search path, so point at it:

```bash
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
DYLD_FRAMEWORK_PATH=$F DYLD_LIBRARY_PATH=$L swift test \
  -Xswiftc -F -Xswiftc $F \
  -Xlinker -F -Xlinker $F \
  -Xlinker -rpath -Xlinker $F \
  -Xlinker -rpath -Xlinker $L
```

## Why a package rather than an Xcode test target

Stege is developed on a machine with no Xcode, so an `xcodebuild test` target
could not be run before pushing it. This can.

`Sources/StegeCore` is symlinks into `Stege/Core`, so there is one copy of each
file and the application and the tests cannot drift apart. Only logic with no
AppKit or SwiftUI in it lives there. A widget's drawing is not testable this
way, and pretending otherwise would mean a second copy of the rules.
