import AppKit
import EventKit

private enum PlanningMode: Int {
  case timeline, calendar, agenda
}

private enum PlanningZoom: Int, CaseIterable {
  case hour, day, week, month, quarter

  var label: String {
    switch self {
    case .hour: "Hour"
    case .day: "Day"
    case .week: "Week"
    case .month: "Month"
    case .quarter: "Quarter"
    }
  }

  func advanced(_ date: Date, by steps: Int) -> Date {
    let calendar = Calendar.current
    if self == .quarter {
      return calendar.date(byAdding: .month, value: steps * 3, to: date) ?? date
    }
    let component: Calendar.Component
    switch self {
    case .hour: component = .hour
    case .day: component = .day
    case .week: component = .weekOfYear
    case .month: component = .month
    case .quarter: component = .month
    }
    return calendar.date(byAdding: component, value: steps, to: date) ?? date
  }
}

/// DateIssueCustomField values represent calendar dates at 12:00 UTC.
/// Convert to the local calendar for drawing, but keep UTC midday on writes.
private enum PlanningDate {
  static var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  static func display(_ timestamp: Int64) -> Date {
    let stored = Date(timeIntervalSince1970: Double(timestamp) / 1000)
    let components = utc.dateComponents([.year, .month, .day], from: stored)
    return Calendar.current.date(from: components) ?? stored
  }

  static func shifted(_ timestamp: Int64, days: Int) -> Int64 {
    let stored = Date(timeIntervalSince1970: Double(timestamp) / 1000)
    let components = utc.dateComponents([.year, .month, .day], from: stored)
    guard
      let noon = utc.date(
        from: DateComponents(
          year: components.year, month: components.month, day: components.day, hour: 12
        )), let shifted = utc.date(byAdding: .day, value: days, to: noon)
    else {
      return timestamp
    }
    return Int64((shifted.timeIntervalSince1970 * 1000).rounded())
  }
}

private struct CalendarOverlay {
  let title: String
  let start: Date
  let end: Date
  let isAllDay: Bool
}

private final class PlanningRootView: NSView {
  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    dirtyRect.fill()
  }
}

private final class PlanningAgendaTableView: NSTableView {
  var onOpen: (() -> Void)?

  override func keyDown(with event: NSEvent) {
    let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
    guard modifiers.isEmpty else {
      super.keyDown(with: event)
      return
    }
    let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
    if key == "\r" || key == "\n" {
      onOpen?()
      return
    }
    let delta: Int
    switch key {
    case "j": delta = 1
    case "k": delta = -1
    case "d":
      delta = max(1, Int((enclosingScrollView?.contentSize.height ?? 400) / (rowHeight * 2)))
    case "u":
      delta = -max(1, Int((enclosingScrollView?.contentSize.height ?? 400) / (rowHeight * 2)))
    default:
      super.keyDown(with: event)
      return
    }
    guard numberOfRows > 0 else { return }
    let row = max(0, min(numberOfRows - 1, max(0, selectedRow) + delta))
    selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    scrollRowToVisible(row)
  }
}

