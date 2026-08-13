import AppKit
import S950Library
import SwiftUI

struct FindRow: Identifiable {
    let image: S950ImageCatalog
    let volume: S950VolumeCatalog
    let entry: S950LibraryEntry
    var id: String { "\(image.imageURL.path)|\(volume.path)|\(entry.id)" }
    var diskName: String { image.name }
    var name: String { entry.name }
    var typeName: String { entry.kind.displayName }
    var byteSize: Int64 { entry.byteSize }
    var sampleRateSortValue: Int { entry.sampleRateSortValue }
}

struct Find950View: View {
    @ObservedObject var model: Find950Model
    @EnvironmentObject private var preferences: SuitePreferences
    @State private var isCompact = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                SuiteBrandHeader(product: "FIND950", purpose: "BROWSE · SEARCH · COLLECT")
                searchStrip
                browserLayout
                FindStatusBar(model: model)
            }
            .task(id: geometry.size.width) {
                // Let AppKit complete its initial constraint pass before adapting
                // the toolbar and search controls for a restored narrow window.
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                updateResponsiveState(width: geometry.size.width)
            }
        }
        .navigationTitle(model.selectedImage?.name ?? "FIND950")
        .navigationSubtitle(model.selectedImage?.imageURL.deletingLastPathComponent().path ?? "950TOOLS LIBRARY")
        .toolbar { toolbar }
        .alert("FIND950", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.dismissError() } }
        )) {
            if model.errorOffersFullDiskAccess {
                Button("OPEN FULL DISK ACCESS") {
                    model.dismissError()
                    model.openFullDiskAccessSettings()
                }
            }
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
        .alert(
            model.notice?.title ?? "FIND950",
            isPresented: Binding(
                get: { model.notice != nil },
                set: { if !$0 { model.dismissNotice() } }
            )
        ) {
            Button("OK", role: .cancel) { model.dismissNotice() }
        } message: {
            Text(model.notice?.message ?? "")
        }
        .sheet(isPresented: $model.showTagManager) {
            FindTagManager(model: model)
                .suiteSurface()
        }
        .sheet(item: $model.relatedPrograms) { context in
            FindRelatedPrograms(model: model, context: context)
                .suiteSurface()
        }
        .onChange(of: model.searchFocusRequest) { _, _ in searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reloadSharedTags()
            model.refreshMediaVolumes()
        }
        .background(
            FindSpaceKeyMonitor {
                model.handleSpaceForSelectedEntry()
            }
        )
    }

    @ViewBuilder
    private var browserLayout: some View {
        if preferences.collectionVisible {
            VSplitView {
                browserPanes
                FindCollection(model: model)
                    .frame(minHeight: 220, idealHeight: 290, maxHeight: 460)
            }
        } else {
            browserPanes
        }
    }

    private var browserPanes: some View {
        HSplitView {
            if preferences.sidebarVisible {
                FindSidebar(model: model)
                    .frame(minWidth: 200, idealWidth: 260, maxWidth: 360)
            }
            content
                .frame(minWidth: 280)
            if preferences.inspectorVisible {
                FindInspector(model: model)
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
            }
        }
        .frame(minHeight: 210)
    }

    @ViewBuilder
    private var content: some View {
        if model.folderURLs.isEmpty {
            SuiteEmptyState(
                systemImage: "externaldrive.badge.plus",
                title: "ADD IMG FOLDERS",
                message: "Choose one or more folders containing Akai disk images. FIND950 indexes them without modifying any IMG.",
                actionTitle: "ADD IMG FOLDERS…",
                action: model.addFolders
            )
        } else if !model.searchText.isEmpty, model.searchScope == .entireLibrary {
            FindLibraryResults(model: model)
        } else if let image = model.selectedImage {
            FindDiskContents(model: model, image: image)
        } else if model.images.isEmpty {
            SuiteEmptyState(
                systemImage: "externaldrive.badge.questionmark",
                title: "NO DISK IMAGES FOUND",
                message: "No readable IMG files were found in the current folder scope.",
                actionTitle: "RESCAN",
                action: model.scanFolders
            )
        } else {
            SuiteEmptyState(
                systemImage: "externaldrive",
                title: "SELECT A DISK IMAGE",
                message: "Choose an image from the library to browse its programs, samples and other Akai files.",
                actionTitle: nil,
                action: nil
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            FindToolbarButton(
                title: preferences.sidebarVisible ? "HIDE FOLDERS" : "SHOW FOLDERS",
                symbol: "sidebar.left",
                isSelected: preferences.sidebarVisible
            ) { preferences.sidebarVisible.toggle() }
            if isCompact && !preferences.sidebarVisible {
                Menu {
                    ForEach(model.images) { image in
                        Button(image.name) { model.selectedImageID = image.id }
                    }
                } label: {
                    SuiteMenuLabel(title: "LIBRARY", systemImage: "externaldrive")
                }
                .menuStyle(.borderlessButton)
            }
            FindToolbarButton(title: "RESCAN", symbol: "arrow.clockwise", action: model.scanFolders)
                .disabled(model.folderURLs.isEmpty || model.isScanning)
            FindToolbarButton(title: "ADD FOLDERS", symbol: "folder.badge.plus", action: model.addFolders)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            FindEjectMenu(model: model)
            FindToolbarButton(title: "TAGS", symbol: "tag") { model.showTagManager = true }
            FindToolbarButton(
                title: preferences.collectionVisible ? "HIDE COLLECTION" : "SHOW COLLECTION",
                symbol: "tray.full",
                isSelected: preferences.collectionVisible
            ) { preferences.collectionVisible.toggle() }
            FindToolbarButton(
                title: preferences.inspectorVisible ? "HIDE INSPECTOR" : "SHOW INSPECTOR",
                symbol: "sidebar.right",
                isSelected: preferences.inspectorVisible
            ) { preferences.inspectorVisible.toggle() }
        }
    }

    private func updateResponsiveState(width: CGFloat) {
        isCompact = width < 940
    }

    private var searchStrip: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                searchField
                if !isCompact { searchControls }
            }
            if isCompact {
                HStack(spacing: 8) {
                    searchControls
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.suitePanel)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.suiteRule).frame(height: 1) }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            FindSearchScopeMenu(model: model)
            TextField("SEARCH", text: $model.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(SuiteFont.regular(11))
                .onSubmit { model.requestMainPaneFocus() }
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.suiteUnit)
                }
                .buttonStyle(.plain)
                .help("CLEAR SEARCH")
            }
        }
        .padding(.trailing, 10)
        .frame(minWidth: 220, maxWidth: .infinity, minHeight: 32)
        .background(Color.suiteSlab)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.suiteRule2))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var searchControls: some View {
        HStack(spacing: 8) {
            FindTagFilter(model: model)
        }
    }
}

