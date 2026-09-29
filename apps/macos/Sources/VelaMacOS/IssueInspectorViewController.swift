import AppKit

final class IssueInspectorViewController: NSViewController {
  private let serviceURL: String
  private let accountID: String?
  private let issueID: String
  private let preview: MyWorkIssue?
  private let onBack: () -> Void
  private let onIssueChanged: (IssueDetails) -> Void

  private let idLabel = NSTextField(labelWithString: "")
  private let projectLabel = NSTextField(labelWithString: "")
  private let summaryField = NSTextField()
  private let descriptionTextView = NSTextView()
  private let descriptionSaveButton = NSButton(title: "Save description", target: nil, action: nil)
  private let fieldsStack = NSStackView()
  private let linksStack = NSStackView()
  private let errorLabel = NSTextField(wrappingLabelWithString: "")
  private let progress = NSProgressIndicator()

  private var details: IssueDetails?
  private var schema: ProjectSchema?
  private var links: [IssueLink] = []
  private var enrichedFields: [CustomFieldValue]?
  private var loaded = false
  private var enrichmentLoaded = false
  private var saving = false

  init(
    serviceURL: String,
    accountID: String?,
    issueID: String,
    preview: MyWorkIssue? = nil,
    onBack: @escaping () -> Void,
    onIssueChanged: @escaping (IssueDetails) -> Void
  ) {
    self.serviceURL = serviceURL
    self.accountID = accountID
    self.issueID = issueID
    self.preview = preview
    self.onBack = onBack
    self.onIssueChanged = onIssueChanged
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

    let backButton = ClosureButton(title: "‹ My Work") { [weak self] in
      self?.onBack()
    }
    backButton.bezelStyle = .rounded

    idLabel.textColor = .secondaryLabelColor
    idLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)

    let toolbar = NSStackView(views: [backButton, idLabel])
    toolbar.orientation = .horizontal
    toolbar.alignment = .centerY
    toolbar.spacing = 12

    projectLabel.textColor = .secondaryLabelColor
    projectLabel.font = .systemFont(ofSize: 13)

    summaryField.font = .systemFont(ofSize: 22, weight: .semibold)
    summaryField.setAccessibilityLabel("Issue summary")

    let summarySaveButton = ClosureButton(title: "Save summary") { [weak self] in
      self?.saveSummary()
    }

    descriptionTextView.isRichText = false
    descriptionTextView.isAutomaticQuoteSubstitutionEnabled = false
    descriptionTextView.isAutomaticDashSubstitutionEnabled = false
    descriptionTextView.font = .systemFont(ofSize: 14)
    descriptionTextView.setAccessibilityLabel("Issue description")

    let descriptionScroll = NSScrollView()
    descriptionScroll.borderType = .bezelBorder
    descriptionScroll.hasVerticalScroller = true
    descriptionScroll.documentView = descriptionTextView
    descriptionScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true

    descriptionSaveButton.target = self
    descriptionSaveButton.action = #selector(saveDescription)
    descriptionSaveButton.bezelStyle = .rounded

    configureSectionStack(fieldsStack)
    configureSectionStack(linksStack)

    errorLabel.textColor = .systemRed
    errorLabel.maximumNumberOfLines = 3
    errorLabel.isHidden = true

    progress.style = .spinning
    progress.controlSize = .small
    progress.isDisplayedWhenStopped = false

    let content = NSStackView()
    content.orientation = .vertical
    content.alignment = .leading
    content.spacing = 10
    content.translatesAutoresizingMaskIntoConstraints = false

    content.addArrangedSubview(projectLabel)
    content.addArrangedSubview(sectionLabel("Summary"))
    content.addArrangedSubview(summaryField)
    content.addArrangedSubview(summarySaveButton)
    content.addArrangedSubview(sectionLabel("Description"))
    content.addArrangedSubview(descriptionScroll)
    content.addArrangedSubview(descriptionSaveButton)
    content.addArrangedSubview(errorLabel)
    content.addArrangedSubview(sectionTitle("Fields"))
    content.addArrangedSubview(fieldsStack)
    content.addArrangedSubview(sectionTitle("Links"))
    content.addArrangedSubview(linksStack)

