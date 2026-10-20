import Darwin
import Foundation

public enum CandidateKind: String, Codable, CaseIterable, Sendable {
  case build = "Build output"
  case cache = "Caches"
  case reviewCache = "App caches to review"
  case projectArtifacts = "Project output to review"
  case logs = "Logs"
  case installer = "Installers"
  case archive = "Developer archives"
  case largeFile = "Large files"
  public var rebuildable: Bool { self == .build || self == .cache || self == .logs }
  public var symbol: String {
    switch self {
    case .build, .projectArtifacts: "hammer.fill"
    case .cache, .reviewCache: "shippingbox.fill"
    case .logs: "doc.text.fill"
    case .installer: "shippingbox.and.arrow.backward.fill"
    case .archive: "archivebox.fill"
    case .largeFile: "doc.fill"
    }
  }
}

public struct FileStamp: Codable, Equatable, Sendable {
  public let device: Int32
  public let inode: UInt64
  public let mode: UInt16
  public let size: Int64
  public let blocks: Int64
  public let modified: Int64
  public let changed: Int64
  public static func read(_ path: String) throws -> FileStamp {
    try inspect(path).stamp
  }
  static func inspect(_ path: String) throws -> (stamp: FileStamp, links: UInt16) {
    var info = stat()
    guard lstat(path, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    let stamp = FileStamp(
      device: info.st_dev, inode: info.st_ino, mode: info.st_mode, size: info.st_size,
      blocks: info.st_blocks,
      modified: Int64(info.st_mtimespec.tv_sec) &* 1_000_000_000
        &+ Int64(info.st_mtimespec.tv_nsec),
      changed: Int64(info.st_ctimespec.tv_sec) &* 1_000_000_000 &+ Int64(info.st_ctimespec.tv_nsec))
    return (stamp, info.st_nlink)
  }
  public var isDirectory: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFDIR) }
  public var isRegular: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFREG) }
  public var isSymlink: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFLNK) }
  var hashValueStable: UInt64 {
    [
      UInt64(bitPattern: Int64(device)), inode, UInt64(mode), UInt64(bitPattern: size),
      UInt64(bitPattern: blocks), UInt64(bitPattern: modified), UInt64(bitPattern: changed),
    ]
    .reduce(14_695_981_039_346_656_037) { ($0 ^ $1) &* 1_099_511_628_211 }
  }
}

public struct Candidate: Identifiable, Codable, Sendable {
  public var id: String { path }
  public let path: String
  public let bytes: Int64
  public let kind: CandidateKind
  public let reason: String
  public let modified: Date
  public let stamp: FileStamp
  public let treeSignature: UInt64
  public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public struct StorageNode: Identifiable, Codable, Sendable {
  public var id: String { path }
  public let path: String
  public let bytes: Int64
  public let isDirectory: Bool
  public let children: [StorageNode]
  public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public struct ScanIssue: Codable, Identifiable, Sendable {
  public var id: String { path }
  public let path: String
  public let message: String
}

public struct ScanReport: Codable, Sendable {
  public let date: Date
  public let roots: [StorageNode]
  public let candidates: [Candidate]
  public let issues: [ScanIssue]
  public let filesVisited: Int
  public let cancelled: Bool
  public var scannedBytes: Int64 { roots.reduce(0) { $0 + $1.bytes } }
  public var rebuildableBytes: Int64 {
    candidates.filter { $0.kind.rebuildable }.reduce(0) { $0 + $1.bytes }
  }
}

public struct DiskSpace: Sendable {
  public let total: Int64
  public let free: Int64
  public let availableForImportantUsage: Int64?
  public static func current(at url: URL = FileManager.default.homeDirectoryForCurrentUser)
    -> DiskSpace
  {
    var fs = statvfs()
    guard statvfs(url.path, &fs) == 0 else {
      return DiskSpace(total: 0, free: 0, availableForImportantUsage: nil)
    }
    let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return DiskSpace(
      total: Int64(fs.f_blocks) * Int64(fs.f_frsize), free: Int64(fs.f_bavail) * Int64(fs.f_frsize),
      availableForImportantUsage: values?.volumeAvailableCapacityForImportantUsage)
  }
}

public func formatBytes(_ bytes: Int64) -> String {
  ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

public func displayPath(_ path: String) -> String {
  let home = FileManager.default.homeDirectoryForCurrentUser.path
  return path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
}

public final class ScanCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  public init() {}
  public func cancel() {
    lock.lock()
    value = true
    lock.unlock()
  }
  public var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}
