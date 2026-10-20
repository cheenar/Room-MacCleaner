# Room

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