    let document = FlippedView()
    document.translatesAutoresizingMaskIntoConstraints = false
    document.addSubview(content)

    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.documentView = document

    for subview in [toolbar, progress, scroll] {
      subview.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(subview)
    }

    NSLayoutConstraint.activate([
      toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
      toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),

      progress.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
      progress.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),

      scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 12),
      scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),

      document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
      content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 32),
      content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -32),
      content.topAnchor.constraint(equalTo: document.topAnchor, constant: 12),
      content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -36),

      summaryField.widthAnchor.constraint(equalTo: content.widthAnchor),
      descriptionScroll.widthAnchor.constraint(equalTo: content.widthAnchor),
      fieldsStack.widthAnchor.constraint(equalTo: content.widthAnchor),
      linksStack.widthAnchor.constraint(equalTo: content.widthAnchor),
      errorLabel.widthAnchor.constraint(equalTo: content.widthAnchor),
    ])

    view = root

    if let preview {
      idLabel.stringValue = preview.idReadable
      summaryField.stringValue = preview.summary
      projectLabel.stringValue = "Loading…"
      descriptionTextView.string = ""
      renderFields()
      renderLinks()
    }
  }

  override func viewDidAppear() {
    super.viewDidAppear()

    guard !loaded else {
      return
    }

    loaded = true
    loadIssue()
  }

  private func loadIssue() {
    setBusy(true)
    errorLabel.isHidden = true
    enrichmentLoaded = false

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        return
      }

      do {
        let bearerToken = try self.bearerToken()
        let issue = try RustBridge.loadIssueDetails(
          serviceURL: self.serviceURL,
          bearerToken: bearerToken,
          issueID: self.issueID
        )
        DispatchQueue.main.async {
          self.details = issue
          self.schema = nil
          self.links = []
          self.enrichedFields = nil
          self.render()
          self.setBusy(false)
        }

        let enrichment = try RustBridge.loadIssueEnrichment(
          serviceURL: self.serviceURL,
          bearerToken: bearerToken,
          issueID: self.issueID,
          projectID: issue.project.id
        )

        DispatchQueue.main.async {
          self.schema = enrichment.schema
          self.links = enrichment.links
          self.enrichedFields = enrichment.customFields
          self.enrichmentLoaded = true
          self.renderFields()
          self.renderLinks()
        }
      } catch {
        DispatchQueue.main.async {
          self.show(error: error)
          self.setBusy(false)
        }
      }
    }
  }

  private func bearerToken() throws -> String {
    guard let accountID else {
      return ""
    }

    return try SecureAccountStore.bearerToken(for: accountID)
  }

  private func render() {
    guard let details else {
      return
    }

    idLabel.stringValue = details.idReadable
    projectLabel.stringValue = "\(details.project.name) · \(details.project.shortName)"
    summaryField.stringValue = details.summary
    descriptionTextView.string = details.description ?? ""

    renderFields()
    renderLinks()
  }

  private func renderFields() {
    removeArrangedSubviews(from: fieldsStack)

    guard let details else {
      return
    }

    let fields = enrichedFields ?? details.customFields
    let sorted = fields.sorted {
      semanticRank($0) < semanticRank($1)
    }

    if sorted.isEmpty {
      let empty = NSTextField(labelWithString: "No custom fields.")
      empty.textColor = .secondaryLabelColor
      fieldsStack.addArrangedSubview(empty)
      return
    }

    for field in sorted {
      let row = makeFieldRow(field)
      fieldsStack.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: fieldsStack.widthAnchor).isActive = true
    }
  }

  private func renderLinks() {
    removeArrangedSubviews(from: linksStack)

    if !enrichmentLoaded {
      let loading = NSTextField(labelWithString: "Loading…")
      loading.textColor = .secondaryLabelColor
      linksStack.addArrangedSubview(loading)
      return
    }

    let rows = links.flatMap { link in
      link.issues.map { (link, $0) }
    }

    if rows.isEmpty {
      let empty = NSTextField(labelWithString: "No issue links.")
      empty.textColor = .secondaryLabelColor
      linksStack.addArrangedSubview(empty)
      return
    }

    for (link, issue) in rows {
      let relationship = NSTextField(labelWithString: linkLabel(link))
      relationship.textColor = .secondaryLabelColor
      relationship.font = .systemFont(ofSize: 12)
      relationship.widthAnchor.constraint(equalToConstant: 110).isActive = true

      let id = NSTextField(labelWithString: issue.idReadable)
      id.textColor = .secondaryLabelColor
      id.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
      id.widthAnchor.constraint(equalToConstant: 90).isActive = true

      let summary = NSTextField(labelWithString: issue.summary)
      summary.lineBreakMode = .byTruncatingTail

      let row = NSStackView(views: [relationship, id, summary])
      row.orientation = .horizontal
      row.alignment = .centerY
      row.spacing = 8
      linksStack.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: linksStack.widthAnchor).isActive = true
    }
  }

  private func makeFieldRow(_ field: CustomFieldValue) -> NSView {
    let label = NSTextField(labelWithString: field.name)
    label.font = .systemFont(ofSize: 14, weight: .medium)

    let type = NSTextField(labelWithString: field.fieldType)
    type.textColor = .tertiaryLabelColor
    type.font = .systemFont(ofSize: 10)

    let labelStack = NSStackView(views: [label, type])
    labelStack.orientation = .vertical
    labelStack.alignment = .leading
    labelStack.spacing = 2
    labelStack.widthAnchor.constraint(equalToConstant: 190).isActive = true

    let editor = makeEditor(field)
    let row = NSStackView(views: [labelStack, editor])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 16
    row.edgeInsets = NSEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)

    editor.setContentHuggingPriority(.defaultLow, for: .horizontal)

    return row
  }

  private func makeEditor(_ field: CustomFieldValue) -> NSView {
    let projectField = projectField(for: field)

    if !field.possibleEvents.isEmpty {
      let popup = ClosurePopUpButton()
      let items: [(String, (() -> Void)?)] =
        [("Current: \(displayValue(field.value))", nil)]
        + field.possibleEvents.map { event in
          (
            event.presentation,
            { [weak self] in
              self?.applyEvent(field: field, eventID: event.id)
            }
          )
        }
      popup.configure(items: items, selectedIndex: 0)
      return popup
    }

    if let bundle = projectField?.bundle, !bundle.values.isEmpty {
      let available = bundle.values.filter { $0.archived != true }

      if projectField?.field.fieldType.isMultiValue == true {
        let selected = selectedIDs(field.value)
        let popup = ClosurePopUpButton()
        popup.configure(
          items: available.map { value in
            let checked = selected.contains(value.id) ? "✓ " : ""
            return (
              checked + value.displayName,
              { [weak self] in
                var next = selected
                if next.contains(value.id) {
                  next.remove(value.id)
                } else {
                  next.insert(value.id)
                }
                self?.updateField(
                  field,
                  value: .array(next.map { .object(["id": .string($0)]) })
                )
              }
            )
          },
          selectedIndex: 0
        )
        return popup
      }

      let popup = ClosurePopUpButton()
      var items: [(String, (() -> Void)?)] = []

      if projectField?.canBeEmpty == true {
        items.append(
          (
            "None",
            { [weak self] in
              self?.updateField(field, value: .null)
            }
          )
        )
      }

      items.append(
        contentsOf: available.map { value in
          (
            value.displayName,
            { [weak self] in
              self?.updateField(
                field,
                value: .object(["id": .string(value.id)])
              )
            }
          )
        }
      )

      let current = displayValue(field.value)
      let selectedIndex = max(0, items.firstIndex { $0.0 == current } ?? 0)
      popup.configure(items: items, selectedIndex: selectedIndex)
      return popup
    }

    if case .bool(let value) = field.value {
      let toggle = ClosureSwitch(value: value) { [weak self] next in
        self?.updateField(field, value: .bool(next))
      }
      toggle.setAccessibilityLabel(field.name)
      return toggle
    }

    if isDateField(field, projectField: projectField) {
      let picker = NSDatePicker()
      picker.datePickerElements = [.yearMonthDay]
      picker.datePickerStyle = .textFieldAndStepper
      picker.setAccessibilityLabel("\(field.name) date")

      if let timestamp = timestamp(field.value) {
        picker.dateValue = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
      }

      let save = ClosureButton(title: "Save") { [weak self, weak picker] in
        guard let self, let picker else {
          return
        }
        let milliseconds = Int64((picker.dateValue.timeIntervalSince1970 * 1000).rounded())
        self.updateField(field, value: .integer(milliseconds))
      }

      let row = NSStackView(views: [picker, save])
      row.orientation = .horizontal
      row.spacing = 8
      return row
    }

    if isTextEditable(field.value) {
      let input = NSTextField(string: editableText(field.value))
      input.setAccessibilityLabel(field.name)

      let save = ClosureButton(title: "Save") { [weak self, weak input] in
        guard let self, let input else {
          return
        }
        self.updateField(
          field,
          value: valueFromText(field.value, text: input.stringValue)
        )
      }

      let row = NSStackView(views: [input, save])
      row.orientation = .horizontal
      row.spacing = 8
      input.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
      return row
    }

    let value = NSTextField(labelWithString: displayValue(field.value))
    value.lineBreakMode = .byTruncatingTail
    value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return value
  }

  private func saveSummary() {
    guard let details, !saving else {
      return
    }

    let summary = summaryField.stringValue
    guard summary != details.summary else {
      return
    }

    mutate {
      let bearerToken = try self.bearerToken()
      return try RustBridge.setIssueSummary(
        serviceURL: self.serviceURL,
        bearerToken: bearerToken,
        issueID: details.id,
        summary: summary
      )
    } apply: { [weak self] updated in
      self?.replaceDetails(updated)
    }
  }

  @objc private func saveDescription() {
    guard let details, !saving else {
      return
    }

    let description = descriptionTextView.string
    guard description != (details.description ?? "") else {
      return
    }

    mutate {
      let bearerToken = try self.bearerToken()
      return try RustBridge.setIssueDescription(
        serviceURL: self.serviceURL,
        bearerToken: bearerToken,
        issueID: details.id,
        description: description.isEmpty ? nil : description
      )
    } apply: { [weak self] updated in
      self?.replaceDetails(updated)
    }
  }

  private func updateField(_ field: CustomFieldValue, value: JSONValue) {
    guard let details, !saving else {
      return
    }

    mutate {
      let bearerToken = try self.bearerToken()
      return try RustBridge.setCustomFieldValue(
        serviceURL: self.serviceURL,
        bearerToken: bearerToken,
        issueID: details.id,
        fieldID: field.id,
        fieldType: field.fieldType,
        value: value
      )
    } apply: { [weak self] updated in
      self?.replaceField(updated)
    }
  }

  private func applyEvent(field: CustomFieldValue, eventID: String) {
    guard let details, !saving else {
      return
    }

    mutate {
      let bearerToken = try self.bearerToken()
      return try RustBridge.applyCustomFieldEvent(
        serviceURL: self.serviceURL,
        bearerToken: bearerToken,
        issueID: details.id,
        fieldID: field.id,
        fieldType: field.fieldType,
        eventID: eventID
      )
    } apply: { [weak self] updated in
      self?.replaceField(updated)
    }
  }

  private func mutate<Value>(
    operation: @escaping () throws -> Value,
    apply: @escaping (Value) -> Void
  ) {
    saving = true
    setControlsEnabled(false)
    errorLabel.isHidden = true
    progress.startAnimation(nil)

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        let value = try operation()
        DispatchQueue.main.async {
          guard let self else {
            return
          }
          apply(value)
          self.saving = false
          self.setControlsEnabled(true)
          self.progress.stopAnimation(nil)
        }
      } catch {
        DispatchQueue.main.async {
          guard let self else {
            return
          }
          self.show(error: error)
          self.saving = false
          self.setControlsEnabled(true)
          self.progress.stopAnimation(nil)
        }
      }
    }
  }

  private func replaceDetails(_ updated: IssueDetails) {
    details = updated
    enrichedFields = nil
    render()
    onIssueChanged(updated)
  }

  private func replaceField(_ updated: CustomFieldValue) {
    guard let details else {
      return
    }

    let fields = details.customFields.map {
      $0.id == updated.id ? updated : $0
    }

    let next = IssueDetails(
      id: details.id,
      idReadable: details.idReadable,
      summary: details.summary,
      description: details.description,
      createdAt: details.createdAt,
      updatedAt: details.updatedAt,
      resolvedAt: details.resolvedAt,
      project: details.project,
      customFields: fields
    )

    self.details = next
    if var enrichedFields,
      let index = enrichedFields.firstIndex(where: { $0.id == updated.id })
    {
      enrichedFields[index] = updated
      self.enrichedFields = enrichedFields
    }
    renderFields()
    onIssueChanged(next)
  }

  private func setBusy(_ busy: Bool) {
    setControlsEnabled(!busy)

    if busy {
      progress.startAnimation(nil)
    } else {
      progress.stopAnimation(nil)
    }
  }

  private func setControlsEnabled(_ enabled: Bool) {
    summaryField.isEnabled = enabled
    descriptionTextView.isEditable = enabled
    descriptionSaveButton.isEnabled = enabled
  }

  private func show(error: Error) {
    errorLabel.stringValue = error.localizedDescription
    errorLabel.isHidden = false
  }

  private func projectField(for field: CustomFieldValue) -> ProjectCustomField? {
    guard let schema else {
      return nil
    }

    return schema.customFields.first { $0.id == field.id }
      ?? schema.customFields.first { $0.field.name == field.name }
  }

  private func semanticRank(_ field: CustomFieldValue) -> Int {
    let projectField = projectField(for: field)
    let valueType = projectField?.field.fieldType.valueType.lowercased() ?? ""
    let name = field.name.lowercased()
    let aliases = projectField?.field.aliases?.lowercased() ?? ""

    if valueType.contains("state") || field.fieldType.lowercased().contains("state") {
      return 0
    }
    if name == "priority" || aliases.contains("priority") {
      return 1
    }
    if isDateField(field, projectField: projectField) {
      return 2
    }
    return 3
  }

  private func isDateField(
    _ field: CustomFieldValue,
    projectField: ProjectCustomField?
  ) -> Bool {
    let valueType = projectField?.field.fieldType.valueType.lowercased() ?? ""
    return field.fieldType.lowercased().contains("dateissuecustomfield")
      || valueType == "date"
  }

  private func configureSectionStack(_ stack: NSStackView) {
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 0
  }

  private func sectionLabel(_ title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title.uppercased())
    label.textColor = .secondaryLabelColor
    label.font = .systemFont(ofSize: 11, weight: .semibold)
    return label
  }

  private func sectionTitle(_ title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 18, weight: .semibold)
    label.addConstraint(label.heightAnchor.constraint(greaterThanOrEqualToConstant: 28))
    return label
  }

  private func removeArrangedSubviews(from stack: NSStackView) {
    for view in stack.arrangedSubviews {
      stack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
  }
}

