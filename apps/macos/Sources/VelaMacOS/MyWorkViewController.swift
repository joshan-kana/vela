import AppKit

final class MyWorkViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  private let titleLabel = NSTextField(labelWithString: "My Work")
  private let serviceURLField = NSTextField()
  private let tokenField = NSSecureTextField()
  private let connectButton = NSButton(title: "Connect", target: nil, action: nil)
  private let progress = NSProgressIndicator()
  private let errorLabel = NSTextField(wrappingLabelWithString: "")
  private let accountName = NSTextField(labelWithString: "")
  private let accountDetail = NSTextField(labelWithString: "")
  private let connectionStack = NSStackView()
  private let accountStack = NSStackView()
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()

  private var issues: [MyWorkIssue] = []

  override func loadView() {
    let root = NSView()

    titleLabel.font = .systemFont(ofSize: 28, weight: .semibold)

    serviceURLField.placeholderString = "https://youtrack.example.com"
    serviceURLField.setAccessibilityLabel("YouTrack address")

    tokenField.placeholderString = "Permanent token (optional)"
    tokenField.setAccessibilityLabel("Permanent token")

    connectButton.target = self
    connectButton.action = #selector(connect)
    connectButton.keyEquivalent = "\r"

    progress.style = .spinning
    progress.controlSize = .small
    progress.isDisplayedWhenStopped = false

    errorLabel.textColor = .systemRed
    errorLabel.maximumNumberOfLines = 3
    errorLabel.isHidden = true

    connectionStack.setViews(
      [serviceURLField, tokenField, connectButton, progress, errorLabel],
      in: .top
    )
    connectionStack.orientation = .vertical
    connectionStack.alignment = .centerX
    connectionStack.spacing = 10

    serviceURLField.widthAnchor.constraint(equalToConstant: 360).isActive = true
    tokenField.widthAnchor.constraint(equalToConstant: 360).isActive = true
    connectButton.widthAnchor.constraint(equalToConstant: 120).isActive = true

    accountName.font = .systemFont(ofSize: 14, weight: .semibold)
    accountDetail.textColor = .secondaryLabelColor

    accountStack.setViews([accountName, accountDetail], in: .top)
    accountStack.orientation = .vertical
    accountStack.alignment = .leading
    accountStack.spacing = 2
    accountStack.isHidden = true

    tableView.headerView = nil
    tableView.rowHeight = 42
    tableView.intercellSpacing = NSSize(width: 0, height: 0)
    tableView.usesAlternatingRowBackgroundColors = false
    tableView.delegate = self
    tableView.dataSource = self

    let issueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("issue"))
    issueColumn.resizingMask = .autoresizingMask
    tableView.addTableColumn(issueColumn)

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.isHidden = true

    for subview in [titleLabel, connectionStack, accountStack, scrollView] {
      subview.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(subview)
    }

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
      titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),

      connectionStack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      connectionStack.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -24),

      accountStack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      accountStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 22),

      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
      scrollView.topAnchor.constraint(equalTo: accountStack.bottomAnchor, constant: 14),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
    ])

    view = root
  }

  @objc private func connect() {
    let serviceURL = serviceURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !serviceURL.isEmpty else {
      NSSound.beep()
      return
    }

    let token = tokenField.stringValue
    setConnecting(true)

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        let work = try RustBridge.loadMyWork(
          serviceURL: serviceURL,
          bearerToken: token
        )

        DispatchQueue.main.async {
          self?.show(work)
        }
      } catch {
        DispatchQueue.main.async {
          self?.show(error: error)
        }
      }
    }
  }

  private func setConnecting(_ connecting: Bool) {
    connectButton.isEnabled = !connecting
    serviceURLField.isEnabled = !connecting
    tokenField.isEnabled = !connecting
    errorLabel.isHidden = true

    if connecting {
      progress.startAnimation(nil)
    } else {
      progress.stopAnimation(nil)
    }
  }

  private func show(_ work: MyWork) {
    setConnecting(false)
    tokenField.stringValue = ""

    issues = work.issues
    accountName.stringValue = work.user.fullName
    accountDetail.stringValue =
      work.user.login + (work.user.guest ? " · Guest access" : "")

    accountStack.isHidden = false
    connectionStack.isHidden = true
    scrollView.isHidden = false
    tableView.reloadData()
  }

  private func show(error: Error) {
    setConnecting(false)
    errorLabel.stringValue = error.localizedDescription
    errorLabel.isHidden = false
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    issues.count
  }

  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  ) -> NSView? {
    let issue = issues[row]
    let identifier = NSUserInterfaceItemIdentifier("issueCell")

    let field: NSTextField
    if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
      field = reused
    } else {
      field = NSTextField(labelWithString: "")
      field.identifier = identifier
      field.lineBreakMode = .byTruncatingTail
      field.font = .systemFont(ofSize: 14)
    }

    let readable = NSAttributedString(
      string: issue.idReadable + "   ",
      attributes: [
        .foregroundColor: NSColor.secondaryLabelColor,
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
      ]
    )
    let summary = NSAttributedString(
      string: issue.summary,
      attributes: [
        .foregroundColor: NSColor.labelColor,
        .font: NSFont.systemFont(ofSize: 14),
      ]
    )

    let value = NSMutableAttributedString()
    value.append(readable)
    value.append(summary)
    field.attributedStringValue = value

    return field
  }
}
