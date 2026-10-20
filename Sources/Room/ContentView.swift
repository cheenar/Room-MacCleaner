import AppKit
import RoomCore
import SwiftUI

struct ContentView: View {
  @ObservedObject var model: RoomModel
  @State private var inspected: Candidate?
  var body: some View {
    NavigationSplitView {
      VStack(alignment: .leading, spacing: 22) {
        HStack(spacing: 10) {
          Image(systemName: "circle.hexagongrid.fill").font(.system(size: 28)).foregroundStyle(
            .orange)
          Text("Room").font(.system(size: 25, weight: .semibold, design: .rounded))
        }.padding(.horizontal, 18).padding(.top, 22)
        List(Page.allCases, selection: $model.page) { page in
          Label(page.rawValue, systemImage: page.symbol).padding(.vertical, 6).tag(page)
        }.listStyle(.sidebar)
      }
      .navigationSplitViewColumnWidth(min: 195, ideal: 215, max: 250)
    } detail: {
      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            header
            diskCard
            if model.scanning { scanProgress }
            if let notice = model.notice { noticeView(notice) }
            if model.page == .map {
              storageMap
            } else if model.page == .access {
              accessView
            } else if model.page == .history {
              historyView
            } else {
              candidatesView
            }
          }.padding(30)
        }
        footer
      }
      .background(Color(nsColor: .windowBackgroundColor))
    }
    .toolbar {
      ToolbarItemGroup {
        Button(action: model.openStorage) { Label("macOS Storage", systemImage: "internaldrive") }
          .help("Open macOS Storage settings")
        Button(action: model.chooseFolder) {
          Label("Scan folder", systemImage: "folder.badge.plus")
        }.disabled(model.busy)
        if model.scanning {
          Button("Stop", action: model.stop)
        } else {
          Button(action: model.scanMac) { Label("Scan Mac", systemImage: "arrow.clockwise") }
            .disabled(model.busy)
        }
      }
    }
    .sheet(
      isPresented: Binding(
        get: { model.reviewItems != nil }, set: { if !$0 { model.reviewItems = nil } })
    ) {
      if let items = model.reviewItems {
        ReviewSheet(
          items: items, confirm: { model.trash(items) }, cancel: { model.reviewItems = nil })
      }
    }
    .sheet(item: $inspected) { item in
      VStack(alignment: .leading, spacing: 18) {
        Label(item.kind.rawValue, systemImage: item.kind.symbol).font(.title2.bold())
        Text(item.name).font(.title3.weight(.medium))
        Text(item.reason).foregroundStyle(.secondary)
        Text(item.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        LabeledContent("On disk", value: formatBytes(item.bytes))
        LabeledContent(
          "Last modified", value: item.modified.formatted(date: .abbreviated, time: .shortened))
        HStack {
          Button("Reveal in Finder") { model.reveal(item.path) }
          Spacer()
          Button("Done") { inspected = nil }.keyboardShortcut(.defaultAction)
        }
      }.padding(28).frame(width: 510)
    }
    .alert(
      "Unable to complete action",
      isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
    ) {
      Button("OK") { model.error = nil }
    } message: {
      Text(model.error ?? "")
    }
    .onChange(of: model.page) { _, _ in
      model.filter = nil
      model.search = ""
    }
  }
  private var header: some View {
    HStack(alignment: .top) {
      Text(model.page?.rawValue ?? "Cleanup").font(.system(size: 28, weight: .semibold))
      Spacer()
      if let report = model.report, !model.scanning {
        VStack(alignment: .trailing, spacing: 5) {
          Label(
            report.cancelled ? "Partial scan" : "Last scan",
            systemImage: report.cancelled ? "pause.circle" : "checkmark.circle"
          ).font(.caption).foregroundStyle(.secondary)
          Text(report.date, style: .time).font(.caption.monospacedDigit())
        }.padding(.top, 5)
      }
    }
  }
  private var diskCard: some View {
    VStack(alignment: .leading, spacing: 15) {
      HStack(alignment: .firstTextBaseline) {
        Label("Macintosh HD", systemImage: "internaldrive.fill").font(.headline)
        Spacer()
        Text(formatBytes(model.disk.free)).font(
          .system(size: 27, weight: .semibold, design: .rounded)
        ).monospacedDigit()
        Text("free").foregroundStyle(.secondary)
      }
      GeometryReader { proxy in
        let fraction =
          model.disk.total > 0 ? 1 - Double(model.disk.free) / Double(model.disk.total) : 0
        ZStack(alignment: .leading) {
          Capsule().fill(Color.primary.opacity(0.07))
          Capsule().fill(
            LinearGradient(
              colors: [.orange.opacity(0.75), .orange, .red.opacity(0.8)], startPoint: .leading,
              endPoint: .trailing)
          ).frame(width: max(0, proxy.size.width * min(1, fraction)))
        }
      }.frame(height: 10)
      HStack {
        Text(
          "\(formatBytes(model.disk.total - model.disk.free)) used of \(formatBytes(model.disk.total))"
        ).font(.caption).foregroundStyle(.secondary)
        Spacer()
        if model.disk.free < 30_000_000_000 {
          Label("Running low", systemImage: "exclamationmark.circle.fill").font(
            .caption.weight(.medium)
          ).foregroundStyle(.orange)
        }
      }
      if let available = model.disk.availableForImportantUsage,
        available > model.disk.free + 5_000_000_000
      {
        LabeledContent("Available with purgeable space", value: formatBytes(available))
          .font(.caption).foregroundStyle(.secondary)
          .help(
            "Includes storage macOS can reclaim automatically. Free space above is available immediately."
          )
      }
    }.padding(22).background(.background, in: RoundedRectangle(cornerRadius: 18)).overlay(
      RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.06)))
  }
  private var scanProgress: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        ProgressView().controlSize(.small)
        Text("Scanning…").font(.headline)
        Spacer()
        Text("\(model.scannedCount.formatted()) entries").font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      Text(displayPath(model.currentPath)).font(.caption.monospaced()).lineLimit(1).truncationMode(
        .middle
      ).foregroundStyle(.secondary)
    }.padding(18).background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
  }
  private func noticeView(_ notice: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "info.circle.fill").foregroundStyle(.orange)
      Text(notice).font(.callout)
      Spacer()
      Button("Scan again", action: model.rescan).disabled(model.busy)
    }.padding(16).background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
  }
  private var candidatesView: some View {
    VStack(alignment: .leading, spacing: 18) {
      if let report = model.report {
        HStack(spacing: 12) {
          statCard(
            "Rebuildable", value: formatBytes(report.rebuildableBytes),
            symbol: "arrow.triangle.2.circlepath",
            color: .green)
          statCard(
            "Review",
            value: formatBytes(
              report.candidates.filter { !$0.kind.rebuildable }.reduce(0) { $0 + $1.bytes }),
            symbol: "eye", color: .orange)
          statCard(
            "Scanned", value: formatBytes(report.scannedBytes),
            symbol: "viewfinder", color: .blue)
        }
        if !report.issues.isEmpty {
          Button {
            model.page = .access
          } label: {
            Label(
              "\(report.issues.count) skipped locations",
              systemImage: "lock.shield"
            )
            .font(.caption).foregroundStyle(.secondary)
          }.buttonStyle(.plain)
        }
      }
      HStack(spacing: 12) {
        HStack {
          Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
          TextField("Search", text: $model.search).textFieldStyle(.plain)
        }.padding(9).background(.background, in: RoundedRectangle(cornerRadius: 8))
        Picker("Type", selection: $model.filter) {
          Text("All types").tag(nil as CandidateKind?)
          ForEach(CandidateKind.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
        }.labelsHidden().frame(width: 155)
        Menu {
          Button("Select visible rebuildable items", action: model.selectVisibleRebuildable)
          Button("Clear selection") { model.selection.removeAll() }
        } label: {
          Image(systemName: "checklist")
        }.menuStyle(.borderlessButton).fixedSize().disabled(!model.canClean)
      }
      if model.items.isEmpty {
        ContentUnavailableView(
          model.scanning ? "Scan in progress" : "No matching candidates",
          systemImage: model.scanning ? "magnifyingglass" : "checkmark.seal",
          description: Text(
            model.scanning
              ? "Results appear when the scan finishes."
              : "Change the filter or scan another folder.")
        )
        .frame(maxWidth: .infinity, minHeight: 180)
      } else {
        HStack {
          Text("\(model.items.count.formatted()) items").font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
          Spacer()
          Text("Largest first").font(.caption).foregroundStyle(.tertiary)
        }
        LazyVStack(spacing: 0) {
          ForEach(model.items) { item in
            candidateRow(item)
            Divider().padding(.leading, 62)
          }
        }.background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(
          RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06)))
      }
    }.disabled(model.scanning || model.cleaning)
  }
  private func statCard(
    _ title: String, value: String, symbol: String, color: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(color)
      Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.7)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(
      color.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
  }
  private func candidateRow(_ item: Candidate) -> some View {
    HStack(spacing: 13) {
      Toggle(
        "Select \(item.name)",
        isOn: Binding(
          get: { model.selection.contains(item.path) },
          set: {
            if $0 { model.selection.insert(item.path) } else { model.selection.remove(item.path) }
          })
      )
      .labelsHidden().toggleStyle(.checkbox).disabled(!model.canClean)
      Image(systemName: item.kind.symbol).font(.system(size: 19)).foregroundStyle(
        item.kind.rebuildable ? Color.green : Color.orange
      )
      .frame(width: 34, height: 38).background(
        (item.kind.rebuildable ? Color.green : Color.orange).opacity(0.08),
        in: RoundedRectangle(cornerRadius: 8))
      VStack(alignment: .leading, spacing: 5) {
        Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(
          .middle)
        Text(displayPath(item.path)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(
          1
        ).truncationMode(.middle)
        Text(item.kind.rawValue + " · " + (item.kind.rebuildable ? "Rebuildable" : "Review first"))
          .font(.system(size: 10)).foregroundStyle(.tertiary)
      }
      Spacer(minLength: 8)
      Text(formatBytes(item.bytes)).font(.system(size: 13, weight: .medium, design: .rounded))
        .monospacedDigit().fixedSize()
      Button {
        inspected = item
      } label: {
        Image(systemName: "info.circle")
      }.buttonStyle(.borderless).help("Why is this here?")
      Button {
        model.reveal(item.path)
      } label: {
        Image(systemName: "folder")
      }.buttonStyle(.borderless).help("Reveal in Finder")
    }.padding(14)
      .contextMenu {
        Button("Details") { inspected = item }
        Button("Reveal in Finder") { model.reveal(item.path) }
        Button("Copy path") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(item.path, forType: .string)
        }
      }
  }
  private var storageMap: some View {
    VStack(alignment: .leading, spacing: 17) {
      HStack {
        Button {
          model.mapStack = []
        } label: {
          Label("Scan roots", systemImage: "internaldrive")
        }.disabled(model.mapStack.isEmpty)
        if !model.mapStack.isEmpty {
          Button {
            model.mapStack.removeLast()
          } label: {
            Label("Back", systemImage: "chevron.left")
          }
          Text(displayPath(model.mapStack.last!.path)).font(.caption.monospaced()).lineLimit(1)
            .truncationMode(.middle)
        }
        Spacer()
      }
      let total = max(1, model.mapNodes.reduce(Int64(0)) { $0 + $1.bytes })
      LazyVStack(spacing: 0) {
        ForEach(model.mapNodes) { node in
          HStack(spacing: 14) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill").font(.title3)
              .foregroundStyle(.orange).frame(width: 26)
            VStack(alignment: .leading, spacing: 9) {
              HStack {
                Text(model.mapStack.isEmpty ? displayPath(node.path) : node.name).lineLimit(1)
                  .truncationMode(.middle)
                Spacer()
                Text(formatBytes(node.bytes)).font(.callout.monospacedDigit())
              }
              GeometryReader { proxy in
                Capsule().fill(Color.orange.opacity(0.65)).frame(
                  width: max(3, proxy.size.width * Double(node.bytes) / Double(total)))
              }.frame(height: 5)
            }
            Button {
              model.reveal(node.path)
            } label: {
              Image(systemName: "folder")
            }.buttonStyle(.borderless).help("Reveal in Finder")
            Button {
              model.mapStack.append(node)
            } label: {
              Image(systemName: "chevron.right")
            }.buttonStyle(.borderless).disabled(node.children.isEmpty).help("Inspect folder")
          }.padding(16)
          Divider().padding(.leading, 56)
        }
      }.background(.background, in: RoundedRectangle(cornerRadius: 14))
      Text("Items under 1 MB hidden").font(.caption).foregroundStyle(.secondary)
        .help(
          "Totals include all readable items. Symlinks are not followed; system folders are inspection only."
        )
    }
  }
  private var accessView: some View {
    VStack(alignment: .leading, spacing: 18) {
      GroupBox {
        VStack(alignment: .leading, spacing: 13) {
          Text("Full Disk Access").font(.headline)
          Text(
            "To include protected app data, add Room in Privacy & Security → Full Disk Access, then reopen Room."
          )
          .font(.callout).foregroundStyle(.secondary)
          HStack {
            Button("Open Settings", action: model.openPrivacy)
            Button("Reveal Room") { model.reveal(Bundle.main.bundleURL.path) }
          }
          Divider()
          DisclosureGroup("Scan scope") {
            Text(
              "Scans your home folder, /Applications, /Library, /private/var, /Users/Shared, /opt and /usr/local. Cloud folders and separate volumes require an explicit folder scan. System data and snapshots are inspection only."
            )
            .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
          }
          if let report = model.report {
            LabeledContent("Scanned", value: formatBytes(report.scannedBytes))
            LabeledContent(
              "Outside scan",
              value: formatBytes(max(0, model.disk.total - model.disk.free - report.scannedBytes)))
          }
          Button("Open macOS Storage settings", action: model.openStorage)
        }.padding(12)
      }
      let simulatorPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Developer/CoreSimulator"
      ).path
      if let simulators = model.node(at: simulatorPath), simulators.bytes > 500_000_000 {
        GroupBox {
          VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Simulator storage", value: formatBytes(simulators.bytes)).font(
              .headline)
            Text("Manage devices and runtimes in Xcode.").font(.callout).foregroundStyle(.secondary)
            HStack {
              Button("Reveal in Finder") { model.reveal(simulatorPath) }
              Link(
                "Xcode guide",
                destination: URL(
                  string:
                    "https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components"
                )!)
            }
          }.padding(12)
        }
      }
      Text("Skipped locations · \(model.report?.issues.count ?? 0)").font(.headline)
      LazyVStack(alignment: .leading, spacing: 12) {
        ForEach(model.report?.issues ?? []) { issue in
          VStack(alignment: .leading, spacing: 4) {
            Text(displayPath(issue.path)).font(.caption.monospaced()).textSelection(.enabled)
            Text(issue.message).font(.caption).foregroundStyle(.secondary)
          }
          Divider()
        }
      }
    }
  }
  private var historyView: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(
          "Restore items before emptying Trash."
        ).font(.callout).foregroundStyle(.secondary)
        Spacer()
        Button("Open Trash", action: model.openTrash)
      }
      if model.receipts.isEmpty {
        ContentUnavailableView(
          "Nothing cleaned yet", systemImage: "clock.arrow.circlepath",
          description: Text("Cleaned items appear here."))
      }
      ForEach(model.receipts) { receipt in
        HStack {
          VStack(alignment: .leading, spacing: 5) {
            Text(URL(fileURLWithPath: receipt.original).lastPathComponent).font(.headline)
            Text(displayPath(receipt.original)).font(.caption).foregroundStyle(.secondary)
              .lineLimit(1).truncationMode(.middle)
            Text(receipt.date, style: .date).font(.caption).foregroundStyle(.tertiary)
          }
          Spacer()
          Text(formatBytes(receipt.bytes)).font(.callout.monospacedDigit())
          Button("Restore") { model.restore(receipt) }.disabled(
            model.busy || !FileManager.default.fileExists(atPath: receipt.trashed))
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12))
      }
    }
  }
  private var footer: some View {
    HStack(spacing: 12) {
      if model.cleaning {
        ProgressView().controlSize(.small)
        Text("Working…").font(.callout)
      } else {
        Text(
          model.selection.isEmpty
            ? "0 selected"
            : "\(model.selection.count) selected · \(formatBytes(model.selectedBytes))"
        )
        .font(.callout.weight(.medium))
      }
      Spacer()
      Button("Open Trash", action: model.openTrash).buttonStyle(.borderless)
      Button("Review", action: model.review).buttonStyle(.borderedProminent).disabled(
        model.selection.isEmpty || !model.canClean)
    }.padding(.horizontal, 25).padding(.vertical, 16).background(.bar)
  }
}

