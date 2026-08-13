import AppKit
import SwiftUI

struct SuiteTableCell<Content: View>: View {
    let selected: Bool
    let alignment: Alignment
    @ViewBuilder let content: () -> Content

    init(
        selected: Bool,
        alignment: Alignment = .center,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.selected = selected
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        content()
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: alignment
            )
            .background(selected ? Color.suiteYellow : Color.clear)
    }
}

/// SwiftUI's macOS `Table` does not consistently honour `tint` for selected
/// rows. This colours the native row views without replacing table behaviour.
struct SuiteTableSelectionColor: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.hostView = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        context.coordinator.applySoon()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        weak var hostView: NSView?
        private var observers: [NSObjectProtocol] = []
        private let selectedColor = NSColor(
            calibratedRed: 1,
            green: 196.0 / 255.0,
            blue: 0,
            alpha: 1
        )

        func install() {
            guard observers.isEmpty else { return }
            observers = [
                NotificationCenter.default.addObserver(
                    forName: NSTableView.selectionDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    guard let coordinator = self else { return }
                    Task { @MainActor in coordinator.apply() }
                },
                NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    guard let coordinator = self else { return }
                    Task { @MainActor in coordinator.apply() }
                }
            ]
            applySoon()
        }

        func uninstall() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }

        func applySoon() {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.apply()
            }
        }

        private func apply() {
            guard let root = hostView?.window?.contentView else { return }
            for table in Self.tables(in: root) {
                table.enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
                for rowIndex in 0..<table.numberOfRows {
                    guard let row = table.rowView(
                        atRow: rowIndex,
                        makeIfNecessary: false
                    ) else { continue }
                    let selected = table.selectedRowIndexes.contains(rowIndex)
                    row.wantsLayer = true
                    row.selectionHighlightStyle = selected ? .none : .regular
                    row.layer?.backgroundColor = selected
                        ? selectedColor.cgColor : nil
                    for cell in row.subviews {
                        cell.wantsLayer = true
                        cell.layer?.backgroundColor = selected
                            ? selectedColor.cgColor : nil
                    }
                }
            }
        }

        private static func tables(in view: NSView) -> [NSTableView] {
            var result = (view as? NSTableView).map { [$0] } ?? []
            for child in view.subviews {
                result.append(contentsOf: tables(in: child))
            }
            return result
        }
    }
}