private struct FindSpaceKeyMonitor: NSViewRepresentable {
    let onSpace: @MainActor () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(onSpace: onSpace) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.hostView = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        context.coordinator.onSpace = onSpace
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        weak var hostView: NSView?
        var onSpace: @MainActor () -> Bool
        private var monitor: Any?

        init(onSpace: @escaping @MainActor () -> Bool) {
            self.onSpace = onSpace
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                guard let self,
                      event.keyCode == 49,
                      event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                      let window = hostView?.window,
                      event.window === window
                else { return event }
                // Preserve normal typing in Search and any other field editor.
                if let textView = window.firstResponder as? NSTextView,
                   textView.isFieldEditor {
                    return event
                }
                return onSpace() ? nil : event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

private struct FindSearchScopeMenu: View {
    @ObservedObject var model: Find950Model

    var body: some View {
        Menu {
            Button {
                model.searchScope = .selectedDisk
            } label: {
                Label("THIS DISK", systemImage: "externaldrive")
            }
            Button {
                model.searchScope = .entireLibrary
            } label: {
                Label("ALL DISKS", systemImage: "externaldrive.fill.badge.plus")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                Text(model.searchScope == .selectedDisk ? "DISK" : "ALL")
                    .font(SuiteFont.regular(9))
                Image(systemName: "chevron.down")
                    .font(SuiteFont.regular(8))
            }
            .foregroundStyle(Color.suiteInk)
            .padding(.horizontal, 9)
            .frame(minHeight: 30)
            .background(Color.suiteSlab2)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(
            model.searchScope == .selectedDisk
                ? "SEARCH THIS DISK" : "SEARCH ALL DISKS"
        )
    }
}

private struct FindToolbarButton: View {
    let title: String
    let symbol: String
    var isSelected: Bool? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title.uppercased(), systemImage: symbol)
                .font(SuiteFont.regular(11))
                .tracking(1.3)
                .foregroundStyle(Color.suiteInk)
                .padding(.horizontal, 8)
                .frame(minHeight: 30)
                .background(buttonBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected == true ? Color.suiteYellow : Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(title.uppercased())
    }

    private var buttonBackground: Color {
        if hovering { return Color.suiteSlab2 }
        if isSelected == true { return Color.suiteYellow.opacity(0.2) }
        return Color.suiteSlab
    }
}

private struct FindEjectMenu: View {
    @ObservedObject var model: Find950Model

    var body: some View {
        Menu {
            if model.ejectableMediaVolumes.isEmpty {
                Button("NO EJECTABLE MEDIA") {}
                    .disabled(true)
            } else {
                ForEach(model.ejectableMediaVolumes) { media in
                    Button {
                        model.eject(media)
                    } label: {
                        Label(
                            model.ejectingMediaIDs.contains(media.id)
                                ? "EJECTING \(media.name.uppercased())…"
                                : "CLEAN & EJECT \(media.name.uppercased())",
                            systemImage: "eject"
                        )
                    }
                    .disabled(!model.canEject(media))
                }
            }
        } label: {
            SuiteMenuLabel(
                title: "SAFE EJECT",
                systemImage: "eject",
                badge: model.ejectableMediaVolumes.isEmpty
                    ? nil : model.ejectableMediaVolumes.count
            )
        }
        .menuStyle(.borderlessButton)
        .disabled(model.ejectableMediaVolumes.isEmpty)
        .help("CLEANLY UNMOUNT AND EJECT REMOVABLE MEDIA")
    }
}

private struct FindTagFilter: View {
    @ObservedObject var model: Find950Model
    var body: some View {
        Menu {
            Button("ALL TAGS") { model.selectedTagFilterID = nil }
            Divider()
            ForEach(model.tags) { tag in Button(tag.name) { model.selectedTagFilterID = tag.id } }
        } label: {
            SuiteMenuLabel(title: "TAG FILTER", systemImage: "tag", badge: model.selectedTagFilterID == nil ? nil : 1)
        }.menuStyle(.borderlessButton)
    }
}

private struct FindSidebar: View {
    @ObservedObject var model: Find950Model
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SuiteSectionHeader(title: "FOLDERS")
                    Spacer()
                    Button(action: model.addFolders) {
                        Image(systemName: "plus")
                            .font(SuiteFont.medium(12))
                            .foregroundStyle(Color.suiteOnYellow)
                            .frame(width: 30, height: 28)
                            .background(Color.suiteYellow)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.suiteRule2))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("ADD IMG FOLDERS")
                }
                VStack(spacing: 2) {
                    ForEach(model.folderURLs, id: \.standardizedFileURL) { folder in
                        HStack(spacing: 8) {
                            Button {
                                model.toggleFolderVisibility(folder)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: model.isFolderVisible(folder) ? "eye" : "eye.slash")
                                        .foregroundStyle(model.isFolderVisible(folder) ? Color.suiteInk : Color.suiteUnit)
                                    Text(folder.lastPathComponent).lineLimit(1)
                                    Spacer()
                                    if let media = model.mediaVolume(for: folder) {
                                        Image(systemName: media.isAvailable
                                            ? "externaldrive.fill" : "externaldrive.badge.xmark")
                                            .foregroundStyle(media.isAvailable
                                                ? Color.suiteBlue : Color.suiteUnit)
                                            .help(media.statusTitle)
                                    }
                                    Text(folderDiskCount(folder).formatted())
                                        .font(SuiteFont.regular(10)).foregroundStyle(Color.suiteUnit).monospacedDigit()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if let media = model.mediaVolume(for: folder), media.isEjectable {
                                Button {
                                    model.eject(media)
                                } label: {
                                    Image(systemName: "eject.fill")
                                        .font(SuiteFont.medium(11))
                                        .foregroundStyle(Color.suiteInk)
                                        .frame(width: 28, height: 26)
                                        .background(Color.suiteSlab2)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.suiteRule2))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .disabled(!model.canEject(media))
                                .help("CLEAN & EJECT \(media.name.uppercased())")
                            }
                            Button(role: .destructive) {
                                model.removeFolder(folder)
                            } label: {
                                Image(systemName: "minus")
                                    .font(SuiteFont.medium(11))
                                    .foregroundStyle(Color.suiteOnRed)
                                    .frame(width: 28, height: 26)
                                    .background(Color.suiteRed)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.suiteRule2))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .help("REMOVE FOLDER")
                        }
                        .frame(height: 28)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("SHOW IN FINDER") { model.showInFinder(folder) }
                            if let media = model.mediaVolume(for: folder), media.isEjectable {
                                Button {
                                    model.eject(media)
                                } label: {
                                    Label("CLEAN & EJECT \(media.name.uppercased())", systemImage: "eject")
                                }
                                .disabled(!model.canEject(media))
                            }
                            Divider()
                            Button("REMOVE FOLDER", role: .destructive) { model.removeFolder(folder) }
                        }
                    }
                }
                FindStats(model: model)
                SuiteSectionHeader(title: "DISK IMAGES")
                LazyVStack(spacing: 2) {
                    ForEach(model.images) { image in
                        Button {
                            model.selectImage(image)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(image.name).font(SuiteFont.medium(12)).lineLimit(1)
                                HStack(spacing: 7) {
                                    Text("\(image.programCount) \(image.programCount == 1 ? "PROGRAM" : "PROGRAMS") · \(image.sampleCount) \(image.sampleCount == 1 ? "SAMPLE" : "SAMPLES")")
                                        .font(SuiteFont.regular(10)).tracking(1.1).foregroundStyle(Color.suiteUnit).monospacedDigit()
                                    if model.mediaStatus(for: image) != "LOCAL" {
                                        FindMediaBadge(
                                            title: model.mediaStatus(for: image),
                                            available: model.isImageAvailable(image)
                                        )
                                    }
                                }
                                FindTagChips(tags: model.tagsFor(image: image), limit: 2)
                            }
                            .foregroundStyle(Color.suiteInk)
                            .padding(.horizontal, 9).padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .background(model.selectedImageID == image.id ? Color.suiteYellow.opacity(0.24) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button { model.openInEDIT950(image) } label: {
                                Label("OPEN IN EDIT950", systemImage: "arrow.up.forward.app")
                            }
                            Button("SHOW IN FINDER") { model.showInFinder(image.imageURL) }
                            Button("RESCAN THIS IMAGE") { model.rescanImage(image) }
                            if let media = model.mediaVolume(for: image), media.isEjectable {
                                Divider()
                                Button {
                                    model.eject(media)
                                } label: {
                                    Label("CLEAN & EJECT \(media.name.uppercased())", systemImage: "eject")
                                }
                                .disabled(!model.canEject(media))
                            }
                        }
                    }
                }
            }.padding(16)
        }
        .background(Color.suitePanel)
        .navigationTitle("FIND950")
    }

    private func folderDiskCount(_ folder: URL) -> Int {
        model.allImages.filter { $0.libraryFolderURL?.standardizedFileURL == folder.standardizedFileURL }.count
    }
}

