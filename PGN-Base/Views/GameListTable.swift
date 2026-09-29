import AppKit
import SwiftUI

/// The sidebar list of games, backed by `NSTableView`.
///
/// SwiftUI's `List` creates state for every row up front, which takes gigabytes for a database
/// with hundreds of thousands of games. A table view only asks for the rows on screen.
struct GameListTable: NSViewRepresentable {
    let database: GameDatabase
    let gameCount: Int
    @Binding var selection: Int?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.style = .sourceList
        tableView.headerView = nil
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = 36
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.allowsEmptySelection = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("game"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.setAccessibilityLabel("Games")

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let tableView = scrollView.documentView as? NSTableView else { return }

        if coordinator.rowCount != gameCount {
            coordinator.rowCount = gameCount
            tableView.reloadData()
            tableView.sizeLastColumnToFit()
        }

        let selectedRow = tableView.selectedRow >= 0 ? tableView.selectedRow : nil
        if selection != selectedRow {
            if let selection, selection < gameCount {
                tableView.selectRowIndexes(IndexSet(integer: selection), byExtendingSelection: false)
                tableView.scrollRowToVisible(selection)
            } else {
                tableView.deselectAll(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: GameListTable
        var rowCount = 0

        init(_ parent: GameListTable) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rowCount
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let cell = tableView.makeView(withIdentifier: GameCellView.identifier, owner: nil) as? GameCellView ?? GameCellView()
            cell.configure(with: parent.database.header(at: row))
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            let row = tableView.selectedRow >= 0 ? tableView.selectedRow : nil
            if parent.selection != row {
                parent.selection = row
            }
        }
    }
}

/// A row showing the players, with the event, date, and result underneath.
private final class GameCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("GameCell")

    private let titleField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier

        for field in [titleField, detailField] {
            field.lineBreakMode = .byTruncatingTail
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        detailField.font = .preferredFont(forTextStyle: .caption1)
        detailField.textColor = .secondaryLabelColor
        // Lets the table adjust the title's color for the selected row.
        textField = titleField

        let stack = NSStackView(views: [titleField, detailField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with game: PGNGame) {
        titleField.stringValue = game.title
        detailField.stringValue = [game.tag("Event"), game.date, game.tag("Result")].compactMap(\.self).joined(separator: " · ")
    }
}
