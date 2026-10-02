import AppKit

final class MyWorkViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  private let titleLabel = NSTextField(labelWithString: "My Work")
  private let serviceURLField = NSTextField()
  private let oauthClientIDField = NSTextField()
  private let oauthHubURLField = NSTextField()
  private let oauthScopeField = NSTextField()
  private let oauthConnectButton = NSButton(title: "Connect with OAuth", target: nil, action: nil)
  private let tokenField = NSSecureTextField()
  private let connectButton = NSButton(
    title: "Connect with token or guest access",
    target: nil,
    action: nil
  )
  private let progress = NSProgressIndicator()
  private let errorLabel = NSTextField(wrappingLabelWithString: "")
  private let accountName = NSTextField(labelWithString: "")
  private let accountDetail = NSTextField(labelWithString: "")
  private let connectionStack = NSStackView()
  private let savedAccountsStack = NSStackView()
  private let accountStack = NSStackView()
  private let newIssueButton = NSButton(title: "New issue", target: nil, action: nil)
  private let disconnectButton = NSButton(title: "Disconnect", target: nil, action: nil)
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()

  private var issues: [MyWorkIssue] = []
  private var connectedServiceURL = ""
  private var connectedAccountID: String?
  private var inspector: IssueInspectorViewController?
  private var quickCreate: QuickCreateViewController?
  private var oauthLoopbackServer: OAuthLoopbackServer?
  private var prefetchedIssueDetails: [String: IssueDetails] = [:]
  private var prefetchedProjectSchemas: [String: ProjectSchema] = [:]
  private var prefetchGeneration = UUID()
  private var prefetchProtectedIssueIDs: Set<String> = []

  override func loadView() {
    let root = NSView()

    titleLabel.font = .systemFont(ofSize: 28, weight: .semibold)

    serviceURLField.placeholderString = "https://youtrack.example.com"
    serviceURLField.setAccessibilityLabel("YouTrack address")

    oauthClientIDField.placeholderString = "OAuth client ID"
    oauthClientIDField.setAccessibilityLabel("OAuth client ID")

    oauthHubURLField.placeholderString = "Hub address override (optional)"
    oauthHubURLField.setAccessibilityLabel("Hub address")

    oauthScopeField.placeholderString = "OAuth scope override (optional)"
    oauthScopeField.setAccessibilityLabel("OAuth scope")

    oauthConnectButton.target = self
    oauthConnectButton.action = #selector(connectOAuth)

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

    savedAccountsStack.orientation = .vertical
    savedAccountsStack.alignment = .leading
    savedAccountsStack.spacing = 6
    savedAccountsStack.widthAnchor.constraint(equalToConstant: 360).isActive = true

    let authDivider = NSTextField(labelWithString: "or")
    authDivider.textColor = .secondaryLabelColor

    connectionStack.setViews(
      [
        savedAccountsStack,
        serviceURLField,
        oauthClientIDField,
        oauthHubURLField,
        oauthScopeField,
        oauthConnectButton,
        authDivider,
        tokenField,
        connectButton,
        progress,
        errorLabel,
      ],
      in: .top
    )
    connectionStack.orientation = .vertical
    connectionStack.alignment = .centerX
    connectionStack.spacing = 10

    serviceURLField.widthAnchor.constraint(equalToConstant: 360).isActive = true
    oauthClientIDField.widthAnchor.constraint(equalToConstant: 360).isActive = true
    oauthHubURLField.widthAnchor.constraint(equalToConstant: 360).isActive = true
    oauthScopeField.widthAnchor.constraint(equalToConstant: 360).isActive = true
    oauthConnectButton.widthAnchor.constraint(equalToConstant: 220).isActive = true
    tokenField.widthAnchor.constraint(equalToConstant: 360).isActive = true
    connectButton.widthAnchor.constraint(equalToConstant: 260).isActive = true

    accountName.font = .systemFont(ofSize: 14, weight: .semibold)
    accountDetail.textColor = .secondaryLabelColor

    newIssueButton.target = self
    newIssueButton.action = #selector(showQuickCreate)
    newIssueButton.bezelStyle = .inline

    disconnectButton.target = self
    disconnectButton.action = #selector(disconnect)
    disconnectButton.bezelStyle = .inline

    accountStack.setViews(
      [accountName, accountDetail, newIssueButton, disconnectButton],
      in: .top
    )
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
    refreshSavedAccounts(autoConnect: true)
  }

  deinit {
    oauthLoopbackServer?.stop()
  }

  @objc private func connectOAuth() {
    let serviceURL = serviceURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let clientID = oauthClientIDField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let hubURL = oauthHubURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let scope = oauthScopeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !serviceURL.isEmpty, !clientID.isEmpty else {
      NSSound.beep()
      return
    }

    oauthLoopbackServer?.stop()

    let loopbackServer = OAuthLoopbackServer()
    do {
      try loopbackServer.start { [weak self] result in
        guard let self else {
          return
        }

        self.oauthLoopbackServer = nil
        switch result {
        case .success(let callback):
          self.handleOAuthCallback(callback)
        case .failure(let error):
          self.show(error: error)
        }
      }
      oauthLoopbackServer = loopbackServer
    } catch {
      show(error: error)
      return
    }

    setConnecting(true)

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        let authorization = try RustBridge.beginOAuth(
          serviceURL: serviceURL,
          hubURL: hubURL.isEmpty ? nil : hubURL,
          clientID: clientID,
          redirectURI: OAuthLoopbackServer.redirectURI,
          scope: scope.isEmpty ? Self.defaultOAuthScope : scope
        )
        try SecureAccountStore.savePendingOAuth(
          serviceURL: serviceURL,
          authorization: authorization
        )

        guard let authorizationURL = URL(string: authorization.authorizationURL) else {
          throw SecureAccountStoreError.oauth("OAuth authorization URL is invalid.")
        }

        DispatchQueue.main.async {
          self?.setConnecting(false)
          NSWorkspace.shared.open(authorizationURL)
        }
      } catch {
        DispatchQueue.main.async {
          self?.oauthLoopbackServer?.stop()
          self?.oauthLoopbackServer = nil
          self?.show(error: error)
        }
      }
    }
  }

  private func handleOAuthCallback(_ callback: String) {
    guard
      let components = URLComponents(string: callback),
      components.scheme == "http",
      components.host == OAuthLoopbackServer.host,
      components.port == Int(OAuthLoopbackServer.port),
      components.path == OAuthLoopbackServer.path
    else {
      show(error: SecureAccountStoreError.oauth("OAuth callback URL is invalid."))
      return
    }

    let state = components.queryItems?.first { $0.name == "state" }?.value
    if let oauthError = components.queryItems?.first(where: { $0.name == "error" })?.value {
      if let state {
        try? SecureAccountStore.deletePendingOAuth(state: state)
      }
      let description =
        components.queryItems?.first { $0.name == "error_description" }?.value
      show(
        error: SecureAccountStoreError.oauth(
          description.map { "\(oauthError): \($0)" } ?? oauthError
        )
      )
      return
    }

    guard
      let state,
      let code = components.queryItems?.first(where: { $0.name == "code" })?.value
    else {
      show(error: SecureAccountStoreError.oauth("OAuth callback is missing code or state."))
      return
    }

    setConnecting(true)

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        let pending = try SecureAccountStore.pendingOAuth(state: state)
        let authorization = pending.authorization
        let tokens = try RustBridge.exchangeOAuthCode(
          hubURL: authorization.hubURL,
          clientID: authorization.clientID,
          redirectURI: authorization.redirectURI,
          codeVerifier: authorization.codeVerifier,
          code: code
        )
        let account = try SecureAccountStore.saveOAuthAccount(
          serviceURL: pending.serviceURL,
          authorization: authorization,
          tokens: tokens
        )
        try SecureAccountStore.deletePendingOAuth(state: state)

        let bearerToken = try SecureAccountStore.bearerToken(for: account.id)
        let work = try RustBridge.loadMyWork(
          serviceURL: account.serviceURL,
          bearerToken: bearerToken
        )

        DispatchQueue.main.async {
          self?.serviceURLField.stringValue = account.serviceURL
          self?.show(
            work,
            serviceURL: account.serviceURL,
            accountID: account.id
          )
          self?.refreshSavedAccounts()
        }
      } catch {
        DispatchQueue.main.async {
          self?.show(error: error)
        }
      }
    }
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
        let accountID: String?
        if token.isEmpty {
          accountID = nil
        } else {
          accountID = try SecureAccountStore.savePermanentToken(
            serviceURL: serviceURL,
            bearerToken: token
          ).id
        }

        DispatchQueue.main.async {
          self?.show(
            work,
            serviceURL: serviceURL,
            accountID: accountID
          )
          self?.refreshSavedAccounts()
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
    oauthConnectButton.isEnabled = !connecting
    serviceURLField.isEnabled = !connecting
    oauthClientIDField.isEnabled = !connecting
    oauthHubURLField.isEnabled = !connecting
    oauthScopeField.isEnabled = !connecting
    tokenField.isEnabled = !connecting
    errorLabel.isHidden = true

    if connecting {
      progress.startAnimation(nil)
    } else {
      progress.stopAnimation(nil)
    }
  }

  private func show(
    _ work: MyWork,
    serviceURL: String,
    accountID: String?
  ) {
    setConnecting(false)
    tokenField.stringValue = ""

    let connectionChanged =
      connectedServiceURL != serviceURL
      || connectedAccountID != accountID

    connectedServiceURL = serviceURL
    connectedAccountID = accountID

    if connectionChanged {
      prefetchedIssueDetails.removeAll()
      prefetchedProjectSchemas.removeAll()
    }

    if let accountID {
      UserDefaults.standard.set(accountID, forKey: Self.lastConnectedAccountIDKey)
    }
    issues = work.issues
    accountName.stringValue = work.user.fullName
    accountDetail.stringValue =
      work.user.login + (work.user.guest ? " · Guest access" : "")

    accountStack.isHidden = false
    connectionStack.isHidden = true
    scrollView.isHidden = false
    tableView.reloadData()
    prefetchMyWork()
  }

  private func prefetchMyWork() {
    let serviceURL = connectedServiceURL
    let accountID = connectedAccountID
    let generation = UUID()
    prefetchGeneration = generation
    prefetchProtectedIssueIDs.removeAll()

    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self else {
        return
      }

      do {
        let bearerToken =
          try accountID.map { try SecureAccountStore.bearerToken(for: $0) } ?? ""
        let prefetch = try RustBridge.prefetchMyWork(
          serviceURL: serviceURL,
          bearerToken: bearerToken
        )

        DispatchQueue.main.async {
          guard
            self.prefetchGeneration == generation,
            self.connectedServiceURL == serviceURL,
            self.connectedAccountID == accountID
          else {
            return
          }

          for issue in prefetch.issues
          where !self.prefetchProtectedIssueIDs.contains(issue.id) {
            self.prefetchedIssueDetails[issue.id] = issue
          }
          for schema in prefetch.schemas {
            self.prefetchedProjectSchemas[schema.project.id] = schema
          }
        }
      } catch {
        // Prefetch is opportunistic. The inspector still has its normal live-fetch path.
      }
    }
  }

  private func show(error: Error) {
    setConnecting(false)
    errorLabel.stringValue = error.localizedDescription
    errorLabel.isHidden = false
  }

  private func refreshSavedAccounts(autoConnect: Bool = false) {
    for view in savedAccountsStack.arrangedSubviews {
      savedAccountsStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }

    do {
      let accounts = try SecureAccountStore.accounts()
      savedAccountsStack.isHidden = accounts.isEmpty

      guard !accounts.isEmpty else {
        return
      }

      let title = NSTextField(labelWithString: "Saved accounts")
      title.textColor = .secondaryLabelColor
      title.font = .systemFont(ofSize: 12, weight: .semibold)
      savedAccountsStack.addArrangedSubview(title)

      if autoConnect, connectedServiceURL.isEmpty {
        let lastConnectedAccountID = UserDefaults.standard.string(
          forKey: Self.lastConnectedAccountIDKey
        )
        let accountToConnect =
          accounts.first { $0.id == lastConnectedAccountID }
          ?? (accounts.count == 1 ? accounts[0] : nil)

        if let accountToConnect {
          connectStored(account: accountToConnect)
        }
      }

      for account in accounts {
        let connect = AccountActionButton(title: account.serviceURL) { [weak self] in
          self?.connectStored(account: account)
        }
        connect.alignment = .left
        connect.lineBreakMode = .byTruncatingMiddle

        let forget = AccountActionButton(title: "Forget") { [weak self] in
          self?.forget(account: account)
        }
        forget.bezelStyle = .inline

        let row = NSStackView(views: [connect, forget])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.widthAnchor.constraint(equalToConstant: 360).isActive = true
        connect.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        savedAccountsStack.addArrangedSubview(row)
      }
    } catch {
      errorLabel.stringValue = error.localizedDescription
      errorLabel.isHidden = false
    }
  }

  private func connectStored(account: StoredAccount) {
    guard connectedServiceURL.isEmpty else {
      return
    }

    setConnecting(true)

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        let token = try SecureAccountStore.bearerToken(for: account.id)
        let work = try RustBridge.loadMyWork(
          serviceURL: account.serviceURL,
          bearerToken: token
        )

        DispatchQueue.main.async {
          self?.serviceURLField.stringValue = account.serviceURL
          self?.show(
            work,
            serviceURL: account.serviceURL,
            accountID: account.id
          )
        }
      } catch {
        DispatchQueue.main.async {
          self?.show(error: error)
        }
      }
    }
  }

  private func forget(account: StoredAccount) {
    do {
      try SecureAccountStore.delete(accountID: account.id)
      if UserDefaults.standard.string(forKey: Self.lastConnectedAccountIDKey) == account.id {
        UserDefaults.standard.removeObject(forKey: Self.lastConnectedAccountIDKey)
      }
      refreshSavedAccounts()
    } catch {
      show(error: error)
    }
  }

  @objc private func disconnect() {
    hideInspector()
    hideQuickCreate()
    issues = []
    connectedServiceURL = ""
    connectedAccountID = nil
    prefetchGeneration = UUID()
    prefetchProtectedIssueIDs.removeAll()
    prefetchedIssueDetails.removeAll()
    prefetchedProjectSchemas.removeAll()
    UserDefaults.standard.removeObject(forKey: Self.lastConnectedAccountIDKey)
    accountStack.isHidden = true
    scrollView.isHidden = true
    connectionStack.isHidden = false
    tableView.reloadData()
    refreshSavedAccounts()
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    let row = tableView.selectedRow
    guard issues.indices.contains(row) else {
      return
    }

    showInspector(for: issues[row])
  }

  private func showInspector(for issue: MyWorkIssue) {
    showInspector(issueID: issue.id, preview: issue)
  }

  private func showInspector(
    issueID: String,
    preview: MyWorkIssue? = nil,
    prefetchedDetails explicitDetails: IssueDetails? = nil
  ) {
    guard inspector == nil, quickCreate == nil, !connectedServiceURL.isEmpty else {
      return
    }

    let cachedDetails = explicitDetails ?? prefetchedIssueDetails[issueID]
    let cachedSchema = cachedDetails.flatMap { prefetchedProjectSchemas[$0.project.id] }

    if let cachedDetails {
      prefetchedIssueDetails[issueID] = cachedDetails
    }

    let inspector = IssueInspectorViewController(
      serviceURL: connectedServiceURL,
      accountID: connectedAccountID,
      issueID: issueID,
      preview: preview,
      prefetchedDetails: cachedDetails,
      prefetchedSchema: cachedSchema,
      onBack: { [weak self] in
        self?.hideInspector()
      },
      onIssueChanged: { [weak self] updated in
        self?.updateIssueList(updated)
      }
    )

    addChild(inspector)
    inspector.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(inspector.view)

    NSLayoutConstraint.activate([
      inspector.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      inspector.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      inspector.view.topAnchor.constraint(equalTo: view.topAnchor),
      inspector.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    self.inspector = inspector
  }

  @objc private func showQuickCreate() {
    guard quickCreate == nil, inspector == nil, !connectedServiceURL.isEmpty else {
      return
    }

    let quickCreate = QuickCreateViewController(
      serviceURL: connectedServiceURL,
      accountID: connectedAccountID,
      onCancel: { [weak self] in
        self?.hideQuickCreate()
      },
      onCreated: { [weak self] issue in
        guard let self else {
          return
        }

        self.prefetchedIssueDetails[issue.id] = issue
        self.hideQuickCreate()
        self.showInspector(issueID: issue.id, prefetchedDetails: issue)
      }
    )

    addChild(quickCreate)
    quickCreate.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(quickCreate.view)

    NSLayoutConstraint.activate([
      quickCreate.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      quickCreate.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      quickCreate.view.topAnchor.constraint(equalTo: view.topAnchor),
      quickCreate.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    self.quickCreate = quickCreate
  }

  private func hideQuickCreate() {
    guard let quickCreate else {
      return
    }

    quickCreate.view.removeFromSuperview()
    quickCreate.removeFromParent()
    self.quickCreate = nil
  }

  private func hideInspector() {
    guard let inspector else {
      return
    }

    inspector.view.removeFromSuperview()
    inspector.removeFromParent()
    self.inspector = nil
    tableView.deselectAll(nil)
  }

  private func updateIssueList(_ updated: IssueDetails) {
    prefetchProtectedIssueIDs.insert(updated.id)

    if updated.resolvedAt != nil {
      prefetchedIssueDetails.removeValue(forKey: updated.id)
      issues.removeAll { $0.id == updated.id }
    } else {
      prefetchedIssueDetails[updated.id] = updated

      if let index = issues.firstIndex(where: { $0.id == updated.id }) {
        issues[index] = MyWorkIssue(
          id: updated.id,
          idReadable: updated.idReadable,
          summary: updated.summary,
          resolvedAt: updated.resolvedAt
        )
      }
    }

    tableView.reloadData()
    tableView.deselectAll(nil)
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
  private static let lastConnectedAccountIDKey = "last_connected_account_id"
  private static let defaultOAuthScope = "YouTrack"
}

private final class AccountActionButton: NSButton {
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