private struct FindMediaBadge: View {
    let title: String
    let available: Bool

    var body: some View {
        Text(title)
            .font(SuiteFont.medium(8))
            .tracking(0.8)
            .foregroundStyle(available ? Color.suiteBlue : Color.suiteUnit)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.suiteSlab2, in: RoundedRectangle(cornerRadius: 3))
    }
}

private struct FindStats: View {
    @ObservedObject var model: Find950Model
    var body: some View {
        HStack(spacing: 8) {
            stat(model.visibleLibraryImages.count, "DISKS", nil)
            stat(model.visibleProgramCount, "PROGRAMS", .suiteRed)
            stat(model.visibleSampleCount, "SAMPLES", .suiteBlue)
        }.padding(.vertical, 10).overlay(alignment: .top) { Rectangle().fill(Color.suiteRule).frame(height: 1) }
    }
    private func stat(_ count: Int, _ title: String, _ accent: Color?) -> some View {
        VStack(spacing: 4) {
            Text(count.formatted()).font(SuiteFont.medium(19)).monospacedDigit()
            Text(title).font(SuiteFont.regular(9)).tracking(1.2).foregroundStyle(Color.suiteUnit)
            Rectangle().fill(accent ?? Color.suiteRule).frame(height: 3)
        }.frame(maxWidth: .infinity)
    }
}

