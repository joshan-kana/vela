import AppKit

final class QuickCreateViewController: NSViewController, NSTextFieldDelegate {
  private let serviceURL: String
  private let accountID: String?
  private let onCancel: () -> Void
  private let onCreated: (IssueDetails) -> Void

  private let projectPicker = NSPopUpButton()
  private let summaryField = NSTextField()
  private let descriptionTextView = NSTextView()
  private let createButton = NSButton(title: "Create issue", target: nil, action: nil)
  private let progress = NSProgressIndicator()
  private let errorLabel = NSTextField(wrappingLabelWithString: "")

  private var projects: [ProjectReference] = []
  private var loaded = false

  init(
    serviceURL: String,
    accountID: String?,
    onCancel: @escaping () -> Void,
    onCreated: @escaping (IssueDetails) -> Void
  ) {
    self.serviceURL = serviceURL
    self.accountID = accountID
    self.onCancel = onCancel
    self.onCreated = onCreated
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    let root = NSView()

    let backButton = NSButton(title: "‹ My Work", target: self, action: #selector(cancel))
    backButton.bezelStyle = .rounded

    let title = NSTextField(labelWithString: "New issue")
    title.font = .systemFont(ofSize: 22, weight: .semibold)

    let toolbar = NSStackView(views: [backButton, title])
    toolbar.orientation = .horizontal
    toolbar.alignment = .centerY
    toolbar.spacing = 12

    projectPicker.setAccessibilityLabel("Project")
    projectPicker.isEnabled = false
    projectPicker.widthAnchor.constraint(equalToConstant: 360).isActive = true

    summaryField.placeholderString = "What needs doing?"
    summaryField.setAccessibilityLabel("New issue summary")
    summaryField.delegate = self
    summaryField.widthAnchor.constraint(equalToConstant: 520).isActive = true

    descriptionTextView.isRichText = false
    descriptionTextView.isAutomaticQuoteSubstitutionEnabled = false
    descriptionTextView.isAutomaticDashSubstitutionEnabled = false
    descriptionTextView.font = .systemFont(ofSize: 14)
    descriptionTextView.setAccessibilityLabel("New issue description")

    let descriptionScroll = NSScrollView()
    descriptionScroll.borderType = .bezelBorder
    descriptionScroll.hasVerticalScroller = true
    descriptionScroll.documentView = descriptionTextView
    descriptionScroll.widthAnchor.constraint(equalToConstant: 520).isActive = true
    descriptionScroll.heightAnchor.constraint(equalToConstant: 140).isActive = true

    createButton.target = self
    createButton.action = #selector(createIssue)
    createButton.bezelStyle = .rounded
    createButton.keyEquivalent = "\r"
    createButton.isEnabled = false

    progress.style = .spinning
    progress.controlSize = .small
    progress.isDisplayedWhenStopped = false

    errorLabel.textColor = .systemRed
    errorLabel.maximumNumberOfLines = 3
    errorLabel.isHidden = true
    errorLabel.widthAnchor.constraint(equalToConstant: 520).isActive = true

    let form = NSStackView()
    form.orientation = .vertical
    form.alignment = .leading
    form.spacing = 10
    form.addArrangedSubview(sectionLabel("Project"))
    form.addArrangedSubview(projectPicker)
    form.addArrangedSubview(sectionLabel("Summary"))
    form.addArrangedSubview(summaryField)
    form.addArrangedSubview(sectionLabel("Description"))
    form.addArrangedSubview(descriptionScroll)

    let actions = NSStackView(views: [createButton, progress])
    actions.orientation = .horizontal
    actions.alignment = .centerY
    actions.spacing = 10
    form.addArrangedSubview(actions)
    form.addArrangedSubview(errorLabel)

    for subview in [toolbar, form] {
      subview.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(subview)
    }

    NSLayoutConstraint.activate([
      toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
      toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),

      form.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
      form.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 28),
      form.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -32),
    ])

    view = root
  }

  override func viewDidAppear() {
    super.viewDidAppear()

    guard !loaded else {
      return
    }

    loaded = true
    loadProjects()
  }

  private func loadProjects() {
    setBusy(true)

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        return
      }

      do {
        let bearerToken = try self.bearerToken()
        let discovery = try RustBridge.discover(
          serviceURL: self.serviceURL,
          bearerToken: bearerToken
        )

        guard discovery.projects.capability == .available else {
          throw QuickCreateError.projectsUnavailable
        }

        let projects = discovery.projects.items
          .filter { $0.archived != true }
          .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
          }

        guard !projects.isEmpty else {
          throw QuickCreateError.noProjects
        }

        DispatchQueue.main.async {
          self.projects = projects
          self.projectPicker.removeAllItems()
          self.projectPicker.addItems(
            withTitles: projects.map { "\($0.name) · \($0.shortName)" }
          )
          self.projectPicker.isEnabled = true
          self.updateCreateButton()
          self.summaryField.becomeFirstResponder()
          self.setBusy(false)
        }
      } catch {
        DispatchQueue.main.async {
          self.show(error: error)
          self.setBusy(false)
        }
      }
    }
  }

  func controlTextDidChange(_ notification: Notification) {
    updateCreateButton()
  }

  private func updateCreateButton() {
    createButton.isEnabled =
      !projects.isEmpty
      && !summaryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  @objc private func createIssue() {
    let row = projectPicker.indexOfSelectedItem
    let summary = summaryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

    guard projects.indices.contains(row), !summary.isEmpty else {
      NSSound.beep()
      return
    }

    let project = projects[row]
    let description = descriptionTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
    setBusy(true)

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        return
      }

      do {
        let bearerToken = try self.bearerToken()
        let result = try RustBridge.executeIssueAction(
          serviceURL: self.serviceURL,
          bearerToken: bearerToken,
          action: .createIssue(
            projectID: project.id,
            summary: summary,
            description: description.isEmpty ? nil : description
          )
        )

        guard result.kind == "issue", let issue = result.issue else {
          throw QuickCreateError.unexpectedResult
        }

        DispatchQueue.main.async {
          self.setBusy(false)
          self.onCreated(issue)
        }
      } catch {
        DispatchQueue.main.async {
          self.show(error: error)
          self.setBusy(false)
        }
      }
    }
  }

  @objc private func cancel() {
    onCancel()
  }

  private func bearerToken() throws -> String {
    guard let accountID else {
      return ""
    }

    return try SecureAccountStore.bearerToken(for: accountID)
  }

  private func setBusy(_ busy: Bool) {
    projectPicker.isEnabled = !busy && !projects.isEmpty
    summaryField.isEnabled = !busy
    descriptionTextView.isEditable = !busy
    createButton.isEnabled =
      !busy
      && !projects.isEmpty
      && !summaryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    errorLabel.isHidden = true

    if busy {
      progress.startAnimation(nil)
    } else {
      progress.stopAnimation(nil)
    }
  }

  private func show(error: Error) {
    errorLabel.stringValue = error.localizedDescription
    errorLabel.isHidden = false
  }

  private func sectionLabel(_ title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.textColor = .secondaryLabelColor
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    return label
  }
}

private enum QuickCreateError: LocalizedError {
  case projectsUnavailable
  case noProjects
  case unexpectedResult

  var errorDescription: String? {
    switch self {
    case .projectsUnavailable:
      "Projects are not available for this YouTrack account."
    case .noProjects:
      "No active projects are available."
    case .unexpectedResult:
      "YouTrack did not return the created issue."
    }
  }
}