struct ReviewSheet: View {
  let items: [Candidate]
  let confirm: () -> Void
  let cancel: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("Move to Trash", systemImage: "trash").font(.title2.weight(.semibold))
      Text(
        "\(items.count) \(items.count == 1 ? "item" : "items") · \(formatBytes(items.reduce(0) { $0 + $1.bytes }))"
      ).font(.headline)
      Text(
        "Quit related apps first. Changes to synced files also affect other devices."
      ).font(.callout).foregroundStyle(.secondary)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          ForEach(items) { item in
            VStack(alignment: .leading, spacing: 5) {
              HStack {
                Text(item.name).font(.headline)
                Spacer()
                Text(formatBytes(item.bytes)).monospacedDigit()
              }
              Text(displayPath(item.path)).font(.caption.monospaced()).textSelection(.enabled)
              Text(item.reason).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
          }
        }
      }.frame(maxHeight: 320)
      Label(
        "Empty Trash in Finder to free space. Restore from History until then.",
        systemImage: "info.circle"
      ).font(.callout).foregroundStyle(.secondary)
      HStack {
        Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
        Spacer()
        Button("Move to Trash", role: .destructive, action: confirm).buttonStyle(.borderedProminent)
          .tint(.orange)
      }
    }.padding(28).frame(width: 610)
  }
}