private struct FindDiskContents: View {
    @ObservedObject var model: Find950Model
    let image: S950ImageCatalog
    private var rows: [FindRow] {
        image.volumes.flatMap { volume in
            model.visibleEntries(volume.entries, image: image, volume: volume).map { FindRow(image: image, volume: volume, entry: $0) }
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            FindContentHeader(model: model, image: image)
            if rows.isEmpty {
                SuiteEmptyState(
                    systemImage: "doc.text.magnifyingglass",
                    title: model.searchText.isEmpty ? "THIS VOLUME IS EMPTY" : "NO FILES MATCH",
                    message: model.searchText.isEmpty ? "This disk contains no recognised Akai files." : "No files match \(model.searchText).",
                    actionTitle: model.searchText.isEmpty ? nil : "SEARCH ALL DISKS",
                    action: model.searchText.isEmpty ? nil : { model.searchScope = .entireLibrary }
                )
            } else {
                FindEntryTable(model: model, rows: rows, showDisk: false)
            }
        }.background(Color.suiteBackground)
    }
}

private struct FindLibraryResults: View {
    @ObservedObject var model: Find950Model
    private var rows: [FindRow] {
        model.librarySearchResults.map { FindRow(image: $0.image, volume: $0.volume, entry: $0.entry) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LIBRARY SEARCH").font(SuiteFont.medium(17)).tracking(3.4)
                    Text(model.searchText).font(SuiteFont.regular(12)).foregroundStyle(Color.suiteUnit)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(rows.count) FILES").font(SuiteFont.medium(19)).monospacedDigit()
                    Text("ALL DISKS").font(SuiteFont.regular(10)).tracking(1.4).foregroundStyle(Color.suiteUnit)
                }
            }.padding(.horizontal, 16).frame(height: 64).background(Color.suiteBackground)
            if rows.isEmpty {
                SuiteEmptyState(systemImage: "magnifyingglass", title: "NO FILES MATCH", message: "No indexed file matches \(model.searchText).", actionTitle: nil, action: nil)
            } else {
                FindEntryTable(model: model, rows: rows, showDisk: true)
            }
        }
    }
}

private struct FindContentHeader: View {
    @ObservedObject var model: Find950Model
    let image: S950ImageCatalog
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(image.imageURL.lastPathComponent).font(SuiteFont.medium(17)).tracking(3.4).lineLimit(1)
                Text(image.imageURL.path).font(SuiteFont.regular(10)).foregroundStyle(Color.suiteUnit).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            if model.mediaStatus(for: image) != "LOCAL" {
                FindMediaBadge(
                    title: model.mediaStatus(for: image),
                    available: model.isImageAvailable(image)
                )
            }
            if let media = model.mediaVolume(for: image), media.isEjectable {
                Button {
                    model.eject(media)
                } label: {
                    Label("CLEAN EJECT", systemImage: "eject")
                }
                .buttonStyle(SuiteSecondaryButtonStyle())
                .disabled(!model.canEject(media))
            }
            Menu { ImageTagMenu(model: model, image: image) } label: {
                SuiteMenuLabel(title: "TAGS", systemImage: "tag")
            }.menuStyle(.borderlessButton)
            Button { model.openInEDIT950(image) } label: {
                SuiteLauncherLabel(target: .edit, title: "OPEN IN EDIT950")
            }.buttonStyle(SuiteSecondaryButtonStyle())
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(image.programCount) \(image.programCount == 1 ? "PROGRAM" : "PROGRAMS")").font(SuiteFont.medium(19)).monospacedDigit()
                Text("\(image.sampleCount) \(image.sampleCount == 1 ? "SAMPLE" : "SAMPLES")").font(SuiteFont.regular(10)).tracking(1.4).foregroundStyle(Color.suiteUnit).monospacedDigit()
            }
        }.padding(.horizontal, 16).frame(height: 64).background(Color.suiteBackground)
    }
}

