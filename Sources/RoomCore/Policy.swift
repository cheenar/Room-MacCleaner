import Foundation

public struct CleanupPolicy: Sendable {
  public let home: String
  public init(home: String = FileManager.default.homeDirectoryForCurrentUser.path) {
    self.home = URL(fileURLWithPath: home).standardizedFileURL.path
  }
  public func relative(_ path: String) -> String? {
    guard path.hasPrefix(home + "/") else { return nil }
    return String(path.dropFirst(home.count + 1))
  }
  public func classification(
    path: String, isDirectory: Bool, bytes: Int64, modified: Date, now: Date = Date()
  ) -> (CandidateKind, String)? {
    guard let rel = relative(path) else { return nil }
    let parts = rel.split(separator: "/").map(String.init)
    let name = parts.last ?? ""
    // Never offer contents of repositories, application bundles, backups or cloud stores as generic files.
    guard !parts.contains(where: { [".git", ".Trash", ".ssh", ".gnupg"].contains($0) }),
      !parts.contains(where: {
        $0.hasSuffix(".app") || $0.hasSuffix(".photoslibrary") || $0.hasSuffix(".backupbundle")
          || $0.hasSuffix(".sparsebundle")
      })
    else { return nil }
    let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
    let fm = FileManager.default
    if isDirectory {
      if parent.path == home + "/Library/Developer/Xcode/DerivedData" {
        let compilerCache = ["ModuleCache.noindex", "SymbolCache.noindex", "SDKStatCaches.noindex"]
          .contains(name)
        return (
          compilerCache ? .build : .projectArtifacts,
          compilerCache
            ? "Generated compiler cache. Close build tools first; the next build recreates it."
            : "Xcode project output may include test results, package checkouts with local edits, or debugging evidence. Review before removing."
        )
      }
      let projectProof: String? =
        name == "node_modules"
        ? "package.json"
        : name == ".build" ? "Package.swift" : name == "target" ? "Cargo.toml" : nil
      if let proof = projectProof, !rel.hasPrefix("Library/"),
        !parts.dropLast().contains(where: { $0.hasPrefix(".") }),
        fm.fileExists(atPath: parent.appendingPathComponent(proof).path)
      {
        return (
          .projectArtifacts,
          name == "node_modules"
            ? "Installed dependencies beside package.json. Reinstall with your package manager; local edits inside will be lost."
            : "Project build folder. It may also contain screenshots, recordings, test evidence or locally edited package checkouts. Review those before removing it."
        )
      }
      if parent.path == home + "/Library/Caches" || parent.path == home + "/.cache"
        || [".npm/_cacache", ".cargo/registry/cache", ".gradle/caches", ".bun/install/cache"]
          .contains(rel)
      {
        let downloadCache = [
          ".npm/_cacache", ".cargo/registry/cache", ".gradle/caches", ".bun/install/cache",
          "Library/Caches/Homebrew", "Library/Caches/pip", "Library/Caches/CocoaPods",
          "Library/Caches/ReactNative", "Library/Caches/Coursier", "Library/Caches/electron",
          "Library/Caches/node-gyp",
        ].contains(rel)
        return (
          downloadCache ? .cache : .reviewCache,
          downloadCache
            ? "Downloaded packages or generated package cache. Close package managers first. Future installs may need to download files again."
            : "A cache location can still contain important data: IDE local history, offline files, model downloads, app runtimes or active browser data. Inspect its contents and close the related app before deciding."
        )
      }
      if parent.path == home + "/Library/Developer/Xcode/Archives"
        || parent.path == home + "/Library/Developer/Xcode/iOS DeviceSupport"
      {
        return (
          .archive,
          "Review carefully. Archives may be needed for distribution, symbolication or recovery; device support can be downloaded again."
        )
      }
    }
    if rel.hasPrefix("Library/Logs/"), !isDirectory, now.timeIntervalSince(modified) > 30 * 86400 {
      return (
        .logs,
        "Log file last modified over 30 days ago. It may still be useful for diagnosing an older issue."
      )
    }
    guard !isDirectory, !parts.contains(where: { $0.hasPrefix(".") }), !rel.hasPrefix("Library/"),
      !rel.hasPrefix("Applications/")
    else { return nil }
    if rel.hasPrefix("Downloads/"),
      ["dmg", "pkg", "iso", "xip"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    {
      return (
        .installer,
        "Downloaded installer or disk image. Check that you have installed it and no longer need the original."
      )
    }
    if bytes >= 100_000_000 {
      return (
        .largeFile,
        "Large personal file. Size alone does not mean it is disposable. Open or reveal it before deciding."
      )
    }
    return nil
  }

  public func validate(_ candidate: Candidate) throws {
    let url = URL(fileURLWithPath: candidate.path).standardizedFileURL
    guard url.path == candidate.path, relative(url.path) != nil,
      url.resolvingSymlinksInPath().path == url.path,
      !candidate.stamp.isSymlink,
      classification(
        path: candidate.path, isDirectory: candidate.stamp.isDirectory, bytes: candidate.bytes,
        modified: candidate.modified)?.0 == candidate.kind
    else {
      throw CleanupError.unsafePath(candidate.path)
    }
    guard try FileStamp.read(candidate.path) == candidate.stamp else {
      throw CleanupError.changed(candidate.path)
    }
    let check = try DiskScanner.signature(at: candidate.path)
    guard check == candidate.treeSignature else { throw CleanupError.changed(candidate.path) }
  }
}

public enum CleanupError: LocalizedError {
  case unsafePath(String)
  case changed(String)
  case overlap, cancelledScan
  public var errorDescription: String? {
    switch self {
    case .unsafePath(let path):
      "Room will not clean this protected or redirected path: \(displayPath(path))"
    case .changed(let path):
      "This item changed since the scan. Scan again before cleaning: \(displayPath(path))"
    case .overlap: "The selection contains a folder and something inside it. Select only one."
    case .cancelledScan: "Complete a scan before cleaning."
    }
  }
}
