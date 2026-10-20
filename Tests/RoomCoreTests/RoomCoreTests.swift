import Foundation
import XCTest

@testable import RoomCore

final class RoomCoreTests: XCTestCase {
  var home: URL!
  var policy: CleanupPolicy { CleanupPolicy(home: home.path) }
  override func setUpWithError() throws {
    home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(
      "RoomTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }
  @discardableResult func file(_ relative: String, bytes: Int = 1_100_000) throws -> URL {
    let url = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 65, count: bytes).write(to: url)
    return url
  }
  func scan() -> ScanReport { DiskScanner(policy: policy).scan(roots: [home]) }
  func cache() throws -> Candidate {
    try file("Library/Caches/example/download.bin")
    return try XCTUnwrap(scan().candidates.first)
  }
  func testBuildRequiresProjectManifestAndSuppressesNestedCandidates() throws {
    try file("work/project/package.json", bytes: 2)
    try file("work/project/node_modules/package/large.bin")
    try file("work/unrelated/node_modules/important.bin")
    let report = scan()
    XCTAssertEqual(report.candidates.count, 1)
    XCTAssertEqual(
      report.candidates[0].path, home.appendingPathComponent("work/project/node_modules").path)
    XCTAssertEqual(report.candidates[0].kind, .projectArtifacts)
    XCTAssertNoThrow(try policy.validate(report.candidates[0]))
  }
  func testNeverTraversesSymlink() throws {
    try file("outside/private.bin")
    let cache = home.appendingPathComponent("Library/Caches")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: cache.appendingPathComponent("linked"),
      withDestinationURL: home.appendingPathComponent("outside"))
    XCTAssertTrue(scan().candidates.isEmpty)
  }
  func testChangedNestedContentIsRejectedEvenIfRootMetadataUnchanged() throws {
    let item = try cache()
    try file("Library/Caches/example/nested/new.bin")
    XCTAssertThrowsError(try policy.validate(item))
  }
  func testChangedFileAndReplacementAreRejected() throws {
    let item = try cache()
    let path = home.appendingPathComponent("Library/Caches/example/download.bin")
    try Data(repeating: 66, count: 1_100_000).write(to: path, options: .atomic)
    XCTAssertThrowsError(try policy.validate(item))
  }
  func testSymlinkInsideCacheIsSignedButNotFollowed() throws {
    try file("outside/keep.txt", bytes: 5)
    try file("Library/Caches/example/cache.bin")
    try FileManager.default.createSymbolicLink(
      at: home.appendingPathComponent("Library/Caches/example/link"),
      withDestinationURL: home.appendingPathComponent("outside"))
    let item = try XCTUnwrap(scan().candidates.first)
    XCTAssertNoThrow(try policy.validate(item))
  }
  func testRedirectedParentRejected() throws {
    let item = try cache()
    let parent = home.appendingPathComponent("Library/Caches")
    let moved = home.appendingPathComponent("moved")
    try FileManager.default.moveItem(at: parent, to: moved)
    try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: moved)
    XCTAssertThrowsError(try policy.validate(item))
  }
  func testSparseLogicalSizeDoesNotInflateDiskUse() throws {
    let url = try file("Downloads/sparse.img", bytes: 0)
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: 500_000_000)
    try handle.close()
    let report = scan()
    XCTAssertLessThan(report.scannedBytes, 1_000_000)
    XCTAssertTrue(report.candidates.isEmpty)
  }
  func testHardLinksCountOnlyOnce() throws {
    let first = try file("a.bin")
    try FileManager.default.linkItem(at: first, to: home.appendingPathComponent("b.bin"))
    let bytes = try FileStamp.read(first.path).blocks * 512
    XCTAssertLessThan(scan().scannedBytes, bytes + 20_000)
  }
  func testProtectsSecretsAppsTrashAndApplicationData() throws {
    for path in [
      ".ssh/node_modules", ".Trash/project/node_modules", "Library/Application Support/important",
      "Applications/Test.app/Contents/node_modules", ".git/node_modules",
    ] {
      let url = home.appendingPathComponent(path)
      XCTAssertNil(
        policy.classification(
          path: url.path, isDirectory: true, bytes: 1_000_000_000, modified: Date()))
    }
    XCTAssertNil(
      policy.classification(
        path: home.appendingPathComponent("Library/Keychains/key.db").path, isDirectory: false,
        bytes: 1_000_000_000, modified: Date()))
    XCTAssertNil(
      policy.classification(
        path: "/Library/Caches/test", isDirectory: true, bytes: 1_000_000_000, modified: Date()))
  }
  func testOldLogsOnly() {
    let path = home.appendingPathComponent("Library/Logs/tool.log").path
    XCTAssertNil(
      policy.classification(path: path, isDirectory: false, bytes: 2_000_000, modified: Date()))
    XCTAssertEqual(
      policy.classification(
        path: path, isDirectory: false, bytes: 2_000_000,
        modified: Date(timeIntervalSinceNow: -40 * 86400))?.0, .logs)
  }
  func testCancellationDisablesCleanup() throws {
    let token = ScanCancellation()
    token.cancel()
    let report = DiskScanner(policy: policy, cancellation: token).scan(roots: [home])
    XCTAssertTrue(report.cancelled)
    XCTAssertThrowsError(try CleanupService(policy: policy).trash([], from: report))
  }
  func testTrashAndRestoreWithDisposableFilesystem() throws {
    let item = try cache()
    let report = scan()
    let trash = home.appendingPathComponent(".Trash")
    try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    let service = CleanupService(
      policy: policy,
      mover: { url in
        let destination = trash.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
      })
    let result = try service.trash([item], from: report)
    XCTAssertTrue(result.failures.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: item.path))
    let receipt = try XCTUnwrap(result.receipts.first)
    XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.trashed))
    try service.restore(receipt)
    XCTAssertTrue(FileManager.default.fileExists(atPath: item.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: receipt.trashed))
  }
  func testWholeBatchPreflightPreventsPartialMove() throws {
    try file("Library/Caches/first/file.bin")
    try file("Library/Caches/second/file.bin")
    let report = scan()
    try file("Library/Caches/second/new.bin")
    XCTAssertThrowsError(try CleanupService(policy: policy).trash(report.candidates, from: report))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: home.appendingPathComponent("Library/Caches/first").path))
  }
  func testDuplicateAndForgedSelectionRejected() throws {
    let item = try cache()
    let report = scan()
    XCTAssertThrowsError(try CleanupService(policy: policy).trash([item, item], from: report))
    let other = ScanReport(
      date: Date(), roots: [], candidates: [], issues: [], filesVisited: 0, cancelled: false)
    XCTAssertThrowsError(try CleanupService(policy: policy).trash([item], from: other))
  }
  func testRootOverlapDoesNotDoubleCount() throws {
    try file("work/file.bin")
    let baseline = scan()
    let overlapping = DiskScanner(policy: policy).scan(roots: [
      home, home.appendingPathComponent("work"), home,
    ])
    XCTAssertEqual(baseline.scannedBytes, overlapping.scannedBytes)
    XCTAssertEqual(overlapping.roots.count, 1)
  }
  func testRestoreNeverOverwritesNewData() throws {
    let original = try file("Library/Caches/example/file.bin")
    let source = try file(".Trash/old.bin")
    let receipt = TrashReceipt(
      id: UUID(), original: original.path, trashed: source.path, bytes: 1, date: Date())
    XCTAssertThrowsError(try CleanupService(policy: policy).restore(receipt))
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
  }
  func testCloudProvidersAreSkippedUnlessExplicitlyChosen() throws {
    try file("Library/Mobile Documents/example/keep.bin")
    let implicit = scan()
    XCTAssertTrue(implicit.issues.contains { $0.path.hasSuffix("Mobile Documents") })
    XCTAssertLessThan(implicit.scannedBytes, 1_000_000)
    let explicit = DiskScanner(policy: policy).scan(roots: [
      home.appendingPathComponent("Library/Mobile Documents")
    ])
    XCTAssertGreaterThan(explicit.scannedBytes, 1_000_000)
    XCTAssertTrue(explicit.issues.isEmpty)
  }
  func testNativeTrashAndRestoreOnlyGeneratedFixture() throws {
    let fm = FileManager.default
    let fixture = fm.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Caches/Room-Verification-\(UUID().uuidString)")
    try fm.createDirectory(at: fixture, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: fixture) }
    let content = Data(repeating: 82, count: 1_100_000)
    try content.write(to: fixture.appendingPathComponent("generated-test-data.bin"))
    let report = DiskScanner().scan(roots: [fixture])
    let candidate = try XCTUnwrap(report.candidates.first)
    let service = CleanupService()
    let result = try service.trash([candidate], from: report)
    XCTAssertTrue(result.failures.isEmpty, result.failures.joined(separator: "\n"))
    let receipt = try XCTUnwrap(result.receipts.first)
    XCTAssertFalse(fm.fileExists(atPath: fixture.path))
    try service.restore(receipt)
    XCTAssertEqual(
      try Data(contentsOf: fixture.appendingPathComponent("generated-test-data.bin")), content)
  }
  func testInstalledToolDependenciesAreNotProjectBuildOutput() throws {
    for base in [
      ".nvm/versions/node/v22/lib/node_modules/npm", ".vscode/extensions/example",
      ".claude/plugins/cache/example", ".codex/tools/example",
    ] {
      try file(base + "/package.json", bytes: 2)
      try file(base + "/node_modules/installed-tool.bin")
    }
    XCTAssertTrue(scan().candidates.isEmpty)
  }
  func testUnknownCachesAndProjectOutputRequireReview() throws {
    try file("Library/Caches/JetBrains/IDE/LocalHistory/changes.bin")
    try file("work/project/Cargo.toml", bytes: 2)
    try file("work/project/target/screenshot.png")
    let candidates = scan().candidates
    XCTAssertEqual(candidates.count, 2)
    XCTAssertTrue(candidates.allSatisfy { !$0.kind.rebuildable })
    XCTAssertEqual(Set(candidates.map(\.kind)), [.reviewCache, .projectArtifacts])
  }
}
