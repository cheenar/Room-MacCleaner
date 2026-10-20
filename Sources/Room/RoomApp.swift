import AppKit
import RoomCore
import SwiftUI

@main
struct RoomApp: App {
  @StateObject private var model = RoomModel()
  var body: some Scene {
    WindowGroup {
      ContentView(model: model)
        .frame(minWidth: 720, minHeight: 560)
        .tint(.orange)
        .task { model.startIfNeeded() }
    }
    .defaultSize(width: 1180, height: 790)
    .windowStyle(.titleBar)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("Scan Mac", action: model.scanMac).keyboardShortcut("r").disabled(model.busy)
        Button("Scan Folder…", action: model.chooseFolder).keyboardShortcut("o").disabled(
          model.busy)
      }
    }
  }
}

enum Page: String, CaseIterable, Identifiable {
  case cleanup = "Cleanup"
  case large = "Large files"
  case map = "Storage map"
  case access = "Access & coverage"
  case history = "Cleanup history"
  var id: Self { self }
  var symbol: String {
    switch self {
    case .cleanup: "sparkles"
    case .large: "doc.on.doc"
    case .map: "square.grid.2x2"
    case .access: "lock.shield"
    case .history: "clock.arrow.circlepath"
    }
  }
}

@MainActor
final class RoomModel: ObservableObject {
  @Published var report: ScanReport?
  @Published var scanning = false
  @Published var cleaning = false
  @Published var scannedCount = 0
  @Published var currentPath = ""
  @Published var disk = DiskSpace.current()
  @Published var selection = Set<String>()
  @Published var page: Page? = .cleanup
  @Published var search = ""
  @Published var filter: CandidateKind?
  @Published var error: String?
  @Published var notice: String?
  @Published var receipts: [TrashReceipt] = []
  @Published var mapStack: [StorageNode] = []
  @Published var reviewItems: [Candidate]?
  private var cancellation: ScanCancellation?
  private var started = false
  private var staleAfterCleanup = false
  private var scanRoots = DiskScanner.defaultRoots
  private let historyURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
    "Library/Application Support/Room/History.json")
  var busy: Bool { scanning || cleaning }
  var items: [Candidate] {
    (report?.candidates ?? []).filter { item in
      (page == .large
        ? item.kind == .largeFile || item.kind == .installer : item.kind != .largeFile)
        && (filter == nil || item.kind == filter)
        && (search.isEmpty || item.path.localizedCaseInsensitiveContains(search)
          || item.kind.rawValue.localizedCaseInsensitiveContains(search))
    }
  }
  var selectedItems: [Candidate] {
    (report?.candidates ?? []).filter { selection.contains($0.path) }
  }
  var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }
  var canClean: Bool { !busy && !staleAfterCleanup && report?.cancelled == false }
  var mapNodes: [StorageNode] { mapStack.last?.children ?? report?.roots ?? [] }
  func node(at path: String) -> StorageNode? {
    func find(_ nodes: [StorageNode]) -> StorageNode? {
      for node in nodes {
        if node.path == path { return node }
        if path.hasPrefix(node.path + "/"), let found = find(node.children) { return found }
      }
      return nil
    }
    return find(report?.roots ?? [])
  }

  func startIfNeeded() {
    guard !started else { return }
    started = true
    if let data = try? Data(contentsOf: historyURL),
      let saved = try? JSONDecoder().decode([TrashReceipt].self, from: data)
    {
      receipts = saved
    }
    let args = CommandLine.arguments
    if let flag = args.firstIndex(of: "--report"), args.indices.contains(flag + 1),
      let data = try? Data(contentsOf: URL(fileURLWithPath: args[flag + 1]))
    {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      if let saved = try? decoder.decode(ScanReport.self, from: data) {
        report = saved
        return
      }
    }
    scanMac()
  }
  func scanMac() { scan(roots: DiskScanner.defaultRoots) }
  func rescan() { scan(roots: scanRoots) }
  func scan(roots: [URL]) {
    guard !busy else { return }
    scanRoots = roots
    selection.removeAll()
    mapStack = []
    notice = nil
    error = nil
    scanning = true
    scannedCount = 0
    currentPath = "Starting…"
    let token = ScanCancellation()
    cancellation = token
    Task.detached(priority: .utility) { [weak self] in
      let scanner = DiskScanner(cancellation: token) { [weak self] count, path in
        Task { @MainActor [weak self] in
          self?.scannedCount = count
          self?.currentPath = path
        }
      }
      let report = scanner.scan(roots: roots)
      let space = DiskSpace.current()
      await MainActor.run { [weak self] in
        guard let self else { return }
        self.report = report
        self.scanning = false
        self.disk = space
        self.cancellation = nil
        self.staleAfterCleanup = false
        if report.cancelled {
          self.notice = "Scan stopped. Results are partial; complete a scan before cleaning."
        }
      }
    }
  }
  func stop() { cancellation?.cancel() }
  func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.prompt = "Scan folder"
    panel.message =
      "Choose a folder to inspect. Cleanup is restricted to recognized items in your home folder."
    if panel.runModal() == .OK, let url = panel.url { scan(roots: [url]) }
  }
  func selectVisibleRebuildable() {
    selection.formUnion(items.filter { $0.kind.rebuildable }.map(\.path))
  }
  func review() { reviewItems = selectedItems }
  func trash(_ items: [Candidate]) {
    guard canClean, let report else { return }
    reviewItems = nil
    cleaning = true
    Task.detached(priority: .userInitiated) { [weak self] in
      do {
        let result = try CleanupService().trash(items, from: report)
        await MainActor.run { [weak self] in
          guard let self else { return }
          self.receipts.insert(contentsOf: result.receipts, at: 0)
          self.saveHistory()
          self.selection.removeAll()
          self.cleaning = false
          self.staleAfterCleanup = true
          let bytes = result.receipts.reduce(Int64(0)) { $0 + $1.bytes }
          self.notice =
            "Moved \(result.receipts.count) items (\(formatBytes(bytes))) to Trash. Empty Trash in Finder to recover space. Scan again to refresh totals."
          if !result.failures.isEmpty { self.error = result.failures.joined(separator: "\n\n") }
          self.disk = DiskSpace.current()
        }
      } catch {
        let message = error.localizedDescription
        await MainActor.run { [weak self] in
          self?.cleaning = false
          self?.error = message
        }
      }
    }
  }
  func restore(_ receipt: TrashReceipt) {
    guard !busy else { return }
    cleaning = true
    Task.detached { [weak self] in
      do {
        try CleanupService().restore(receipt)
        await MainActor.run { [weak self] in
          guard let self else { return }
          self.receipts.removeAll { $0.id == receipt.id }
          self.saveHistory()
          self.cleaning = false
          self.staleAfterCleanup = true
          self.notice = "Restored \(displayPath(receipt.original)). Scan again to refresh totals."
        }
      } catch {
        let message = error.localizedDescription
        await MainActor.run { [weak self] in
          self?.cleaning = false
          self?.error = message
        }
      }
    }
  }
  private func saveHistory() {
    do {
      try FileManager.default.createDirectory(
        at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(receipts).write(to: historyURL, options: .atomic)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: historyURL.deletingLastPathComponent().path)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
    } catch {
      self.error =
        "Cleanup completed, but Room could not save the restore receipt. Use Finder to restore items from Trash. \(error.localizedDescription)"
    }
  }
  func reveal(_ path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
  }
  func openTrash() {
    NSWorkspace.shared.open(
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
  }
  func openStorage() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!)
  }
  func openPrivacy() {
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
  }
}
