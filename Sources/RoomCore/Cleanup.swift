import Foundation

public struct TrashReceipt: Codable, Identifiable, Sendable {
  public let id: UUID
  public let original: String
  public let trashed: String
  public let bytes: Int64
  public let date: Date
}

public struct CleanupResult: Sendable {
  public var receipts: [TrashReceipt] = []
  public var failures: [String] = []
}

public struct CleanupService: Sendable {
  public let policy: CleanupPolicy
  private let mover: @Sendable (URL) throws -> URL
  public init(
    policy: CleanupPolicy = CleanupPolicy(),
    mover: @escaping @Sendable (URL) throws -> URL = { url in
      var destination: NSURL?
      try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
      guard let destination else { throw CocoaError(.fileNoSuchFile) }
      return destination as URL
    }
  ) {
    self.policy = policy
    self.mover = mover
  }
  public func trash(_ selected: [Candidate], from report: ScanReport) throws -> CleanupResult {
    guard !report.cancelled else { throw CleanupError.cancelledScan }
    let known = Dictionary(uniqueKeysWithValues: report.candidates.map { ($0.path, $0) })
    let paths = Set(selected.map(\.path))
    guard paths.count == selected.count,
      !paths.contains(where: { path in paths.contains { $0 != path && path.hasPrefix($0 + "/") } })
    else { throw CleanupError.overlap }
    // Preflight the entire selection before moving the first item.
    for item in selected {
      guard let scanned = known[item.path], scanned.stamp == item.stamp,
        scanned.treeSignature == item.treeSignature, scanned.kind == item.kind
      else { throw CleanupError.unsafePath(item.path) }
      try policy.validate(scanned)
    }
    var result = CleanupResult()
    for item in selected {
      do {
        try policy.validate(item)
        let trashURL = try mover(URL(fileURLWithPath: item.path))
        result.receipts.append(
          TrashReceipt(
            id: UUID(), original: item.path, trashed: trashURL.path, bytes: item.bytes, date: Date()
          ))
      } catch { result.failures.append("\(displayPath(item.path)): \(error.localizedDescription)") }
    }
    return result
  }
  public func restore(_ receipt: TrashReceipt) throws {
    let source = URL(fileURLWithPath: receipt.trashed).standardizedFileURL
    let trash = URL(fileURLWithPath: policy.home).appendingPathComponent(".Trash").path
    guard source.path.hasPrefix(trash + "/"), source.path == receipt.trashed,
      let relative = policy.relative(receipt.original), !relative.isEmpty,
      !FileManager.default.fileExists(atPath: receipt.original),
      URL(fileURLWithPath: receipt.original).resolvingSymlinksInPath().path == receipt.original
    else { throw CleanupError.unsafePath(receipt.original) }
    try FileManager.default.moveItem(at: source, to: URL(fileURLWithPath: receipt.original))
  }
}
