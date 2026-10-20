import Darwin
import Foundation

public final class DiskScanner {
  public static var defaultRoots: [URL] {
    [FileManager.default.homeDirectoryForCurrentUser]
      + ["/Applications", "/Library", "/private/var", "/Users/Shared", "/opt", "/usr/local"].map {
        URL(fileURLWithPath: $0)
      }
  }
  private let policy: CleanupPolicy
  private let cancellation: ScanCancellation
  private let progress: @Sendable (Int, String) -> Void
  private var candidates: [Candidate] = []
  private var issues: [ScanIssue] = []
  private var visited = 0
  private var hardLinks = Set<String>()
  private var lastProgress = Date.distantPast
  private var rootPaths = Set<String>()
  public init(
    policy: CleanupPolicy = CleanupPolicy(), cancellation: ScanCancellation = ScanCancellation(),
    progress: @escaping @Sendable (Int, String) -> Void = { _, _ in }
  ) {
    self.policy = policy
    self.cancellation = cancellation
    self.progress = progress
  }
  public func scan(roots: [URL] = DiskScanner.defaultRoots) -> ScanReport {
    candidates = []
    issues = []
    hardLinks = []
    visited = 0
    let paths = Array(Set(roots.map { $0.standardizedFileURL.path })).sorted()
    let disjoint = paths.filter { path in
      !paths.contains { $0 != path && path.hasPrefix($0 == "/" ? "/" : $0 + "/") }
    }
    rootPaths = Set(disjoint)
    var nodes: [StorageNode] = []
    for path in disjoint {
      guard !cancellation.isCancelled else { break }
      guard let stamp = try? FileStamp.read(path) else {
        issues.append(.init(path: path, message: "Cannot read this location."))
        continue
      }
      if stamp.isSymlink {
        issues.append(
          .init(
            path: path, message: "Symbolic link skipped. Choose its original folder to scan it."))
        continue
      }
      if let result = autoreleasepool(invoking: {
        walk(path, device: stamp.device, suppressed: false)
      }) {
        nodes.append(result.node)
      }
    }
    progress(visited, "Scan complete")
    return ScanReport(
      date: Date(), roots: nodes.sorted { $0.bytes > $1.bytes },
      candidates: candidates.sorted { $0.bytes > $1.bytes }, issues: issues, filesVisited: visited,
      cancelled: cancellation.isCancelled)
  }

  private struct Result {
    let node: StorageNode
    let signature: UInt64
    let complete: Bool
  }
  private func walk(_ path: String, device: Int32, suppressed: Bool) -> Result? {
    if cancellation.isCancelled { return nil }
    let cloudRoots = [
      policy.home + "/Library/Mobile Documents", policy.home + "/Library/CloudStorage",
    ]
    if cloudRoots.contains(path), !rootPaths.contains(path) {
      issues.append(
        .init(
          path: path,
          message:
            "Cloud-managed folder skipped to avoid requesting cloud metadata. Manage local downloads in Finder, or choose this folder explicitly to inspect it."
        ))
      return nil
    }
    let stamp: FileStamp
    let links: UInt16
    do {
      (stamp, links) = try FileStamp.inspect(path)
    } catch {
      issues.append(.init(path: path, message: error.localizedDescription))
      return nil
    }
    if stamp.isSymlink {
      return Result(
        node: StorageNode(path: path, bytes: 0, isDirectory: false, children: []),
        signature: stamp.hashValueStable, complete: true)
    }
    guard stamp.device == device else {
      issues.append(.init(path: path, message: "Different mounted volume; scan it separately."))
      return nil
    }
    visited += 1
    if Date().timeIntervalSince(lastProgress) > 0.2 {
      progress(visited, path)
      lastProgress = Date()
    }
    let modified = Date(timeIntervalSince1970: Double(stamp.modified) / 1_000_000_000)
    let earlyClass =
      stamp.isDirectory
      ? policy.classification(path: path, isDirectory: true, bytes: Int64.max, modified: modified)
      : nil
    let isContainerCandidate = stamp.isDirectory && earlyClass != nil && !suppressed
    let bundle = [".app", ".photoslibrary", ".backupbundle", ".sparsebundle"].contains {
      path.hasSuffix($0)
    }
    var bytes = stamp.blocks * 512
    if stamp.isRegular && links > 1 {
      let key = "\(stamp.device):\(stamp.inode)"
      if !hardLinks.insert(key).inserted { bytes = 0 }
    }
    var children: [StorageNode] = []
    var hash = stamp.hashValueStable
    var complete = true
    if stamp.isDirectory {
      do {
        let names = try Self.directoryNames(at: path)
        for name in names {
          if cancellation.isCancelled {
            complete = false
            break
          }
          let childPath = (path as NSString).appendingPathComponent(name)
          if let child = autoreleasepool(invoking: {
            walk(
              childPath, device: device, suppressed: suppressed || isContainerCandidate || bundle)
          }) {
            bytes += child.node.bytes
            hash = Self.combine(hash, name: name, signature: child.signature)
            complete = complete && child.complete
            if child.node.bytes >= 1_000_000 { children.append(child.node) }
          } else {
            complete = false
          }
        }
        if try FileStamp.read(path) != stamp {
          complete = false
          issues.append(
            .init(path: path, message: "Changed during scan. Scan again before cleaning."))
        }
      } catch {
        complete = false
        issues.append(.init(path: path, message: error.localizedDescription))
      }
    }
    if complete, !suppressed, bytes >= 1_000_000,
      let (kind, reason) = policy.classification(
        path: path, isDirectory: stamp.isDirectory, bytes: bytes, modified: modified)
    {
      candidates.append(
        Candidate(
          path: path, bytes: bytes, kind: kind, reason: reason, modified: modified, stamp: stamp,
          treeSignature: hash))
    }
    return Result(
      node: StorageNode(
        path: path, bytes: bytes, isDirectory: stamp.isDirectory,
        children: children.sorted { $0.bytes > $1.bytes }), signature: hash, complete: complete)
  }
  private static func combine(_ hash: UInt64, name: String, signature: UInt64) -> UInt64 {
    let named = name.utf8.reduce(hash) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    return (named ^ signature) &* 1_099_511_628_211
  }
  // Read names only. Foundation's bulk metadata enumeration can block for a long
  // time in provider-backed folders. Metadata is collected explicitly with lstat.
  private static func directoryNames(at path: String) throws -> [String] {
    guard let directory = opendir(path) else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { closedir(directory) }
    var names: [String] = []
    while true {
      errno = 0
      guard let entry = readdir(directory) else {
        if errno != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        break
      }
      let length = Int(entry.pointee.d_namlen) + 1
      let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: length) { String(cString: $0) }
      }
      if name != ".", name != ".." { names.append(name) }
    }
    return names.sorted()
  }
  // This repeats the same metadata walk before a cleanup. No file content is read.
  public static func signature(at path: String) throws -> UInt64 {
    let stamp = try FileStamp.read(path)
    var hash = stamp.hashValueStable
    if stamp.isDirectory {
      for name in try directoryNames(at: path) {
        hash = combine(
          hash, name: name,
          signature: try signature(at: (path as NSString).appendingPathComponent(name)))
      }
    }
    return hash
  }
}