private struct FindEntryTable: View {
    @ObservedObject var model: Find950Model
    @EnvironmentObject private var preferences: SuitePreferences
    let rows: [FindRow]
    let showDisk: Bool

    var body: some View {
        FindNativeEntryTable(
            model: model,
            rows: rows,
            showDisk: showDisk,
            rowHeight: preferences.density.rowHeight
        )
    }
}

private struct FindTypeGlyph: View {
    let kind: S950EntryKind
    var body: some View {
        Image(systemName: symbol).foregroundStyle(colour).font(SuiteFont.regular(12))
    }
    private var symbol: String {
        switch kind {
        case .program: "pianokeys"
        case .sample: "waveform"
        case .effects: "dial.medium"
        case .drumSet: "square.grid.3x3"
        case .cueList: "list.bullet"
        case .multi: "square.stack.3d.up"
        case .unknown, .other: "doc"
        }
    }
    private var colour: Color { kind == .program ? .suiteRed : kind == .sample ? .suiteBlue : .suiteUnit }
}

private struct FindInspector: View {
    @ObservedObject var model: Find950Model
    var body: some View {
        ScrollView {
            if let context = model.selectedEntry {
                entryInspector(context)
            } else if let image = model.selectedImage {
                diskInspector(image)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "info.circle").font(SuiteFont.regular(34)).opacity(0.4)
                    Text("SELECT A FILE TO INSPECT").font(SuiteFont.regular(10)).tracking(1.4).foregroundStyle(Color.suiteUnit)
                }.frame(maxWidth: .infinity).padding(.top, 80)
            }
        }.padding(16).background(Color.suitePanel)
    }

    @ViewBuilder
    private func entryInspector(_ context: (image: S950ImageCatalog, volume: S950VolumeCatalog, entry: S950LibraryEntry)) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 10) {
                FindTypeGlyph(kind: context.entry.kind).font(SuiteFont.regular(20))
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.entry.name).font(SuiteFont.regular(12))
                    Text(context.entry.kind.displayName).font(SuiteFont.regular(10)).tracking(1.4).foregroundStyle(Color.suiteUnit)
                }
            }
            inspectorSection("METADATA") {
                metadataRow("SIZE", context.entry.byteSize.formattedByteCount.uppercased())
                metadataRow("INDEX", context.entry.index.formatted())
                if context.entry.kind == .program { metadataRow("REFERENCES", context.entry.sampleReferences.count.formatted()) }
                if let sampleRate = context.entry.sampleRate { metadataRow("S9 RATE", "\(sampleRate.formatted()) HZ") }
            }
            inspectorSection("TAGS") { FindTagChips(tags: model.tagsFor(image: context.image, volume: context.volume, entry: context.entry), limit: 6) }
            inspectorSection("ACTIONS") { entryActions(context) }
            inspectorSection("LOCATION") {
                Text("\(context.image.name) · \(context.volume.name)").foregroundStyle(Color.suiteUnit)
                if let media = model.mediaVolume(for: context.image) {
                    metadataRow("MEDIA", media.statusTitle.uppercased())
                }
                Button("SHOW IN FINDER") { model.showInFinder(context.image.imageURL) }.buttonStyle(SuiteSecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func entryActions(_ context: (image: S950ImageCatalog, volume: S950VolumeCatalog, entry: S950LibraryEntry)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if context.entry.kind == .sample {
                Button("AUDITION") { model.toggleAudition(image: context.image, volume: context.volume, sample: context.entry) }.buttonStyle(SuitePrimaryButtonStyle(role: .sample))
                Button("EXPORT AS WAV…") { model.exportSampleAsWAV(image: context.image, volume: context.volume, sample: context.entry) }.buttonStyle(SuiteSecondaryButtonStyle())
                Button("PROGRAMS USING THIS SAMPLE") { model.showProgramsUsing(image: context.image, volume: context.volume, sample: context.entry) }.buttonStyle(SuiteSecondaryButtonStyle())
            } else if context.entry.kind == .program {
                Button { model.openProgramInPLAY950(image: context.image, program: context.entry) } label: {
                    SuiteLauncherLabel(target: .play, title: "OPEN IN PLAY950")
                }.buttonStyle(SuitePrimaryButtonStyle(role: .program))
                Button("EXPORT PROGRAM THROUGH EDIT950…") { model.exportProgramInEDIT950(image: context.image, volume: context.volume, program: context.entry) }.buttonStyle(SuiteSecondaryButtonStyle())
                Button("EXPORT AS ABLETON DRUM RACK THROUGH EDIT950…") { model.exportProgramInEDIT950(image: context.image, volume: context.volume, program: context.entry, exportMode: "abletonDrumRack") }.buttonStyle(SuiteSecondaryButtonStyle())
            }
            if context.entry.kind == .sample || context.entry.kind == .program {
                Button { model.toggleCollected(image: context.image, volume: context.volume, entry: context.entry) } label: {
                    Label(
                        model.isCollected(image: context.image, volume: context.volume, entry: context.entry) ? "REMOVE FROM COLLECTION" : "ADD TO COLLECTION",
                        systemImage: model.isCollected(image: context.image, volume: context.volume, entry: context.entry) ? "tray.and.arrow.up" : "tray.and.arrow.down"
                    )
                }.buttonStyle(SuiteSecondaryButtonStyle())
            }
            Menu { EntryTagMenu(model: model, image: context.image, volume: context.volume, entry: context.entry) } label: { SuiteMenuLabel(title: "TAGS", systemImage: "tag") }.menuStyle(.borderlessButton)
            Button { model.openInEDIT950(context.image) } label: {
                SuiteLauncherLabel(target: .edit, title: "OPEN DISK IN EDIT950")
            }.buttonStyle(SuiteSecondaryButtonStyle())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func diskInspector(_ image: S950ImageCatalog) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive").font(SuiteFont.regular(20)).foregroundStyle(Color.suiteUnit)
                VStack(alignment: .leading, spacing: 4) { Text(image.imageURL.lastPathComponent).font(SuiteFont.regular(12)); Text("DISK IMAGE").font(SuiteFont.regular(10)).foregroundStyle(Color.suiteUnit) }
            }
            inspectorSection("METADATA") {
                metadataRow("PROGRAMS", image.programCount.formatted())
                metadataRow("SAMPLES", image.sampleCount.formatted())
                metadataRow("VOLUMES", image.volumes.count.formatted())
                metadataRow("MEDIA", model.mediaStatus(for: image))
            }
            inspectorSection("TAGS") { FindTagChips(tags: model.tagsFor(image: image), limit: 6) }
            inspectorSection("ACTIONS") {
                VStack(alignment: .leading, spacing: 8) {
                    Menu { ImageTagMenu(model: model, image: image) } label: { SuiteMenuLabel(title: "TAGS", systemImage: "tag") }.menuStyle(.borderlessButton)
                    Button { model.openInEDIT950(image) } label: {
                        SuiteLauncherLabel(target: .edit, title: "OPEN IN EDIT950")
                    }.buttonStyle(SuiteSecondaryButtonStyle())
                    Button("SHOW IN FINDER") { model.showInFinder(image.imageURL) }.buttonStyle(SuiteSecondaryButtonStyle())
                    Button("RESCAN THIS IMAGE") { model.rescanImage(image) }.buttonStyle(SuiteSecondaryButtonStyle())
                    if let media = model.mediaVolume(for: image), media.isEjectable {
                        Button {
                            model.eject(media)
                        } label: {
                            Label("CLEAN & EJECT \(media.name.uppercased())", systemImage: "eject")
                        }
                        .buttonStyle(SuiteSecondaryButtonStyle())
                        .disabled(!model.canEject(media))
                    }
                }
            }
            inspectorSection("LOCATION") { Text(image.imageURL.path).font(SuiteFont.regular(10)).foregroundStyle(Color.suiteUnit).textSelection(.enabled) }
        }
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { SuiteSectionHeader(title: title); content() }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func metadataRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title).font(SuiteFont.regular(10)).tracking(1.2).foregroundStyle(Color.suiteLabel); Spacer(); Text(value).font(SuiteFont.regular(12)).monospacedDigit() }
    }
}

