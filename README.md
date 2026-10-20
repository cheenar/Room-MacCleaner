# Room

A small, native macOS utility for understanding disk usage and reviewing cleanup candidates. SwiftUI, no third-party packages, no network requests, and no background services. macOS 14 or later.

Open `~/Applications/Room.app`. A read-only scan starts on launch. Use Cleanup to review rebuildable files, Large files for personal files and downloaded installers, Storage map to drill into folders, and Access & coverage to see what macOS prevented Room from reading.

Nothing is selected automatically. Select items, choose **Review selection**, inspect the paths and explanations, then choose **Move to Trash**. Close related apps first. Free space increases after you empty Trash in Finder. Cleanup history can restore items still in Trash and will never overwrite a new item at the original location.

## What it finds

- Verified package download caches are labeled rebuildable. Other app cache folders and `~/.cache` entries require review: they can contain IDE local history, model downloads, offline files or installed runtimes.
- Compiler module caches are labeled rebuildable. Other Xcode DerivedData, Swift `.build`, Rust `target`, and `node_modules` beside a project manifest require review: they can contain screenshots, demo output, test evidence, locally edited checkouts or dependencies. Dependencies inside hidden tool and extension directories are excluded.
- Logs over 30 days old, with at least 1 MB allocated.
- Xcode archives and device support, explicitly marked for review.
- Downloaded `.dmg`, `.pkg`, `.iso`, and `.xip` installers.
- Personal files with at least 100 MB allocated, explicitly marked for review.
- Simulator storage is shown with a link to [Apple’s component management guide](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components). Room does not manually delete registered simulator devices or runtime images.

Default scan roots: your home, `/Applications`, `/Library`, `/private/var`, `/Users/Shared`, `/opt`, `/usr/local`. iCloud Drive and File Provider roots are skipped by default because listing their metadata can stall; the coverage view explains the omission. Choose one explicitly with Scan Folder to inspect it. Add any other folder or volume the same way. Cleanup is restricted to recognized candidates within your home directory. System folders and other users are inspection only. Optional Full Disk Access improves coverage; the app explains how to grant it. A stopped scan is partial and cannot be used for cleanup.

## Accounting and safety

Sizes use allocated disk blocks, so sparse files do not count their entire logical capacity. Hard links count once across scan roots. Symlinks are not followed, and the scanner does not cross into another mounted volume. Folder totals include readable contents; the map lists children at least 1 MB in size. APFS clones, snapshots, inaccessible folders, volatile files and purgeable space can cause differences from macOS Storage and from the space ultimately recovered. “Free” and “available for important use” are displayed separately.

Before cleanup, Room checks each path against the cleanup policy and scan report, checks the object identity and metadata, rejects redirected paths and overlapping selections, and repeats a metadata signature of the entire selected tree. Changed items require another scan. All selected items pass preflight before the first move. A running app can still recreate data; closing related apps is recommended.

Cleanup uses [macOS `FileManager.trashItem`](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:)) and records the resulting Trash paths in `~/Library/Application Support/Room/History.json` with user-only permissions. Room does not permanently delete anything or empty Trash. Restore receipts remain local. Deleting synced personal files can propagate to other devices.

## Build and verify

```sh
swift test
zsh scripts/build.sh --install
open "$HOME/Applications/Room.app"
```

The build script creates an ad-hoc signed standalone app in `dist/Room.app` and optionally installs it in your user Applications folder. No Xcode project generation, package downloads or paid signing identity is needed for local use.

Use the same scanner without the UI:

```sh
swift run -c release room-scan
swift run -c release room-scan ~/programming
swift run -c release room-scan --json ~/Downloads
```

The CLI is read-only and has no cleanup command. JSON reports contain local paths and metadata, not file contents. Keep exported reports private.

Core tests cover project-manifest requirements, nested candidate suppression, symlinks, changed or replaced content, redirected parents, sparse files, hard links, secrets and protected paths, old logs, cancelled scans, forged/duplicate selection, whole-batch preflight, overlapping roots, and trash/restore with disposable fixtures.

Verified locally on October 19, 2026: 18 tests pass, including a complete native macOS Trash and restore cycle using generated test data. Release build, strict Swift formatting, plist validation and strict app signature verification pass. Native UI checks confirmed selection, the review sheet, cancellation, folder drill-down and the layout in a narrow tiled window. No existing user files were cleaned during development.

A live default scan completed in 85.7 seconds across 2,599,433 entries, with 164 reported coverage gaps. It found about 46.5 GB in caches, logs and build output, and about 20 GB in device-support data requiring review. These are allocated-size candidates, not a guarantee of recoverable free space. The standalone app occupies approximately 2.8 MB; Swift build artifacts remain visible as rebuildable output in the source project.

The subsequent safety audit tightened that initial classification: unknown app caches and project output now require review, and dependencies belonging to installed tools are excluded. Twenty tests pass, including regressions for editor Local History, screenshots in build folders and hidden tool dependencies. JetBrains documents why its system cache must not be treated as wholly disposable: it also stores [Local History](https://www.jetbrains.com/help/idea/local-history.html).
