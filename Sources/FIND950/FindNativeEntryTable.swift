import AppKit
import S950Library
import SwiftUI

/// FIND950 owns the native table instead of reaching through SwiftUI's private
/// `Table` hierarchy. This gives selection, keyboard focus and contextual menus
/// one stable AppKit boundary.
struct FindNativeEntryTable: NSViewRepresentable {
    @ObservedObject var model: Find950Model
    let rows: [FindRow]
    let showDisk: Bool
    let rowHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = FindNativeTableView()
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.gridStyleMask = [.solidHorizontalGridLineMask]
        table.gridColor = NSColor.suiteDynamic(
            light: NSColor(white: 0, alpha: 0.08),
            dark: NSColor(white: 1, alpha: 0.07)
        )
        table.intercellSpacing = NSSize(width: 0, height: 1)
        table.backgroundColor = .suiteDynamic(light: 0xF7F6F2, dark: 0x0A0A0C)
        table.focusRingType = .none
        table.headerView = NSTableHeaderView()
        table.autosaveName = showDisk
            ? "FIND950.nativeTable.library" : "FIND950.nativeTable.disk"
        table.autosaveTableColumns = true
        context.coordinator.installColumns(in: table, showDisk: showDisk)
        table.onSpace = { [weak model] in
            model?.handleSpaceForSelectedEntry() ?? false
        }
        table.contextMenuProvider = { [weak coordinator = context.coordinator] row in
            coordinator?.contextMenu(for: row)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = table.backgroundColor
        context.coordinator.table = table
        context.coordinator.update(
            model: model,
            sourceRows: rows,
            showDisk: showDisk,
            rowHeight: rowHeight
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            model: model,
            sourceRows: rows,
            showDisk: showDisk,
            rowHeight: rowHeight
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        fileprivate weak var table: FindNativeTableView?
        private var model: Find950Model
        private var sourceRows: [FindRow] = []
        private var displayedRows: [FindRow] = []
        private var applyingSelection = false
        private var contextRowID: String?
        private var renderedRowKeys: [RowRenderKey] = []
        private var renderedCollectedIDs: Set<String> = []
        private var renderedAuditioningID: String?
        private var renderedShowDisk: Bool?
        private var renderedRowHeight: CGFloat?

        private struct RowRenderKey: Equatable {
            let id: String
            let diskName: String
            let mediaStatus: String
            let imageAvailable: Bool
            let typeName: String
            let byteSize: Int64
            let sampleRate: Int?
        }

        init(model: Find950Model) {
            self.model = model
        }

        func installColumns(in table: NSTableView, showDisk: Bool) {
            let specifications: [(
                id: String,
                title: String,
                width: CGFloat,
                min: CGFloat,
                max: CGFloat,
                sortKey: String?
            )] = [
                ("kind", "", 24, 24, 24, "type"),
                ("collection", "", 26, 26, 26, nil),
                ("audition", "", 26, 26, 26, nil),
                ("disk", "DISK", 110, 72, 320, "disk"),
                ("media", "MEDIA", 92, 76, 180, "media"),
                ("name", "NAME", 128, 80, 640, "name"),
                ("type", "TYPE", 60, 56, 180, "type"),
                ("rate", "S9 RATE", 70, 62, 180, "rate"),
                ("size", "SIZE", 58, 50, 180, "size"),
                ("actions", "", 52, 52, 52, nil)
            ]
            for specification in specifications {
                let column = NSTableColumn(identifier: .init(specification.id))
                column.title = specification.title
                column.width = specification.width
                column.minWidth = specification.min
                column.maxWidth = specification.max
                column.resizingMask = specification.min == specification.max
                    ? [] : [.userResizingMask, .autoresizingMask]
                if let sortKey = specification.sortKey {
                    column.sortDescriptorPrototype = NSSortDescriptor(
                        key: sortKey,
                        ascending: true
                    )
                }
                if specification.id == "disk" || specification.id == "media" {
                    column.isHidden = !showDisk
                }
                table.addTableColumn(column)
            }
        }

        func update(
            model: Find950Model,
            sourceRows: [FindRow],
            showDisk: Bool,
            rowHeight: CGFloat
        ) {
            self.model = model
            self.sourceRows = sourceRows
            guard let table else { return }

            let effectiveRowHeight = max(24, rowHeight - 1)
            if renderedRowHeight != effectiveRowHeight {
                renderedRowHeight = effectiveRowHeight
                table.rowHeight = effectiveRowHeight
            }
            if renderedShowDisk != showDisk {
                renderedShowDisk = showDisk
                table.tableColumn(withIdentifier: .init("disk"))?.isHidden = !showDisk
                table.tableColumn(withIdentifier: .init("media"))?.isHidden = !showDisk
            }

            let rowKeys = sourceRows.map {
                RowRenderKey(
                    id: $0.id,
                    diskName: $0.diskName,
                    mediaStatus: model.mediaStatus(for: $0.image),
                    imageAvailable: model.isImageAvailable($0.image),
                    typeName: $0.typeName,
                    byteSize: $0.byteSize,
                    sampleRate: $0.entry.sampleRate
                )
            }
            let rowsChanged = rowKeys != renderedRowKeys
            if rowsChanged {
                renderedRowKeys = rowKeys
                sortDisplayedRows()
                table.reloadData()
            } else {
                reloadDynamicColumnsIfNeeded(in: table)
            }
            renderedCollectedIDs = model.collectedEntryIDs
            renderedAuditioningID = model.auditioningID
            applyModelSelection()
        }

        private func reloadDynamicColumnsIfNeeded(in table: NSTableView) {
            if renderedCollectedIDs != model.collectedEntryIDs,
               let column = table.tableColumn(
                   withIdentifier: .init("collection")
               ).map({ table.column(withIdentifier: $0.identifier) }),
               column >= 0 {
                table.reloadData(
                    forRowIndexes: IndexSet(integersIn: 0..<displayedRows.count),
                    columnIndexes: IndexSet(integer: column)
                )
            }

            if renderedAuditioningID != model.auditioningID,
               let column = table.tableColumn(
                   withIdentifier: .init("audition")
               ).map({ table.column(withIdentifier: $0.identifier) }),
               column >= 0 {
                let affectedIDs = Set(
                    [renderedAuditioningID, model.auditioningID].compactMap { $0 }
                )
                let affectedRows = IndexSet(displayedRows.indices.filter {
                    let row = displayedRows[$0]
                    return affectedIDs.contains(
                        "\(row.image.imageURL.path)|\(row.volume.path)|\(row.entry.id)"
                    )
                })
                if !affectedRows.isEmpty {
                    table.reloadData(
                        forRowIndexes: affectedRows,
                        columnIndexes: IndexSet(integer: column)
                    )
                }
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            displayedRows.count
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row rowIndex: Int
        ) -> NSView? {
            guard displayedRows.indices.contains(rowIndex), let tableColumn else {
                return nil
            }
            let row = displayedRows[rowIndex]
            switch tableColumn.identifier.rawValue {
            case "kind":
                return glyphCell(for: row)
            case "disk":
                return textCell(row.diskName, size: 11, color: .suiteDynamic(
                    light: 0x5F636B,
                    dark: 0x8D939D
                ))
            case "media":
                return mediaCell(for: row)
            case "name":
                return textCell(row.name, size: 12, middleTruncation: true)
            case "type":
                return textCell(row.typeName.uppercased(), size: 10, color: .suiteDynamic(
                    light: 0x9095A0,
                    dark: 0x5E636D
                ))
            case "rate":
                return textCell(
                    row.entry.sampleRate.map { "\($0.formatted()) HZ" } ?? "—",
                    size: 11,
                    color: row.entry.sampleRate == nil
                        ? .suiteDynamic(light: 0x9095A0, dark: 0x5E636D)
                        : .suiteDynamic(light: 0x101114, dark: 0xF1F1F5)
                )
            case "size":
                return textCell(
                    ByteCountFormatter.string(
                        fromByteCount: row.byteSize,
                        countStyle: .file
                    ).uppercased(),
                    size: 12,
                    alignment: .right
                )
            case "collection":
                return collectionCell(for: row)
            case "audition":
                return auditionCell(for: row)
            case "actions":
                return actionCell(for: row)
            default:
                return nil
            }
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = FindNativeRowView()
            rowView.isAlternate = row.isMultiple(of: 2)
            return rowView
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !applyingSelection, let table else { return }
            let identifiers = Set(table.selectedRowIndexes.compactMap { index in
                displayedRows.indices.contains(index) ? displayedRows[index].id : nil
            })
            if identifiers != model.selectedEntryIDs {
                model.selectedEntryIDs = identifiers
            }
        }

        func tableView(
            _ tableView: NSTableView,
            sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
        ) {
            let selection = model.selectedEntryIDs
            sortDisplayedRows()
            tableView.reloadData()
            model.selectedEntryIDs = selection
            applyModelSelection()
        }

        private func sortDisplayedRows() {
            guard let descriptors = table?.sortDescriptors, !descriptors.isEmpty else {
                displayedRows = sourceRows
                return
            }
            displayedRows = sourceRows.sorted { left, right in
                for descriptor in descriptors {
                    let result = compare(left, right, key: descriptor.key ?? "")
                    if result != .orderedSame {
                        return descriptor.ascending
                            ? result == .orderedAscending : result == .orderedDescending
                    }
                }
                return left.id.localizedStandardCompare(right.id) == .orderedAscending
            }
        }

        private func compare(_ left: FindRow, _ right: FindRow, key: String) -> ComparisonResult {
            switch key {
            case "disk": left.diskName.localizedStandardCompare(right.diskName)
            case "media": model.mediaStatus(for: left.image).localizedStandardCompare(
                model.mediaStatus(for: right.image)
            )
            case "name": left.name.localizedStandardCompare(right.name)
            case "type": left.typeName.localizedStandardCompare(right.typeName)
            case "rate": NSNumber(value: left.sampleRateSortValue).compare(
                NSNumber(value: right.sampleRateSortValue)
            )
            case "size": NSNumber(value: left.byteSize).compare(NSNumber(value: right.byteSize))
            default: .orderedSame
            }
        }

        private func applyModelSelection() {
            guard let table else { return }
            let indexes = IndexSet(displayedRows.indices.filter {
                model.selectedEntryIDs.contains(displayedRows[$0].id)
            })
            guard indexes != table.selectedRowIndexes else { return }
            applyingSelection = true
            table.selectRowIndexes(indexes, byExtendingSelection: false)
            applyingSelection = false
        }

        private func textCell(
            _ text: String,
            size: CGFloat,
            color: NSColor = .suiteDynamic(light: 0x101114, dark: 0xF1F1F5),
            alignment: NSTextAlignment = .left,
            middleTruncation: Bool = false
        ) -> NSView {
            let cell = FindNativeCellView()
            let field = NSTextField(labelWithString: text)
            field.font = suiteFont(size: size)
            field.textColor = color
            field.alignment = alignment
            field.lineBreakMode = middleTruncation ? .byTruncatingMiddle : .byTruncatingTail
            field.maximumNumberOfLines = 1
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.normalTextColor = color
            cell.textField = field
            cell.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 7),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -7),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        private func glyphCell(for row: FindRow) -> NSView {
            let cell = FindNativeCellView()
            let imageView = NSImageView()
            imageView.image = NSImage(
                systemSymbolName: glyphSymbol(for: row.entry.kind),
                accessibilityDescription: row.typeName
            )
            imageView.contentTintColor = glyphColor(for: row.entry.kind)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 15),
                imageView.heightAnchor.constraint(equalToConstant: 15)
            ])
            return cell
        }

        private func mediaCell(for row: FindRow) -> NSView {
            let cell = FindNativeCellView()
            let available = model.isImageAvailable(row.image)
            let statusColor = available
                ? NSColor.suiteDynamic(light: 0x1E22E8, dark: 0x3A53FF)
                : NSColor.suiteDynamic(light: 0x9095A0, dark: 0x5E636D)
            let imageView = NSImageView()
            imageView.image = NSImage(
                systemSymbolName: available
                    ? "externaldrive.fill" : "externaldrive.badge.xmark",
                accessibilityDescription: model.mediaStatus(for: row.image)
            )
            imageView.contentTintColor = statusColor
            imageView.translatesAutoresizingMaskIntoConstraints = false
            let field = NSTextField(labelWithString: model.mediaStatus(for: row.image))
            field.font = suiteFont(size: 9)
            field.textColor = statusColor
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.normalTextColor = statusColor
            cell.textField = field
            cell.addSubview(imageView)
            cell.addSubview(field)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 7),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 14),
                imageView.heightAnchor.constraint(equalToConstant: 14),
                field.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        private func auditionCell(for row: FindRow) -> NSView {
            let cell = FindNativeCellView()
            guard row.entry.kind == .sample else { return cell }
            let playing = model.isAuditioning(
                image: row.image,
                volume: row.volume,
                sample: row.entry
            )
            let button = actionButton(
                symbol: playing ? "stop.fill" : "play.fill",
                color: .suiteDynamic(light: 0x1E22E8, dark: 0x3A53FF),
                toolTip: playing ? "STOP AUDITION" : "AUDITION \(row.entry.name)",
                rowID: row.id,
                action: .audition
            )
            center(button, in: cell)
            return cell
        }

        private func collectionCell(for row: FindRow) -> NSView {
            let cell = FindNativeCellView()
            guard row.entry.kind == .sample || row.entry.kind == .program else {
                return cell
            }
            let collected = model.isCollected(
                image: row.image,
                volume: row.volume,
                entry: row.entry
            )
            let button = actionButton(
                symbol: collected ? "tray.full.fill" : "tray.and.arrow.down",
                color: collected
                    ? .suite(hex: 0xFFC400)
                    : .suiteDynamic(light: 0x5F636B, dark: 0x8D939D),
                toolTip: collected ? "REMOVE FROM COLLECTION" : "ADD TO COLLECTION",
                rowID: row.id,
                action: .collection
            )
            center(button, in: cell)
            return cell
        }

        private func actionCell(for row: FindRow) -> NSView {
            let cell = FindNativeCellView()
            var buttons: [NSView] = []
            if row.entry.kind == .sample {
                buttons.append(actionButton(
                    symbol: "arrow.triangle.branch",
                    color: .suiteDynamic(light: 0xE8140A, dark: 0xFF2010),
                    toolTip: "PROGRAMS USING THIS SAMPLE",
                    rowID: row.id,
                    action: .relatedPrograms
                ))
            } else if row.entry.kind == .program {
                buttons.append(actionButton(
                    symbol: "play.square.stack",
                    color: .suiteDynamic(light: 0xE8140A, dark: 0xFF2010),
                    toolTip: "OPEN IN PLAY950",
                    rowID: row.id,
                    action: .play950
                ))
            }
            buttons.append(actionButton(
                symbol: "ellipsis",
                color: .suiteDynamic(light: 0x101114, dark: 0xF1F1F5),
                toolTip: "MORE ACTIONS",
                rowID: row.id,
                action: .more
            ))
            let stack = NSStackView(views: buttons)
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 6
            stack.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        private func actionButton(
            symbol: String,
            color: NSColor,
            toolTip: String,
            rowID: String,
            action: FindNativeAction
        ) -> FindNativeActionButton {
            let button = FindNativeActionButton()
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)
            button.imagePosition = .imageOnly
            button.contentTintColor = color
            button.isBordered = false
            button.focusRingType = .none
            button.toolTip = toolTip
            button.rowID = rowID
            button.nativeAction = action
            if action == .collection {
                button.selectionSnapshotProvider = { [weak self] in
                    self?.selectionSnapshot(fallbackRowID: rowID) ?? [rowID]
                }
            }
            button.target = self
            button.action = #selector(handleAction(_:))
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 22),
                button.heightAnchor.constraint(equalToConstant: 22)
            ])
            return button
        }

        private func center(_ view: NSView, in cell: NSView) {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                view.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        private func suiteFont(size: CGFloat) -> NSFont {
            NSFont(name: "JetBrainsMono-Regular", size: size)
                ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        }

        private func glyphSymbol(for kind: S950EntryKind) -> String {
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

        private func glyphColor(for kind: S950EntryKind) -> NSColor {
            switch kind {
            case .program: .suiteDynamic(light: 0xE8140A, dark: 0xFF2010)
            case .sample: .suiteDynamic(light: 0x1E22E8, dark: 0x3A53FF)
            default: .suiteDynamic(light: 0x9095A0, dark: 0x5E636D)
            }
        }

        @objc private func handleAction(_ sender: FindNativeActionButton) {
            guard let row = displayedRows.first(where: { $0.id == sender.rowID }) else {
                return
            }
            select(row)
            switch sender.nativeAction {
            case .audition:
                model.toggleAudition(image: row.image, volume: row.volume, sample: row.entry)
            case .collection:
                toggleCollection(
                    entryIDs: sender.selectionSnapshot.isEmpty
                        ? [row.id] : sender.selectionSnapshot
                )
            case .relatedPrograms:
                model.showProgramsUsing(image: row.image, volume: row.volume, sample: row.entry)
            case .play950:
                model.openProgramInPLAY950(image: row.image, program: row.entry)
            case .more:
                guard let menu = contextMenu(for: displayedRows.firstIndex(where: {
                    $0.id == row.id
                }) ?? -1) else { return }
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 3), in: sender)
                table?.window?.makeFirstResponder(table)
            }
        }

        private func selectionSnapshot(fallbackRowID: String) -> Set<String> {
            guard let table,
                  let fallbackIndex = displayedRows.firstIndex(where: {
                      $0.id == fallbackRowID
                  }),
                  table.selectedRowIndexes.contains(fallbackIndex)
            else { return [fallbackRowID] }
            return Set(table.selectedRowIndexes.compactMap { index in
                displayedRows.indices.contains(index) ? displayedRows[index].id : nil
            })
        }

        private func toggleCollection(entryIDs: Set<String>) {
            let eligibleIDs = Set(entryIDs.filter { id in
                guard let selected = displayedRows.first(where: { $0.id == id }) else {
                    return false
                }
                return selected.entry.kind == .sample || selected.entry.kind == .program
            })
            guard !eligibleIDs.isEmpty else { return }
            model.selectedEntryIDs = entryIDs
            let allCollected = eligibleIDs.allSatisfy(model.collectedEntryIDs.contains)
            model.setCollected(
                entryIDs: eligibleIDs,
                collected: !allCollected,
                actionName: allCollected
                    ? "Remove from Collection" : "Add to Collection"
            )
        }

        private func select(_ row: FindRow) {
            guard let table,
                  let index = displayedRows.firstIndex(where: { $0.id == row.id })
            else { return }
            if !table.selectedRowIndexes.contains(index) {
                table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            }
            table.window?.makeFirstResponder(table)
        }

        func contextMenu(for rowIndex: Int) -> NSMenu? {
            guard displayedRows.indices.contains(rowIndex) else { return nil }
            let row = displayedRows[rowIndex]
            contextRowID = row.id
            let menu = NSMenu()
            menu.autoenablesItems = false
            let selectedRows = table?.selectedRowIndexes.compactMap { index in
                displayedRows.indices.contains(index) ? displayedRows[index] : nil
            } ?? [row]
            let eligibleIDs = Set(selectedRows.compactMap { selected -> String? in
                selected.entry.kind == .sample || selected.entry.kind == .program
                    ? selected.id : nil
            })
            if !eligibleIDs.isEmpty {
                let allCollected = eligibleIDs.allSatisfy(model.collectedEntryIDs.contains)
                menu.addItem(menuItem(
                    allCollected ? "REMOVE FROM COLLECTION" : "ADD TO COLLECTION",
                    symbol: allCollected ? "tray.and.arrow.up" : "tray.and.arrow.down",
                    action: #selector(toggleContextCollection)
                ))
                menu.addItem(.separator())
            }
            if selectedRows.count == 1 {
                menu.addItem(menuItem(
                    "OPEN DISK IN EDIT950",
                    symbol: "arrow.up.forward.app",
                    action: #selector(openContextInEDIT950)
                ))
                if row.entry.kind == .sample {
                    menu.addItem(menuItem(
                        "EXPORT AS WAV…",
                        symbol: "waveform",
                        action: #selector(exportContextWAV)
                    ))
                }
                if row.entry.kind == .program {
                    menu.addItem(menuItem(
                        "OPEN IN PLAY950",
                        symbol: "play.square.stack",
                        action: #selector(openContextInPLAY950)
                    ))
                    menu.addItem(menuItem(
                        "EXPORT PROGRAM THROUGH EDIT950…",
                        symbol: "square.and.arrow.up",
                        action: #selector(exportContextProgram)
                    ))
                    menu.addItem(menuItem(
                        "EXPORT ABLETON DRUM RACK THROUGH EDIT950…",
                        symbol: "square.grid.3x3",
                        action: #selector(exportContextAbleton)
                    ))
                }
                menu.addItem(.separator())
                menu.addItem(menuItem(
                    "SHOW IN FINDER",
                    symbol: "folder",
                    action: #selector(showContextInFinder)
                ))
                if let media = model.mediaVolume(for: row.image), media.isEjectable {
                    let ejectItem = menuItem(
                        "CLEAN & EJECT \(media.name.uppercased())",
                        symbol: "eject",
                        action: #selector(ejectContextMedia)
                    )
                    ejectItem.isEnabled = model.canEject(media)
                    menu.addItem(ejectItem)
                }
            }
            return menu.items.isEmpty ? nil : menu
        }

        private func menuItem(
            _ title: String,
            symbol: String,
            action: Selector
        ) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            item.isEnabled = true
            return item
        }

        private var contextRow: FindRow? {
            contextRowID.flatMap { id in displayedRows.first(where: { $0.id == id }) }
        }

        @objc private func toggleContextCollection() {
            guard let table else { return }
            let identifiers = Set(table.selectedRowIndexes.compactMap { index -> String? in
                guard displayedRows.indices.contains(index) else { return nil }
                let row = displayedRows[index]
                return row.entry.kind == .sample || row.entry.kind == .program
                    ? row.id : nil
            })
            guard !identifiers.isEmpty else { return }
            let allCollected = identifiers.allSatisfy(model.collectedEntryIDs.contains)
            model.setCollected(
                entryIDs: identifiers,
                collected: !allCollected,
                actionName: allCollected ? "Remove from Collection" : "Add to Collection"
            )
        }

        @objc private func openContextInEDIT950() {
            guard let row = contextRow else { return }
            model.openInEDIT950(row.image)
        }

        @objc private func exportContextWAV() {
            guard let row = contextRow else { return }
            model.exportSampleAsWAV(image: row.image, volume: row.volume, sample: row.entry)
        }

        @objc private func openContextInPLAY950() {
            guard let row = contextRow else { return }
            model.openProgramInPLAY950(image: row.image, program: row.entry)
        }

        @objc private func exportContextProgram() {
            guard let row = contextRow else { return }
            model.exportProgramInEDIT950(
                image: row.image,
                volume: row.volume,
                program: row.entry
            )
        }

        @objc private func exportContextAbleton() {
            guard let row = contextRow else { return }
            model.exportProgramInEDIT950(
                image: row.image,
                volume: row.volume,
                program: row.entry,
                exportMode: "abletonDrumRack"
            )
        }

        @objc private func showContextInFinder() {
            guard let row = contextRow else { return }
            model.showInFinder(row.image.imageURL)
        }

        @objc private func ejectContextMedia() {
            guard let row = contextRow,
                  let media = model.mediaVolume(for: row.image)
            else { return }
            model.eject(media)
        }
    }
}