/// A native AppKit planning surface; calendar entries are strictly read-only.
final class PlanningViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  private let serviceURL: String
  private let accountID: String?
  private let onBack: () -> Void
  private let onOpenIssue: (String) -> Void
  private let onIssueChanged: (IssueDetails) -> Void

  private let titleLabel = NSTextField(labelWithString: "Planning")
  private let statusLabel = NSTextField(wrappingLabelWithString: "")
  private let modeControl = NSSegmentedControl(
    labels: ["Timeline", "Calendar", "Agenda"], trackingMode: .selectOne, target: nil, action: nil)
  private let zoomMenu = NSPopUpButton()
  private let previousButton = NSButton(title: "‹", target: nil, action: nil)
  private let todayButton = NSButton(title: "Today", target: nil, action: nil)
  private let nextButton = NSButton(title: "›", target: nil, action: nil)
  private let calendarButton = NSButton(
    checkboxWithTitle: "Show calendars", target: nil, action: nil)
  private let scrollView = NSScrollView()
  private let board = PlanningBoardView()
  private let agendaScroll = NSScrollView()
  private let agendaTable = PlanningAgendaTableView()
  private let eventStore = EKEventStore()

  private var issues: [PlannedIssue] = []
  private struct AgendaEntry {
    let when: Date?
    let issue: PlannedIssue?
    let event: CalendarOverlay?
  }
  private var agendaEntries: [AgendaEntry] = []
  private var overlays: [CalendarOverlay] = []
  private var anchor = Date()
  private var mode = PlanningMode.timeline
  private var zoom = PlanningZoom.week
  private var fetchID = UUID()
  private var changingIssue = false
  private var calendarEnabled = false
  private var calendarFetchID = UUID()

  init(
    serviceURL: String,
    accountID: String?,
    onBack: @escaping () -> Void,
    onOpenIssue: @escaping (String) -> Void,
    onIssueChanged: @escaping (IssueDetails) -> Void
  ) {
    self.serviceURL = serviceURL
    self.accountID = accountID
    self.onBack = onBack
    self.onOpenIssue = onOpenIssue
    self.onIssueChanged = onIssueChanged
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

  override func loadView() {
    let root = PlanningRootView()
    titleLabel.font = .systemFont(ofSize: 27, weight: .semibold)
    let back = NSButton(title: "My Work", target: self, action: #selector(close))
    back.bezelStyle = .rounded
    back.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
    back.imagePosition = .imageLeading

    modeControl.selectedSegment = 0
    modeControl.target = self
    modeControl.action = #selector(selectPlanningMode)
    modeControl.setAccessibilityLabel("Planning view")

    zoomMenu.addItems(withTitles: PlanningZoom.allCases.map(\.label))
    zoomMenu.selectItem(at: zoom.rawValue)
    zoomMenu.target = self
    zoomMenu.action = #selector(changeZoom)
    zoomMenu.setAccessibilityLabel("Planning zoom")

    previousButton.target = self
    previousButton.action = #selector(previousPeriod)
    todayButton.target = self
    todayButton.action = #selector(goToToday)
    nextButton.target = self
    nextButton.action = #selector(nextPeriod)
    for button in [previousButton, todayButton, nextButton] { button.bezelStyle = .rounded }
    previousButton.setAccessibilityLabel("Previous period")
    nextButton.setAccessibilityLabel("Next period")
    calendarButton.target = self
    calendarButton.action = #selector(toggleCalendars)
    calendarButton.setAccessibilityLabel("Show external calendar events")

    let top = NSStackView(views: [back, titleLabel, NSView(), modeControl])
    top.orientation = .horizontal
    top.alignment = .centerY
    top.spacing = 14

    let controls = NSStackView(views: [
      zoomMenu, previousButton, todayButton, nextButton, NSView(), calendarButton,
    ])
    controls.orientation = .horizontal
    controls.alignment = .centerY
    controls.spacing = 8

    statusLabel.textColor = .secondaryLabelColor
    statusLabel.font = .systemFont(ofSize: 12)
    statusLabel.stringValue = "Loading YouTrack planning data…"

    board.onOpenIssue = { [weak self] issueID in self?.onOpenIssue(issueID) }
    board.onEdit = { [weak self] issue, operation, steps in
      self?.changeDate(issue: issue, operation: operation, steps: steps)
    }
    scrollView.documentView = board
    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = true
    scrollView.backgroundColor = .windowBackgroundColor

    let whenColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("when"))
    whenColumn.title = "When"
    whenColumn.width = 150
    whenColumn.minWidth = 100
    whenColumn.maxWidth = 185
    agendaTable.addTableColumn(whenColumn)
    let taskColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("task"))
    taskColumn.title = "Task or event"
    taskColumn.resizingMask = .autoresizingMask
    agendaTable.addTableColumn(taskColumn)
    agendaTable.rowHeight = 35
    agendaTable.usesAlternatingRowBackgroundColors = true
    agendaTable.delegate = self
    agendaTable.dataSource = self
    agendaTable.target = self
    agendaTable.doubleAction = #selector(openAgendaSelection)
    agendaTable.onOpen = { [weak self] in self?.openAgendaSelection() }
    agendaScroll.documentView = agendaTable
    agendaScroll.hasVerticalScroller = true
    agendaScroll.drawsBackground = true
    agendaScroll.backgroundColor = .windowBackgroundColor
    agendaTable.backgroundColor = .windowBackgroundColor
    agendaScroll.isHidden = true

    for subview in [top, controls, statusLabel, scrollView, agendaScroll] {
      subview.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(subview)
    }
    NSLayoutConstraint.activate([
      top.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
      top.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
      top.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
      controls.leadingAnchor.constraint(equalTo: top.leadingAnchor),
      controls.trailingAnchor.constraint(equalTo: top.trailingAnchor),
      controls.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 14),
      statusLabel.leadingAnchor.constraint(equalTo: top.leadingAnchor),
      statusLabel.trailingAnchor.constraint(equalTo: top.trailingAnchor),
      statusLabel.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 10),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
      scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
      agendaScroll.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
      agendaScroll.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
      agendaScroll.topAnchor.constraint(equalTo: scrollView.topAnchor),
      agendaScroll.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
    ])
    view = root
    render()
    reload()
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    render()
  }

  private func reload() {
    let generation = UUID()
    fetchID = generation
    statusLabel.stringValue = "Loading YouTrack planning data…"
    let serviceURL = self.serviceURL
    let accountID = self.accountID
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        let token = try accountID.map { try SecureAccountStore.bearerToken(for: $0) } ?? ""
        let snapshot = try RustBridge.loadPlanning(serviceURL: serviceURL, bearerToken: token)
        DispatchQueue.main.async {
          guard let self, self.fetchID == generation else { return }
          self.issues = snapshot.issues
          self.refreshAgenda()
          let unscheduled = snapshot.issues.filter { $0.startAt == nil && $0.dueAt == nil }.count
          self.statusLabel.stringValue =
            "\(snapshot.issues.count) tasks · \(unscheduled) unscheduled · YouTrack owns task dates"
          self.render()
        }
      } catch {
        DispatchQueue.main.async {
          guard let self, self.fetchID == generation else { return }
          self.statusLabel.stringValue = error.localizedDescription
        }
      }
    }
  }

  private func render() {
    guard isViewLoaded else { return }
    board.configure(issues: issues, overlays: overlays, anchor: anchor, zoom: zoom, mode: mode)
    let size = board.requiredSize(viewportWidth: max(720, scrollView.contentSize.width))
    if board.frame.size != size { board.setFrameSize(size) }
    board.needsDisplay = true
  }

  @objc private func close() { onBack() }
  @objc private func selectPlanningMode() {
    mode = PlanningMode(rawValue: modeControl.selectedSegment) ?? .timeline
    scrollView.isHidden = mode == .agenda
    agendaScroll.isHidden = mode != .agenda
    for control in [zoomMenu, previousButton, todayButton, nextButton] {
      control.isHidden = mode == .agenda
    }
    if mode == .agenda { view.window?.makeFirstResponder(agendaTable) }
    render()
  }
  @objc private func changeZoom() {
    zoom = PlanningZoom(rawValue: zoomMenu.indexOfSelectedItem) ?? .week
    render()
    loadCalendarEvents()
  }
  @objc private func previousPeriod() {
    anchor = shiftedAnchor(by: -1)
    render()
    loadCalendarEvents()
  }
  @objc private func nextPeriod() {
    anchor = shiftedAnchor(by: 1)
    render()
    loadCalendarEvents()
  }
  private func shiftedAnchor(by steps: Int) -> Date {
    if mode == .calendar && zoom == .hour {
      return Calendar.current.date(byAdding: .day, value: steps, to: anchor) ?? anchor
    }
    return zoom.advanced(anchor, by: steps)
  }

  @objc private func goToToday() {
    anchor = Date()
    render()
    loadCalendarEvents()
  }

  @objc private func toggleCalendars() {
    guard calendarButton.state == .on else {
      calendarEnabled = false
      calendarFetchID = UUID()
      overlays = []
      refreshAgenda()
      render()
      return
    }
    if #available(macOS 14.0, *) {
      eventStore.requestFullAccessToEvents { [weak self] permitted, error in
        DispatchQueue.main.async {
          guard let self else { return }
          self.calendarEnabled = permitted
          self.calendarButton.state = permitted ? .on : .off
          if permitted {
            self.loadCalendarEvents()
          } else {
            self.statusLabel.stringValue =
              error?.localizedDescription ?? "Calendar access was not granted."
          }
        }
      }
    }
  }

  private func loadCalendarEvents() {
    guard calendarEnabled else { return }
    let generation = UUID()
    calendarFetchID = generation
    let anchor = self.anchor
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self else { return }
      let start = Calendar.current.date(byAdding: .month, value: -5, to: anchor) ?? anchor
      let end = Calendar.current.date(byAdding: .month, value: 5, to: anchor) ?? anchor
      // Calendar overlays are occupied time, not another task source.
      // Hide known YouTrack-mirrored calendars to prevent duplication.
      let calendars = self.eventStore.calendars(for: .event).filter {
        !["tasks", "youtrack"].contains($0.title.lowercased())
      }
      let entries: [CalendarOverlay]
      if calendars.isEmpty {
        entries = []
      } else {
        let predicate = self.eventStore.predicateForEvents(
          withStart: start, end: end, calendars: calendars)
        entries = self.eventStore.events(matching: predicate).prefix(1000).map { event in
          CalendarOverlay(
            title: event.title ?? "Busy", start: event.startDate, end: event.endDate,
            isAllDay: event.isAllDay)
        }
      }
      DispatchQueue.main.async {
        guard self.calendarEnabled, self.calendarFetchID == generation else { return }
        self.overlays = entries
        self.refreshAgenda()
        self.render()
      }
    }
  }

  private func refreshAgenda() {
    let issueRows = issues.map { issue in
      AgendaEntry(
        when: (issue.startAt ?? issue.dueAt).map(PlanningDate.display),
        issue: issue, event: nil
      )
    }
    let eventRows = overlays.map { AgendaEntry(when: $0.start, issue: nil, event: $0) }
    agendaEntries = (issueRows + eventRows).sorted {
      ($0.when ?? .distantFuture) < ($1.when ?? .distantFuture)
    }
    agendaTable.reloadData()
  }

  func numberOfRows(in tableView: NSTableView) -> Int { agendaEntries.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard let tableColumn else { return nil }
    let entry = agendaEntries[row]
    let identifier = NSUserInterfaceItemIdentifier("agenda_" + tableColumn.identifier.rawValue)
    let field: NSTextField
    if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
      field = reused
    } else {
      field = NSTextField(labelWithString: "")
      field.identifier = identifier
      field.lineBreakMode = .byTruncatingTail
      field.font = .systemFont(ofSize: 13)
    }
    if tableColumn.identifier.rawValue == "when" {
      if let date = entry.when {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        field.stringValue = formatter.string(from: date)
      } else {
        field.stringValue = "Unscheduled"
      }
      field.textColor = .secondaryLabelColor
    } else if let issue = entry.issue {
      field.stringValue = issue.idReadable + " · " + issue.summary
      field.textColor = .labelColor
    } else if let event = entry.event {
      field.stringValue = event.title + " · calendar (read-only)"
      field.textColor = .systemTeal
    }
    return field
  }

  @objc private func openAgendaSelection() {
    let index = agendaTable.clickedRow >= 0 ? agendaTable.clickedRow : agendaTable.selectedRow
    guard agendaEntries.indices.contains(index), let issue = agendaEntries[index].issue else {
      return
    }
    onOpenIssue(issue.id)
  }

  private func changeDate(issue: PlannedIssue, operation: PlanningEdit, steps: Int) {
    guard !changingIssue, steps != 0 else { return }
    let changes: [(PlanningField, Int64)] = {
      let start = issue.startAt.flatMap { stamp -> (PlanningField, Int64)? in
        guard let field = issue.startField else { return nil }
        return (field, moveTimestamp(stamp, by: steps))
      }
      let due = issue.dueAt.flatMap { stamp -> (PlanningField, Int64)? in
        guard let field = issue.dueField else { return nil }
        return (field, moveTimestamp(stamp, by: steps))
      }
      switch operation {
      case .move: return [start, due].compactMap { $0 }
      case .resizeStart: return start.map { [$0] } ?? []
      case .resizeDue: return due.map { [$0] } ?? []
      }
    }()
    guard !changes.isEmpty else { return }
    if operation == .resizeStart, let due = issue.dueAt, changes[0].1 > due { return }
    if operation == .resizeDue, let start = issue.startAt, changes[0].1 < start { return }

    changingIssue = true
    statusLabel.stringValue = "Updating \(issue.idReadable)…"
    let serviceURL = self.serviceURL
    let accountID = self.accountID
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        let token = try accountID.map { try SecureAccountStore.bearerToken(for: $0) } ?? ""
        for (field, timestamp) in changes {
          _ = try RustBridge.setCustomFieldValue(
            serviceURL: serviceURL, bearerToken: token, issueID: issue.id,
            fieldID: field.id, fieldType: field.fieldType, value: .integer(timestamp)
          )
        }
        let updated = try RustBridge.loadIssueDetails(
          serviceURL: serviceURL, bearerToken: token, issueID: issue.id
        )
        DispatchQueue.main.async {
          guard let self else { return }
          self.changingIssue = false
          self.onIssueChanged(updated)
          self.reload()
        }
      } catch {
        DispatchQueue.main.async {
          guard let self else { return }
          self.changingIssue = false
          // Reload after a partial multi-field update, preserving the warning.
          self.reload()
          self.statusLabel.stringValue = "Update failed: \(error.localizedDescription)"
        }
      }
    }
  }

  private func moveTimestamp(_ timestamp: Int64, by steps: Int) -> Int64 {
    PlanningDate.shifted(timestamp, days: steps)
  }
}

