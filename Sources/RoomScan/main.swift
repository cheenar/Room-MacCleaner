import Foundation
import RoomCore

let args = Array(CommandLine.arguments.dropFirst())
if args.contains("--help") || args.contains("-h") {
  print(
    """
    Room — read-only disk usage scanner

    Usage: room-scan [--json] [--progress] [folder ...]

      --json       Export file sizes, paths and cleanup candidates as JSON.
      --progress   Write scan progress to standard error.
      --version    Print the installed version.
      --help       Show this help.

    With no folder, scans common storage locations on this Mac.
    This command never changes or deletes files.
    """)
  exit(0)
}
if args.contains("--version") {
  let contents = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    .deletingLastPathComponent().deletingLastPathComponent()
  let info = NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist"))
  print("Room \(info?["CFBundleShortVersionString"] as? String ?? "1.0")")
  exit(0)
}
if let unknown = args.first(where: { $0.hasPrefix("-") && !["--json", "--progress"].contains($0) })
{
  FileHandle.standardError.write(Data("Unknown option: \(unknown). Use room-scan --help.\n".utf8))
  exit(64)
}
let json = args.contains("--json")
let roots = args.filter { !$0.hasPrefix("--") }.map { URL(fileURLWithPath: $0) }
let verbose = args.contains("--progress")
let scanner = DiskScanner { count, path in
  if verbose {
    FileHandle.standardError.write(Data("\(count)\t\(displayPath(path))\n".utf8))
  }
}
let result = scanner.scan(roots: roots.isEmpty ? DiskScanner.defaultRoots : roots)
if json {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  encoder.dateEncodingStrategy = .iso8601
  FileHandle.standardOutput.write(try encoder.encode(result))
} else {
  let disk = DiskSpace.current()
  print(
    "Room · read-only disk scan\n\(formatBytes(disk.free)) free of \(formatBytes(disk.total))\n\(result.filesVisited) entries · \(result.issues.count) coverage issues\n"
  )
  for node in result.roots { print("\(formatBytes(node.bytes))\t\(displayPath(node.path))") }
  print("\nCleanup candidates (nothing deleted):")
  for item in result.candidates.prefix(60) {
    print("\(formatBytes(item.bytes))\t\(item.kind.rawValue)\t\(displayPath(item.path))")
  }
}