private final class FlippedView: NSView {
  override var isFlipped: Bool {
    true
  }
}

private final class ClosureButton: NSButton {
  private let handler: () -> Void

  init(title: String, handler: @escaping () -> Void) {
    self.handler = handler
    super.init(frame: .zero)
    self.title = title
    bezelStyle = .rounded
    target = self
    action = #selector(invoke)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func invoke() {
    handler()
  }
}

private final class ClosurePopUpButton: NSPopUpButton {
  private var handlers: [(() -> Void)?] = []

  init() {
    super.init(frame: .zero, pullsDown: false)
    target = self
    action = #selector(invoke)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(
    items: [(String, (() -> Void)?)],
    selectedIndex: Int
  ) {
    removeAllItems()
    handlers = items.map { $0.1 }

    for (title, handler) in items {
      addItem(withTitle: title)
      if handler == nil {
        lastItem?.isEnabled = false
      }
    }

    if !items.isEmpty {
      selectItem(at: min(max(0, selectedIndex), items.count - 1))
    }
  }

  @objc private func invoke() {
    let index = indexOfSelectedItem
    guard handlers.indices.contains(index) else {
      return
    }
    handlers[index]?()
  }
}

private final class ClosureSwitch: NSSwitch {
  private let handler: (Bool) -> Void