private struct FindStatusBar: View {
    @ObservedObject var model: Find950Model
    var body: some View {
        HStack(spacing: 10) {
            if model.isScanning {
                Image(systemName: "arrow.clockwise").foregroundStyle(Color.suiteUnit)
                Text("INDEXING").tracking(1.4)
                SuiteProgressBar(value: nil).frame(width: 120)
            } else if model.isWorking {
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(Color.suiteUnit)
                Text("WAITING FOR EDIT950").tracking(1.4)
                SuiteProgressBar(value: nil).frame(width: 120)
            } else {
                Circle().fill(Color.suiteUnit).frame(width: 6, height: 6)
                Text("\(model.visibleLibraryImages.count) DISKS INDEXED").tracking(1.4).monospacedDigit()
            }
            if let image = model.selectedImage { Text(image.imageURL.path).lineLimit(1).truncationMode(.head).foregroundStyle(Color.suiteUnit) }
            Spacer()
            Text("\(model.visibleProgramCount) \(model.visibleProgramCount == 1 ? "PROGRAM" : "PROGRAMS") · \(model.visibleSampleCount) \(model.visibleSampleCount == 1 ? "SAMPLE" : "SAMPLES")").monospacedDigit()
        }.font(SuiteFont.regular(10)).foregroundStyle(Color.suiteUnit).padding(.horizontal, 12).frame(height: 28).background(Color.suitePanel).overlay(alignment: .top) { Rectangle().fill(Color.suiteRule).frame(height: 1) }
    }
}