enum PlanningEdit { case move, resizeStart, resizeDue }

/// Only the time grid is custom-drawn. Navigation, controls and inspectors use
/// native AppKit widgets, and this view never runs a display-link animation.
private final class PlanningBoardView: NSView {
  var onOpenIssue: ((String) -> Void)?
  var onEdit: ((PlannedIssue, PlanningEdit, Int) -> Void)?
  private var issues: [PlannedIssue] = []
  private var overlays: [CalendarOverlay] = []
  private var anchor = Date()
  private var zoom = PlanningZoom.week
  private var mode = PlanningMode.timeline
  private let leftWidth: CGFloat = 240
  private let tickWidth: CGFloat = 84
  private let rowHeight: CGFloat = 36
  private let calendarCellHeight: CGFloat = 134
  private let timeHeaderHeight: CGFloat = 122
  private var hitAreas: [(NSRect, PlannedIssue, PlanningEdit?)] = []
  private var dragStart: (NSPoint, PlannedIssue, PlanningEdit?)?

  override var isFlipped: Bool { true }

  func configure(
    issues: [PlannedIssue], overlays: [CalendarOverlay], anchor: Date, zoom: PlanningZoom,
    mode: PlanningMode
  ) {
    self.issues = issues
    self.overlays = overlays
    self.anchor = anchor
    self.zoom = zoom
    self.mode = mode
    setAccessibilityLabel(
      "\(String(describing: mode).capitalized) planning view, \(issues.count) YouTrack issues")
  }