  init(value: Bool, handler: @escaping (Bool) -> Void) {
    self.handler = handler
    super.init(frame: .zero)
    state = value ? .on : .off
    target = self
    action = #selector(invoke)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func invoke() {
    handler(state == .on)
  }
}

private func displayValue(_ value: JSONValue) -> String {
  switch value {
  case .null:
    return "None"
  case .bool(let value):
    return value ? "Yes" : "No"
  case .integer(let value):
    if value > 100_000_000_000 {
      return dateString(value)
    }
    return String(value)
  case .number(let value):
    return String(value)
  case .string(let value):
    return value
  case .array(let values):
    let display = values.map(displayValue).joined(separator: ", ")
    return display.isEmpty ? "None" : display
  case .object(let object):
    for key in ["presentation", "name", "localizedName", "fullName", "login", "text"] {
      if case .string(let value)? = object[key], !value.isEmpty {
        return value
      }
    }

    if let data = try? JSONEncoder().encode(value),
      let string = String(data: data, encoding: .utf8)
    {
      return string
    }

    return "Value"
  }
}

private func editableText(_ value: JSONValue) -> String {
  switch value {
  case .null:
    return ""
  case .integer(let value):
    return String(value)
  case .number(let value):
    return String(value)
  case .string(let value):
    return value
  case .object(let object):
    if case .string(let text)? = object["text"] {
      return text
    }
    return displayValue(value)
  default:
    return displayValue(value)
  }
}