private struct FindTagChips: View {
    let tags: [LibraryTag]
    var limit = 3
    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(tags.prefix(limit))) { tag in
                HStack(spacing: 5) {
                    Circle().stroke(SuiteTagPalette.colour(for: tag.colorHex), lineWidth: 1.5).frame(width: 8, height: 8)
                    Text(tag.name).lineLimit(1)
                }.font(SuiteFont.regular(9)).padding(.horizontal, 6).padding(.vertical, 3).background(Color.suiteSlab2, in: RoundedRectangle(cornerRadius: 3))
            }
            if tags.count > limit { Text("+\(tags.count - limit)").font(SuiteFont.regular(9)).padding(.horizontal, 5).padding(.vertical, 3).background(Color.suiteSlab2, in: RoundedRectangle(cornerRadius: 3)) }
        }
    }
}

private struct ImageTagMenu: View {
    @ObservedObject var model: Find950Model
    let image: S950ImageCatalog
    var body: some View {
        if model.tags.isEmpty { Button("CREATE A TAG…") { model.showTagManager = true } }
        else {
            ForEach(model.tags) { tag in Button { model.toggleTag(tag, image: image) } label: { Label(tag.name, systemImage: model.isTagAssigned(tag, image: image) ? "checkmark" : "circle") } }
            Divider(); Button("EDIT TAGS…") { model.showTagManager = true }
        }
    }
}

private struct EntryTagMenu: View {
    @ObservedObject var model: Find950Model
    let image: S950ImageCatalog
    let volume: S950VolumeCatalog
    let entry: S950LibraryEntry
    var body: some View {
        if model.tags.isEmpty { Button("CREATE A TAG…") { model.showTagManager = true } }
        else {
            ForEach(model.tags) { tag in Button { model.toggleTag(tag, image: image, volume: volume, entry: entry) } label: { Label(tag.name, systemImage: model.isTagAssigned(tag, image: image, volume: volume, entry: entry) ? "checkmark" : "circle") } }
            Divider(); Button("EDIT TAGS…") { model.showTagManager = true }
        }
    }
}

private struct FindTagManager: View {
    @ObservedObject var model: Find950Model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("LIBRARY TAGS").font(SuiteFont.medium(15)).tracking(2.4); Spacer(); Button("ADD TAG") { model.addTag() }.buttonStyle(SuiteSecondaryButtonStyle()) }
            if model.tags.isEmpty {
                SuiteEmptyState(systemImage: "tag", title: "NO TAGS YET", message: "Create shared tags for IMG disks and Akai files.", actionTitle: "ADD TAG", action: model.addTag)
            } else {
                List(model.tags) { tag in
                    HStack(spacing: 12) {
                        FindTagColourChooser(model: model, tag: tag)
                        TextField("TAG NAME", text: Binding(get: { tag.name }, set: { model.updateTag(tag, name: $0) })).textFieldStyle(.plain).padding(8).background(Color.suiteSlab).clipShape(RoundedRectangle(cornerRadius: 6))
                        Button { model.deleteTag(tag) } label: { Image(systemName: "trash").foregroundStyle(Color.suiteRed) }.buttonStyle(.plain).help("DELETE TAG")
                    }.padding(.vertical, 4)
                }.scrollContentBackground(.hidden).background(Color.suiteBackground)
            }
            Text("Tags are shared with EDIT950 and are never written into IMG, P9 or S9 files.").font(SuiteFont.regular(10)).foregroundStyle(Color.suiteUnit)
            HStack {
                Spacer()
                Button("DONE") { dismiss() }
                    .buttonStyle(SuitePrimaryButtonStyle(role: .neutral))
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(minWidth: 620, minHeight: 420).background(Color.suitePanel)
    }
}

private struct FindTagColourChooser: View {
    @ObservedObject var model: Find950Model
    let tag: LibraryTag
    @State private var showingPalette = false

    var body: some View {
        Button { showingPalette.toggle() } label: {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(SuiteTagPalette.colour(for: tag.colorHex))
                    .frame(width: 25, height: 18)
                    .overlay { RoundedRectangle(cornerRadius: 3).stroke(Color.suiteRule2) }
                Text("COLOUR")
            }
        }
        .buttonStyle(SuiteSecondaryButtonStyle())
        .popover(isPresented: $showingPalette, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(SuiteTagPalette.groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 7) {
                            SuiteSectionHeader(title: group.title)
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 7), count: 10), spacing: 7) {
                                ForEach(group.colours, id: \.self) { hex in
                                    Button {
                                        model.updateTag(tag, colorHex: hex)
                                        showingPalette = false
                                    } label: {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(SuiteTagPalette.colour(for: hex))
                                            .frame(width: 32, height: 25)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .stroke(tag.colorHex.uppercased() == hex ? Color.suiteYellow : Color.suiteRule2, lineWidth: tag.colorHex.uppercased() == hex ? 3 : 1)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .help(hex)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .frame(width: 420, height: 360)
            .background(Color.suitePanel)
        }
    }
}

