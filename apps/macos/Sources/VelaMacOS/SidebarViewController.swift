import AppKit

final class SidebarViewController: NSViewController {
  override func loadView() {
    let visualEffect = NSVisualEffectView()
    visualEffect.material = .sidebar
    visualEffect.blendingMode = .behindWindow
    visualEffect.state = .active

    let appName = NSTextField(labelWithString: "Vela")
    appName.font = .systemFont(ofSize: 20, weight: .semibold)

    let myWork = NSButton(title: "My Work", target: nil, action: nil)
    myWork.bezelStyle = .accessoryBarAction
    myWork.alignment = .left
    myWork.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: nil)
    myWork.imagePosition = .imageLeading
    myWork.isBordered = false

    let projects = NSButton(title: "Projects", target: nil, action: nil)
    projects.bezelStyle = .accessoryBarAction
    projects.alignment = .left
    projects.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
    projects.imagePosition = .imageLeading
    projects.isBordered = false
    projects.isEnabled = false

    let stack = NSStackView(views: [appName, myWork, projects])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false

    visualEffect.addSubview(stack)

    NSLayoutConstraint.activate([
      visualEffect.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
      stack.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(
        lessThanOrEqualTo: visualEffect.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 20),
      myWork.widthAnchor.constraint(equalTo: stack.widthAnchor),
      projects.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])

    view = visualEffect
  }
}