  private var orderedIssues: [PlannedIssue] {
    issues.sorted {
      let left = $0.startAt ?? $0.dueAt ?? Int64.max
      let right = $1.startAt ?? $1.dueAt ?? Int64.max
      return left == right ? $0.idReadable < $1.idReadable : left < right
    }
  }

  private var tickCount: Int { zoom == .hour ? 36 : 18 }

  private var calendarDays: Int {
    switch zoom {
    case .hour: 1
    case .day: 1
    case .week: 7
    case .month: 42
    case .quarter: 98
    }
  }

  func requiredSize(viewportWidth: CGFloat) -> NSSize {
    switch mode {
    case .timeline:
      return NSSize(
        width: max(viewportWidth, leftWidth + CGFloat(tickCount) * tickWidth),
        height: max(420, timeHeaderHeight + CGFloat(issues.count + 2) * rowHeight + 32))
    case .calendar:
      let columns = zoom == .hour || zoom == .day ? 1 : 7
      return NSSize(
        width: max(viewportWidth, CGFloat(columns) * 116),
        height: zoom == .hour
          ? 80 + 24 * 46
          : max(400, 48 + CGFloat((calendarDays + columns - 1) / columns) * calendarCellHeight))
    case .agenda:
      return NSSize(
        width: viewportWidth,
        height: max(420, 48 + CGFloat(issues.count + overlays.count) * 40 + 24))
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    NSColor.windowBackgroundColor.setFill()
    bounds.fill()
    hitAreas.removeAll(keepingCapacity: true)
    switch mode {
    case .timeline: drawTimeline()
    case .calendar: drawCalendar()
    case .agenda: break
    }
  }

  private func text(
    _ label: String, in rect: NSRect, color: NSColor = .labelColor, size: CGFloat = 12,
    bold: Bool = false
  ) {
    guard rect.maxY >= 0, rect.minY <= bounds.height else { return }
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byTruncatingTail
    (label as NSString).draw(
      in: rect,
      withAttributes: [
        .foregroundColor: color,
        .font: NSFont.systemFont(ofSize: size, weight: bold ? .medium : .regular),
        .paragraphStyle: style,
      ])
  }

  private func rule(_ rect: NSRect) {
    NSColor.separatorColor.withAlphaComponent(0.5).setFill()
    rect.fill()
  }

  private func capsule(_ rect: NSRect, color: NSColor) {
    guard rect.width > 0, rect.height > 0 else { return }
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
  }

  private func millis(_ stamp: Int64) -> Date { PlanningDate.display(stamp) }

  private func dateString(_ date: Date, format: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = format
    return formatter.string(from: date)
  }

  private func startOfTimeline() -> Date {
    let cal = Calendar.current
    let base: Date
    switch zoom {
    case .hour: base = cal.dateInterval(of: .hour, for: anchor)?.start ?? anchor
    case .day: base = cal.startOfDay(for: anchor)
    case .week: base = cal.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor
    case .month: base = cal.dateInterval(of: .month, for: anchor)?.start ?? anchor
    case .quarter:
      let monthStart = cal.dateInterval(of: .month, for: anchor)?.start ?? anchor
      let offset = (cal.component(.month, from: anchor) - 1) % 3
      base = cal.date(byAdding: .month, value: -offset, to: monthStart) ?? monthStart
    }
    return zoom.advanced(base, by: zoom == .hour ? -3 : -2)
  }

  private func timelineTicks() -> [Date] {
    let start = startOfTimeline()
    return (0...tickCount).map { zoom.advanced(start, by: $0) }
  }

  private func timelineX(_ date: Date, ticks: [Date]) -> CGFloat {
    guard let first = ticks.first, let last = ticks.last else { return leftWidth }
    if date < first {
      let duration = ticks[1].timeIntervalSince(first)
      return leftWidth + CGFloat(date.timeIntervalSince(first) / duration) * tickWidth
    }
    if date >= last {
      let duration = last.timeIntervalSince(ticks[ticks.count - 2])
      return leftWidth + CGFloat(tickCount) * tickWidth + CGFloat(
        date.timeIntervalSince(last) / duration) * tickWidth
    }
    for index in 0..<ticks.count - 1 where date >= ticks[index] && date < ticks[index + 1] {
      let fraction =
        date.timeIntervalSince(ticks[index]) / ticks[index + 1].timeIntervalSince(ticks[index])
      return leftWidth + (CGFloat(index) + CGFloat(fraction)) * tickWidth
    }
    return leftWidth
  }

  private func timelineDate(at x: CGFloat) -> Date {
    let ticks = timelineTicks()
    let index = max(0, min(tickCount - 1, Int(floor((x - leftWidth) / tickWidth))))
    let fraction = Double((x - leftWidth - CGFloat(index) * tickWidth) / tickWidth)
    return ticks[index].addingTimeInterval(
      fraction * ticks[index + 1].timeIntervalSince(ticks[index]))
  }

  private func drawTimeline() {
    let ticks = timelineTicks()
    let timelineEnd = leftWidth + CGFloat(tickCount) * tickWidth
    text(
      "TASKS", in: NSRect(x: 10, y: 10, width: leftWidth - 20, height: 22),
      color: .secondaryLabelColor, bold: true)
    for index in 0..<tickCount {
      let x = leftWidth + CGFloat(index) * tickWidth
      let format: String
      switch zoom {
      case .hour: format = "ha"
      case .day: format = "EEE d"
      case .week: format = "d MMM"
      case .month, .quarter: format = "MMM yy"
      }
      text(
        dateString(ticks[index], format: format),
        in: NSRect(x: x + 6, y: 10, width: tickWidth - 8, height: 22), color: .secondaryLabelColor)
      rule(NSRect(x: x, y: 34, width: 1, height: bounds.height - 34))
    }
    text(
      "Calendar occupancy (read-only)", in: NSRect(x: 10, y: 53, width: leftWidth - 16, height: 24),
      color: .secondaryLabelColor)
    let visibleEvents = overlays.filter { $0.end > ticks[0] && $0.start < ticks[ticks.count - 1] }
    for event in visibleEvents {
      let x1 = max(leftWidth + 2, timelineX(event.start, ticks: ticks))
      let x2 = min(timelineEnd - 2, timelineX(event.end, ticks: ticks))
      capsule(
        NSRect(x: x1, y: 39, width: max(3, x2 - x1), height: 64),
        color: NSColor.systemTeal.withAlphaComponent(0.08))
    }
    for (index, event) in visibleEvents.prefix(3).enumerated() {
      let x1 = max(leftWidth + 2, timelineX(event.start, ticks: ticks))
      let x2 = min(timelineEnd - 2, timelineX(event.end, ticks: ticks))
      let y = CGFloat(index) * 19 + 42
      capsule(
        NSRect(x: x1, y: y, width: max(7, x2 - x1), height: 16),
        color: NSColor.systemTeal.withAlphaComponent(0.30))
      text(
        event.title, in: NSRect(x: x1 + 3, y: y, width: max(0, x2 - x1 - 6), height: 15), size: 10)
    }
    if visibleEvents.count > 3 {
      text(
        "+\(visibleEvents.count - 3) calendar events",
        in: NSRect(x: 8, y: 85, width: leftWidth - 16, height: 20),
        color: .secondaryLabelColor, size: 11)
    }
    rule(NSRect(x: 0, y: timeHeaderHeight - 1, width: timelineEnd, height: 1))

    let ordered = orderedIssues
    let firstUnscheduled = ordered.firstIndex { $0.startAt == nil && $0.dueAt == nil }
    if let firstUnscheduled {
      let headingY = timeHeaderHeight + CGFloat(firstUnscheduled) * rowHeight
      NSColor.secondaryLabelColor.withAlphaComponent(0.08).setFill()
      NSRect(x: 0, y: headingY, width: timelineEnd, height: 24).fill()
      text(
        "UNSCHEDULED · \(ordered.count - firstUnscheduled) tasks",
        in: NSRect(x: 10, y: headingY + 3, width: 430, height: 18), color: .secondaryLabelColor,
        bold: true)
    }
    for (index, issue) in ordered.enumerated() {
      let y =
        timeHeaderHeight + CGFloat(index) * rowHeight
        + (firstUnscheduled.map { index >= $0 } ?? false ? 24 : 0)
      if index.isMultiple(of: 2) {
        NSColor.alternatingContentBackgroundColors[0].withAlphaComponent(0.4).setFill()
        NSRect(x: 0, y: y, width: bounds.width, height: rowHeight).fill()
      }
      text(
        issue.idReadable, in: NSRect(x: 10, y: y + 3, width: 78, height: 18),
        color: .secondaryLabelColor, size: 11)
      text(issue.summary, in: NSRect(x: 10, y: y + 18, width: leftWidth - 17, height: 17), size: 12)
      hitAreas.append((NSRect(x: 0, y: y, width: leftWidth, height: rowHeight), issue, nil))
      guard let start = issue.startAt ?? issue.dueAt else { continue }
      let end = max(start, issue.dueAt ?? start)
      let marker = issue.startAt == nil || issue.dueAt == nil
      let x1 = timelineX(millis(start), ticks: ticks)
      let endExclusive =
        Calendar.current.date(byAdding: .day, value: 1, to: millis(end)) ?? millis(end)
      let x2 = marker ? x1 + 11 : timelineX(endExclusive, ticks: ticks)
      if x2 < leftWidth || x1 > timelineEnd { continue }
      let clippedX = max(leftWidth + 2, x1)
      let clippedEnd = min(timelineEnd - 2, x2)
      let rect = NSRect(x: clippedX, y: y + 9, width: max(9, clippedEnd - clippedX), height: 20)
      capsule(rect, color: marker ? .systemOrange : .controlAccentColor)
      if !marker {
        text(issue.summary, in: rect.insetBy(dx: 7, dy: 2), color: .white, size: 11)
      }
      hitAreas.append((rect, issue, .move))
      if !marker, issue.startField != nil, issue.dueField != nil,
        x1 >= leftWidth, x2 <= timelineEnd
      {
        hitAreas.append(
          (NSRect(x: rect.minX, y: rect.minY, width: 7, height: rect.height), issue, .resizeStart))
        hitAreas.append(
          (NSRect(x: rect.maxX - 7, y: rect.minY, width: 7, height: rect.height), issue, .resizeDue)
        )
      }
    }
    let bottom =
      timeHeaderHeight + CGFloat(issues.count) * rowHeight + (firstUnscheduled == nil ? 0 : 24) + 7
    text(
      "Drag bars to move · drag edges to resize · click labels to inspect · no date fields means unscheduled",
      in: NSRect(x: 10, y: bottom, width: bounds.width - 20, height: 19),
      color: .secondaryLabelColor, size: 11)
  }

  private func drawCalendar() {
    if zoom == .hour {
      drawHourlyCalendar()
      return
    }
    let cal = Calendar.current
    let columns = zoom == .hour || zoom == .day ? 1 : 7
    let cellWidth = bounds.width / CGFloat(columns)
    let start: Date
    let monthStart = cal.dateInterval(of: .month, for: anchor)?.start ?? anchor
    if zoom == .day {
      start = cal.startOfDay(for: anchor)
    } else if zoom == .month {
      start = cal.dateInterval(of: .weekOfYear, for: monthStart)?.start ?? anchor
    } else if zoom == .quarter {
      let offset = (cal.component(.month, from: anchor) - 1) % 3
      let quarterStart = cal.date(byAdding: .month, value: -offset, to: monthStart) ?? monthStart
      start = cal.dateInterval(of: .weekOfYear, for: quarterStart)?.start ?? quarterStart
    } else {
      start = cal.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor
    }
    text(
      "Tasks and occupied time · calendar overlays are read-only",
      in: NSRect(x: 8, y: 8, width: bounds.width - 16, height: 24), color: .secondaryLabelColor)
    for dayIndex in 0..<calendarDays {
      let day = cal.date(byAdding: .day, value: dayIndex, to: start) ?? start
      let next = cal.date(byAdding: .day, value: 1, to: day) ?? day
      let rect = NSRect(
        x: CGFloat(dayIndex % columns) * cellWidth,
        y: 40 + CGFloat(dayIndex / columns) * calendarCellHeight,
        width: cellWidth, height: calendarCellHeight)
      rule(NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1))
      rule(NSRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height))
      if cal.isDateInToday(day) {
        NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
        rect.fill()
      }
      text(
        dateString(day, format: "EEE d MMM"),
        in: NSRect(x: rect.minX + 6, y: rect.minY + 6, width: rect.width - 12, height: 19),
        bold: true)
      var line = 0
      let scheduled = orderedIssues.filter { issue in
        guard let first = issue.startAt ?? issue.dueAt else { return false }
        let last = max(first, issue.dueAt ?? first)
        return millis(first) < next && millis(last) >= day
      }
      for event in overlays where event.start < next && event.end > day {
        guard line < 4 else { break }
        let lineRect = NSRect(
          x: rect.minX + 4, y: rect.minY + 30 + CGFloat(line) * 20, width: rect.width - 8,
          height: 19)
        capsule(lineRect, color: NSColor.systemTeal.withAlphaComponent(0.25))
        text(event.title, in: lineRect.insetBy(dx: 4, dy: 2), size: 10)
        line += 1
      }
      for issue in scheduled {
        guard line < 4 else { break }
        let lineRect = NSRect(
          x: rect.minX + 4, y: rect.minY + 30 + CGFloat(line) * 20, width: rect.width - 8,
          height: 19)
        capsule(lineRect, color: .controlAccentColor)
        text(
          issue.idReadable + " " + issue.summary, in: lineRect.insetBy(dx: 4, dy: 1), color: .white,
          size: 10)
        hitAreas.append((lineRect, issue, nil))
        line += 1
      }
      let overflow =
        overlays.filter { $0.start < next && $0.end > day }.count + scheduled.count - line
      if overflow > 0 {
        text(
          "+\(overflow) more",
          in: NSRect(x: rect.minX + 5, y: rect.minY + 113, width: rect.width - 10, height: 16),
          color: .secondaryLabelColor, size: 10)
      }
    }
  }

  private func drawHourlyCalendar() {
    let cal = Calendar.current
    let day = cal.startOfDay(for: anchor)
    let next = cal.date(byAdding: .day, value: 1, to: day) ?? day
    let scheduled = orderedIssues.filter { issue in
      guard let first = issue.startAt ?? issue.dueAt else { return false }
      let last = max(first, issue.dueAt ?? first)
      return millis(first) < next && millis(last) >= day
    }
    text(
      dateString(day, format: "EEEE, d MMMM yyyy"),
      in: NSRect(x: 12, y: 8, width: bounds.width - 24, height: 23), bold: true)
    for (index, issue) in scheduled.prefix(4).enumerated() {
      let rect = NSRect(x: 170 + CGFloat(index) * 175, y: 34, width: 168, height: 20)
      capsule(rect, color: .controlAccentColor)
      text(issue.summary, in: rect.insetBy(dx: 5, dy: 2), color: .white, size: 11)
      hitAreas.append((rect, issue, nil))
    }
    for hour in 0..<24 {
      let hourStart = cal.date(byAdding: .hour, value: hour, to: day) ?? day
      let following = cal.date(byAdding: .hour, value: 1, to: hourStart) ?? hourStart
      let y = 80 + CGFloat(hour) * 46
      rule(NSRect(x: 0, y: y, width: bounds.width, height: 1))
      text(
        dateString(hourStart, format: "h a"), in: NSRect(x: 14, y: y + 9, width: 120, height: 20),
        color: .secondaryLabelColor)
      let events = overlays.filter { !$0.isAllDay && $0.start < following && $0.end > hourStart }
      for (index, event) in events.prefix(4).enumerated() {
        let rect = NSRect(x: 165 + CGFloat(index) * 200, y: y + 6, width: 192, height: 32)
        capsule(rect, color: NSColor.systemTeal.withAlphaComponent(0.3))
        text(event.title, in: rect.insetBy(dx: 8, dy: 8), size: 11)
      }
    }
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    dragStart = hitAreas.reversed().first { $0.0.contains(point) }.map { (point, $0.1, $0.2) }
  }

  override func mouseUp(with event: NSEvent) {
    guard let (start, issue, operation) = dragStart else { return }
    dragStart = nil
    let end = convert(event.locationInWindow, from: nil)
    guard mode == .timeline, let operation, abs(end.x - start.x) >= 5 else {
      if abs(end.x - start.x) < 5 { onOpenIssue?(issue.id) }
      return
    }
    let from = timelineDate(at: start.x)
    let to = timelineDate(at: end.x)
    let component: Calendar.Component = .day
    let change =
      Calendar.current.dateComponents([component], from: from, to: to).value(for: component) ?? 0
    if change != 0 { onEdit?(issue, operation, change) }
  }
}
