# Room

## October 20: focused interface and local distribution

Engineering review: adapt Iridium's stable certificate signing, user Applications install and CLI symlink. Reuse an existing trusted local identity without changing keychain trust; provide an explicit one-time identity setup command. Preserve the bundle identifier and user data. Test installs in disposable directories, including paths with spaces and conflicting files.

Product review: use page names as headings, remove slogans and repeated reassurance, and keep decision-making information in Details, Review and Access. Keep the free-space distinction and review-before-Trash behavior. The README is the product introduction; engineering and validation notes live separately. SEO and advertising placement do not apply to a native app.

Reviewed layout before implementation:

```
┌──────────────────────────────────────────────────────────────────────────┐
│ ● ● ●   Room                         [Storage] [Folder…] [Scan Mac]      │
├──────────────┬───────────────────────────────────────────────────────────┤
│ Room         │ Cleanup                                      Last scan   │
│              │ Macintosh HD                              31 GB free     │
│ Cleanup      │ ███████████████████████████████░░░                       │
│ Large files  │ 463 GB used of 494 GB           111 GB with purgeable     │
│ Storage map  │                                                           │
│ Access       │ [Rebuildable 2 GB] [Review 28 GB] [Scanned 250 GB]        │
│ History      │                                                           │
│              │ [Search…]                  [All types ▾]          [☑ ▾] │
│              │ 24 items                                   Largest first │
│              │ □  Package cache                    1.2 GB   [ⓘ] [↗]    │
│              │    ~/Library/Caches/…                                    │
│              │ □  Project output                     800 MB [ⓘ] [↗]    │
│              ├───────────────────────────────────────────────────────────┤
│              │ 0 selected                         [Open Trash] [Review]  │
└──────────────┴───────────────────────────────────────────────────────────┘
```

Harness review: retain core cleanup tests and add isolated packaging checks. Verify certificate-based designated requirements, CLI help, strict signatures and the installed native interface. No window-manager e2e or keychain trust changes are needed.

## Original implementation

Native, local macOS disk utility. No network, daemon, administrator helper, or automatic cleanup.

Engineering: one read-only filesystem traversal, allocated disk blocks, no following symlinks or crossing volumes. Keep the UI responsive with background scanning and cancellation. Cleanup accepts only items from a completed scan, revalidates their identity and entire metadata tree, rejects protected paths and overlapping selections, and uses Finder Trash. Permanent space recovery is a separate Finder action.

Product design reviewed before implementation:

```
┌────────────────────────────────────────────────────────────────────────┐
│ ● ● ●     Room                                  [Scan Mac] [Folder…]   │
├────────────────┬───────────────────────────────────────────────────────┤
│                │ Make a little room.                                   │
│ Cleanup        │ Macintosh HD    14 GB free / 494 GB                   │
│ Large files    │ ████████████████████████████████░                     │
│ Storage map    │                                                       │
│ Access         │ [Rebuildable  24 GB] [Review first  18 GB] [Scanned…]   │
│                │                                                       │
│                │ [Search…] [All types ▾]               Largest first   │
│                │ □  Xcode build output                  12.4 GB   ⓘ   │
│                │    ~/Library/Developer/Xcode/DerivedData/…             │
│                │ □  Package cache                        6.2 GB   ⓘ   │
│                │    Can be downloaded again. Close the related app.    │
│                ├───────────────────────────────────────────────────────┤
│ Local only     │ 2 selected · 18.6 GB             [Review selection]   │
└────────────────┴───────────────────────────────────────────────────────┘
```

Native semantic colors, system typography, warm orange accent, resizable split navigation, keyboard-accessible controls. Nothing selected by default. Review shows every path, its reason, and a reminder that Trash still occupies disk space. A receipt supports restoring the last batch while items remain in Trash. SEO and advertising do not apply to this personal desktop utility.

Harness review: core tests exercise filesystem safety, sparse files, hard links, symlinks, metadata changes, nested selections, classification, and cleanup/restore with disposable fixtures. A CLI uses the same scanner for read-only live verification. No new shared repository tooling is needed.