private struct FindCollection: View {
    @ObservedObject var model: Find950Model

    private var rows: [FindRow] {
        model.collectedEntries.map { FindRow(image: $0.image, volume: $0.volume, entry: $0.entry) }
    }

    private var manifest: FindCollectionManifest { model.collectionManifest }
    private var selectedCollectedIDs: Set<String> {
        model.selectedEntryIDs.intersection(Set(rows.map(\.id)))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("COLLECTION").font(SuiteFont.medium(15)).tracking(2.4)
                    Text("PROGRAMS AND SAMPLES GATHERED ACROSS THE LIBRARY")
                        .font(SuiteFont.regular(10)).tracking(1.1).foregroundStyle(Color.suiteUnit)
                }
                Spacer()
                if !rows.isEmpty {
                    if !selectedCollectedIDs.isEmpty {
                        Button("REMOVE SELECTED") {
                            model.setCollected(
                                entryIDs: selectedCollectedIDs,
                                collected: false,
                                actionName: "Remove from Collection"
                            )
                        }
                        .buttonStyle(SuiteSecondaryButtonStyle())
                    }
                    Button("CLEAR COLLECTION") { model.clearCollection() }
                        .buttonStyle(SuiteSecondaryButtonStyle())
                }
                Button(model.collectionExportStatus ?? "EXPORT TO FRESH IMG…") {
                    model.exportCollectionInEDIT950()
                }
                .buttonStyle(SuitePrimaryButtonStyle(role: .neutral))
                .disabled(rows.isEmpty || model.isWorking)
                .help(
                    manifest.canExport
                        ? "Send exactly the collected P9 and S9 files to EDIT950 for a new verified IMG."
                        : manifest.exportBlockers.joined(separator: " ")
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Color.suitePanel)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.suiteRule).frame(height: 1) }

            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("HIGH DENSITY IMG CAPACITY")
                            .font(SuiteFont.medium(10)).tracking(1.5)
                        Spacer()
                        Text("\(manifest.totalBytes.formattedByteCount.uppercased()) ALLOCATED · \(manifest.remainingBytes.formattedByteCount.uppercased()) REMAINING")
                            .font(SuiteFont.regular(10)).monospacedDigit()
                    }
                    SuiteProgressBar(value: manifest.limitingFraction, alertAt: 0.9)
                    HStack {
                        Text("\(manifest.explicitEntries.count) EXACT P9/S9 FILES COLLECTED")
                        Spacer()
                        Text("\(manifest.fileCount) OF \(FindCollectionManifest.maximumFileCount) DIRECTORY SLOTS")
                    }
                    .font(SuiteFont.regular(9)).tracking(1.1)
                    .foregroundStyle(Color.suiteUnit)
                    Text("P9 PROGRAMS ARE COPIED AS SELECTED. COLLECT ANY S9 FILES YOU ALSO WANT ON THE IMG.")
                        .font(SuiteFont.regular(9))
                        .foregroundStyle(Color.suiteUnit)
                    if !manifest.filenameCollisions.isEmpty {
                        Label(
                            "NATIVE NAME COLLISIONS: \(manifest.filenameCollisions.joined(separator: ", "))",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(SuiteFont.regular(9))
                        .foregroundStyle(Color.suiteRed)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.suiteBackground)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.suiteRule).frame(height: 1) }
            }

            if rows.isEmpty {
                SuiteEmptyState(
                    systemImage: "tray",
                    title: "COLLECTION IS EMPTY",
                    message: "Use the tray control on any P9 program or S9 sample to collect it here.",
                    actionTitle: nil,
                    action: nil
                )
            } else {
                FindEntryTable(model: model, rows: rows, showDisk: true)
            }
        }
        .background(Color.suiteBackground)
    }
}

private struct FindRelatedPrograms: View {
    @ObservedObject var model: Find950Model
    let context: RelatedProgramsContext
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("PROGRAMS USING \(context.sample.name)")
                        .font(SuiteFont.medium(15)).tracking(2.4)
                    Text("\(context.image.name) · \(context.volume.name)")
                        .foregroundStyle(Color.suiteUnit)
                }
                Spacer()
                Button("DONE") { dismiss() }
                    .buttonStyle(SuiteSecondaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            if context.programs.isEmpty { SuiteEmptyState(systemImage: "arrow.triangle.branch", title: "NO REFERENCING PROGRAMS FOUND", message: "The sample may be unused, or the program format may not expose a matching sample name.", actionTitle: nil, action: nil) }
            else {
                List(context.programs) { program in
                    HStack {
                        FindTypeGlyph(kind: .program)
                        Text(program.name)
                        Spacer()
                        Button { model.openProgramInPLAY950(image: context.image, program: program) } label: {
                            SuiteLauncherLabel(target: .play, title: "OPEN IN PLAY950")
                        }.buttonStyle(SuiteSecondaryButtonStyle())
                    }
                }.scrollContentBackground(.hidden).background(Color.suiteBackground)
            }
        }.padding(24).frame(minWidth: 760, minHeight: 420).background(Color.suitePanel)
    }
}

private extension Int64 {
    var formattedByteCount: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
