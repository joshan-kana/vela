import AppKit

enum CommandPaletteCommand: CaseIterable {
  case createIssue
  case openIssue
  case resolveIssue
  case searchMyWork

  var title: String {
    switch self {
    case .createIssue:
      "Create issue"
    case .openIssue:
      "Open selected issue"
    case .resolveIssue:
      "Complete selected issue"
    case .searchMyWork:
      "Search My Work"
    }
  }

  var shortcut: String {
    switch self {
    case .createIssue:
      "C"
    case .openIssue:
      "Return"
    case .resolveIssue:
      "E"
    case .searchMyWork:
      "/"
    }
  }
}

final class CommandPaletteViewController:
  NSViewController,
  NSTableViewDataSource,
  NSTableViewDelegate,
  NSSearchFieldDelegate
{
  private let commands: [CommandPaletteCommand]
  private let onSelect: (CommandPaletteCommand) -> Void
  private let onCancel: () -> Void

  private let searchField = NSSearchField()
  private let tableView = NSTableView()
  private var filtered: [CommandPaletteCommand] = []

  init(
    commands: [CommandPaletteCommand],
    onSelect: @escaping (CommandPaletteCommand) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.commands = commands
    self.onSelect = onSelect
    self.onCancel = onCancel
    self.filtered = commands
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    let root = NSView()

    let title = NSTextField(labelWithString: "Commands")
    title.font = .systemFont(ofSize: 18, weight: .semibold)

    let close = NSButton(title: "Close", target: self, action: #selector(cancel))
    close.bezelStyle = .inline

    let header = NSStackView(views: [title, NSView(), close])
    header.orientation = .horizontal
    header.alignment = .centerY

    searchField.placeholderString = "Type a command"
    searchField.setAccessibilityLabel("Command palette")
    searchField.delegate = self

    tableView.headerView = nil
    tableView.rowHeight = 38
    tableView.delegate = self
    tableView.dataSource = self
    tableView.target = self
    tableView.action = #selector(invokeSelected)

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)

    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.borderType = .noBorder
    scroll.documentView = tableView

    let panel = NSStackView(views: [header, searchField, scroll])
    panel.orientation = .vertical
    panel.alignment = .leading
    panel.spacing = 12
    panel.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
    panel.wantsLayer = true
    panel.layer?.cornerRadius = 12
    panel.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

    for subview in [panel] {
      subview.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(subview)
    }

    NSLayoutConstraint.activate([
      panel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      panel.topAnchor.constraint(equalTo: root.topAnchor, constant: 72),
      panel.widthAnchor.constraint(equalToConstant: 520),
      panel.heightAnchor.constraint(equalToConstant: 310),

      header.widthAnchor.constraint(equalTo: panel.widthAnchor, constant: -36),
      searchField.widthAnchor.constraint(equalTo: panel.widthAnchor, constant: -36),
      scroll.widthAnchor.constraint(equalTo: panel.widthAnchor, constant: -36),
      scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 190),
    ])

    view = root
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    selectFirst()
    view.window?.makeFirstResponder(searchField)
  }

  func controlTextDidChange(_ notification: Notification) {
    let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    filtered =
      query.isEmpty
      ? commands
      : commands.filter { $0.title.lowercased().contains(query) }
    tableView.reloadData()
    selectFirst()
  }

  func control(
    _ control: NSControl,
    textView: NSTextView,
    doCommandBy commandSelector: Selector
  ) -> Bool {
    switch commandSelector {
    case #selector(NSResponder.moveDown(_:)):
      moveSelection(by: 1)
      return true
    case #selector(NSResponder.moveUp(_:)):
      moveSelection(by: -1)
      return true
    case #selector(NSResponder.insertNewline(_:)):
      invokeSelected()
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      cancel()
      return true
    default:
      return false
    }
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    filtered.count
  }

  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  ) -> NSView? {
    let command = filtered[row]
    let title = NSTextField(labelWithString: command.title)
    title.lineBreakMode = .byTruncatingTail

    let shortcut = NSTextField(labelWithString: command.shortcut)
    shortcut.textColor = .secondaryLabelColor
    shortcut.font = .monospacedSystemFont(ofSize: 11, weight: .regular)

    let view = NSStackView(views: [title, NSView(), shortcut])
    view.orientation = .horizontal
    view.alignment = .centerY
    view.spacing = 8
    return view
  }

  @objc private func invokeSelected() {
    let row = tableView.selectedRow
    guard filtered.indices.contains(row) else {
      return
    }

    onSelect(filtered[row])
  }

  @objc private func cancel() {
    onCancel()
  }

  private func selectFirst() {
    guard !filtered.isEmpty else {
      tableView.deselectAll(nil)
      return
    }

    tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  }

  private func moveSelection(by offset: Int) {
    guard !filtered.isEmpty else {
      return
    }

    let current = max(0, tableView.selectedRow)
    let next = min(max(0, current + offset), filtered.count - 1)
    tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
    tableView.scrollRowToVisible(next)
  }
}
