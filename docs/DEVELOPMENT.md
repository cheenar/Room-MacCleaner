# Developing Room

Room is a native macOS 14+ application and read-only CLI built with Swift 6. It has no third-party package dependencies.

## Build and install

```sh
make app                # dist/Room.app, including room-scan
make install            # ~/Applications/Room.app and ~/.local/bin/room-scan
make test               # core tests and shell syntax checks
make test-packaging     # isolated install/reinstall/uninstall checks
make lint               # strict Swift formatting and shell syntax
```

`make test-packaging` uses disposable directories, including paths with spaces, and checks that unrelated apps and commands cannot be overwritten. It does not install into your usual Applications directory or change keychain trust.

The existing `scripts/build.sh --install` entry point also works. The app bundle includes both executables, so the installed CLI does not depend on the source checkout or `.build` folder.

## Local signing

The signing and install workflow is adapted from Iridium. Every build resolves an identity in this order:

1. An explicit `SIGN_ID` override, which must be a valid code-signing identity.
2. **Room Local Signing**, when installed.
3. **Iridium Local Signing**, when already installed.
4. Ad-hoc signing, with a notice explaining how to set up a stable identity.

A certificate-based designated requirement uses the app identifier and signing certificate rather than one build’s code hash. Reusing the same certificate keeps that requirement stable across rebuilds. Room keeps the bundle identifier `local.peter.room` when updating an existing installation.

Create a dedicated identity once:

```sh
make signing-identity
make install
```

This explicit setup command creates a ten-year self-signed certificate for code signing, imports it into your login keychain with a non-exportable private key, allows `/usr/bin/codesign` to use it, and requests code-signing trust for your user. macOS may ask for your password. Normal builds and installs do not create identities or change trust.

Undo it in **Keychain Access → login → My Certificates → Room Local Signing**. Deleting the identity removes it from future signing choices. After switching from an ad-hoc build, macOS may require granting the app access again.

To choose an identity explicitly, or to use ad-hoc signing:

```sh
make install SIGN_ID="Room Local Signing"
make app SIGN_ID=-
```

Local signing is for builds on your own Mac. It does not produce a Developer ID notarized release for public distribution.

## Custom install locations

```sh
make install INSTALL_DIR="$HOME/Applications" PREFIX="$HOME/.local"
make uninstall INSTALL_DIR="$HOME/Applications" PREFIX="$HOME/.local"
```

The installer verifies signatures, replaces only a Room bundle with the matching identifier, and creates a symlink to the CLI inside the installed bundle. It refuses to overwrite an unrelated `room-scan` command. Uninstall removes the app and its own CLI link; scan history, restore receipts and signing identities stay in place.

## Scanning and cleanup

Default roots are your home folder, `/Applications`, `/Library`, `/private/var`, `/Users/Shared`, `/opt` and `/usr/local`. Choose another folder or volume explicitly to inspect it. iCloud Drive and File Provider roots are skipped during the default scan to avoid waiting on cloud metadata. Access lists protected paths and other coverage gaps.

Sizes use allocated disk blocks. Hard links count once, symlinks are not followed, and a scan does not cross mounted volumes. Folder totals include all readable contents; the map lists children using at least 1 MB. APFS clones, snapshots, inaccessible paths, volatile data and purgeable storage can affect accounting and the space recovered.

Known package download and compiler caches are labeled rebuildable. Other app caches and project outputs require review: they can contain IDE Local History, offline files, model downloads, runtimes, screenshots, test evidence or edited package checkouts. Dependencies inside hidden tool and extension directories are excluded.

Cleanup accepts only candidates in a completed scan. It checks paths against the cleanup policy, rejects redirected paths and overlapping selections, compares object identity and metadata, and repeats the selected tree’s metadata signature. Changed items require another scan. All selected items pass preflight before the first move.

Cleanup uses macOS `FileManager.trashItem` and saves its resulting paths in `~/Library/Application Support/Room/History.json` with user-only permissions. Restore does not overwrite new data at the original path. Emptying Trash is a separate Finder action. Deleting synced personal files can propagate to other devices.

## CLI

```sh
room-scan                         # default Mac scan
room-scan ~/Projects ~/Downloads  # selected folders
room-scan --json ~/Downloads      # structured report
room-scan --progress ~/Projects   # progress on stderr
```

The CLI never changes or deletes files. JSON reports contain local paths and metadata; keep exported reports private.

## Validation

Core tests exercise filesystem accounting, cleanup classification, changed or replaced files, symlinks, redirected parents, sparse files, hard links, installed-tool dependencies, cancelled scans, batch preflight, restore protection, cloud-folder handling, and a native Trash/restore cycle using generated data.

Packaging checks verify identity resolution, CLI execution, stable designated requirements, signature validity, install/reinstall/uninstall, paths with spaces and conflict protection. UI changes are checked in the native app; broad window-manager e2e tests are not part of Room’s workflow.
