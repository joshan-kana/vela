import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = makeMainMenu()

    let split = NSSplitViewController()

    let sidebar = NSSplitViewItem(
      sidebarWithViewController: SidebarViewController()
    )
    sidebar.minimumThickness = 180
    sidebar.maximumThickness = 280
    sidebar.canCollapse = false

    let content = NSSplitViewItem(
      viewController: MyWorkViewController()
    )

    split.addSplitViewItem(sidebar)
    split.addSplitViewItem(content)

    let window = NSWindow(contentViewController: split)
    window.title = "Vela"
    window.setContentSize(NSSize(width: 1000, height: 650))
    window.minSize = NSSize(width: 720, height: 480)
    window.center()
    window.makeKeyAndOrderFront(nil)

    self.window = window
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  private func makeMainMenu() -> NSMenu {
    let mainMenu = NSMenu()

    let appItem = NSMenuItem()
    mainMenu.addItem(appItem)

    let appMenu = NSMenu()
    appItem.submenu = appMenu
    appMenu.addItem(
      withTitle: "Quit Vela",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )

    let editItem = NSMenuItem()
    mainMenu.addItem(editItem)

    let editMenu = NSMenu(title: "Edit")
    editItem.submenu = editMenu
    editMenu.addItem(
      withTitle: "Cut",
      action: #selector(NSText.cut(_:)),
      keyEquivalent: "x"
    )
    editMenu.addItem(
      withTitle: "Copy",
      action: #selector(NSText.copy(_:)),
      keyEquivalent: "c"
    )
    editMenu.addItem(
      withTitle: "Paste",
      action: #selector(NSText.paste(_:)),
      keyEquivalent: "v"
    )
    editMenu.addItem(
      withTitle: "Select All",
      action: #selector(NSText.selectAll(_:)),
      keyEquivalent: "a"
    )

    return mainMenu
  }
}