private func valueFromText(_ current: JSONValue, text: String) -> JSONValue {
  switch current {
  case .integer:
    return Int64(text).map(JSONValue.integer) ?? current
  case .number:
    return Double(text).map(JSONValue.number) ?? current
  case .object(var object):
    if object["text"] != nil {
      object["text"] = .string(text)
      return .object(object)
    }
    return .string(text)
  default:
    return .string(text)
  }
}

private func isTextEditable(_ value: JSONValue) -> Bool {
  switch value {
  case .null, .integer, .number, .string:
    return true
  case .object(let object):
    if case .string? = object["text"] {
      return true
    }
    return false
  default:
    return false
  }
}

private func timestamp(_ value: JSONValue) -> Int64? {
  switch value {
  case .integer(let value):
    return value
  case .number(let value):
    return Int64(value)
  default:
    return nil
  }
}

private func selectedIDs(_ value: JSONValue) -> Set<String> {
  guard case .array(let values) = value else {
    return []
  }

  return Set(
    values.compactMap { value in
      guard case .object(let object) = value,
        case .string(let id)? = object["id"]
      else {
        return nil
      }
      return id
    }
  )
}

private func dateString(_ milliseconds: Int64) -> String {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withFullDate]
  return formatter.string(
    from: Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
  )
}

private func linkLabel(_ link: IssueLink) -> String {
  if !link.linkType.directed {
    return link.linkType.sourceToTarget
  }

  if link.direction == "OUTWARD" {
    return link.linkType.sourceToTarget
  }

  return link.linkType.targetToSource ?? link.linkType.sourceToTarget
}