private enum FindNativeAction: Equatable {
    case audition
    case collection
    case relatedPrograms
    case play950
    case more
}

private final class FindNativeActionButton: NSButton {
    var rowID = ""
    var nativeAction: FindNativeAction = .more
    var selectionSnapshotProvider: (() -> Set<String>)?
    private(set) var selectionSnapshot: Set<String> = []

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        selectionSnapshot = selectionSnapshotProvider?() ?? []
        super.mouseDown(with: event)
    }
}

private final class FindNativeTableView: NSTableView {
    var onSpace: (() -> Bool)?
    var contextMenuProvider: ((Int) -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        let disallowed = event.modifierFlags.intersection([.command, .control, .option])
        if event.keyCode == 49, disallowed.isEmpty, onSpace?() == true {
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: location)
        guard clickedRow >= 0 else { return nil }
        if !selectedRowIndexes.contains(clickedRow) {
            selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }
        return contextMenuProvider?(clickedRow)
    }
}

private final class FindNativeRowView: NSTableRowView {
    var isAlternate = false

    override var isSelected: Bool {
        didSet {
            needsDisplay = true
            updateCellAppearance()
        }
    }

    override var isEmphasized: Bool {
        didSet { needsDisplay = true }
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        updateCellAppearance()
    }

    override func drawBackground(in dirtyRect: NSRect) {
        let color: NSColor = isAlternate
            ? .suiteDynamic(light: 0xEAE9E3, dark: 0x17171C)
            : .suiteDynamic(light: 0xF7F6F2, dark: 0x0A0A0C)
        color.setFill()
        dirtyRect.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        let alpha: CGFloat = isEmphasized ? 1 : 0.72
        NSColor.suite(hex: 0xFFC400).withAlphaComponent(alpha).setFill()
        bounds.fill()
    }

    private func updateCellAppearance() {
        for cell in subviews.compactMap({ $0 as? FindNativeCellView }) {
            cell.isRowSelected = isSelected
        }
    }
}

private final class FindNativeCellView: NSTableCellView {
    var normalTextColor: NSColor = .labelColor
    var isRowSelected = false {
        didSet {
            textField?.textColor = isRowSelected
                ? .suite(hex: 0x101114) : normalTextColor
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let row = superview as? NSTableRowView {
            isRowSelected = row.isSelected
        }
    }
}
