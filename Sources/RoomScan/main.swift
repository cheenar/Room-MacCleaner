import Foundation
import RoomCore

let args = Array(CommandLine.arguments.dropFirst())
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
