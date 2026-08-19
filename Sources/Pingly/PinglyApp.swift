import AppKit
import SwiftUI

@main
struct PinglyApp: App {
    @NSApplicationDelegateAdaptor(PinglyAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class PinglyAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            NSApplication.shared.applicationIconImage = appIcon
        }
        PinglyStatusItemController.shared.install()
        PinglyWindowCoordinator.shared.showMainWindow()
        ReminderScheduler.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        PinglyWindowCoordinator.shared.showMainWindow()
        return true
    }
}

@MainActor
final class PinglyStatusItemController: NSObject, NSMenuDelegate {
    static let shared = PinglyStatusItemController()

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Pingly")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
            button.toolTip = "Pingly"
        }

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        statusMenu = menu
        rebuildMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let menu = statusMenu else { return }
        menu.removeAllItems()

        let store = AppStore.shared
        if store.isPaused {
            menu.addItem(menuItem("继续提醒", action: #selector(resumeReminders)))
        } else {
            let pauseItem = NSMenuItem(title: "快速暂停", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.addItem(pauseMenuItem("30 分钟", seconds: 30 * 60))
            submenu.addItem(pauseMenuItem("1 小时", seconds: 60 * 60))
            submenu.addItem(menuItem("今天剩余时间", action: #selector(pauseForToday)))
            pauseItem.submenu = submenu
            menu.addItem(pauseItem)
        }

        let nextTitle = store.nextReminder.map { "下一条：\($0.title)" } ?? "暂无即将到来的提醒"
        let nextItem = NSMenuItem(title: nextTitle, action: nil, keyEquivalent: "")
        nextItem.isEnabled = false
        menu.addItem(nextItem)

        menu.addItem(.separator())
        menu.addItem(menuItem("打开主窗口", action: #selector(openMainWindow)))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出 Pingly", action: #selector(quitPingly)))
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func pauseMenuItem(_ title: String, seconds: TimeInterval) -> NSMenuItem {
        let item = menuItem(title, action: #selector(pauseForDuration(_:)))
        item.representedObject = seconds
        return item
    }

    @objc private func resumeReminders() {
        AppStore.shared.resume()
    }

    @objc private func pauseForDuration(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        AppStore.shared.pause(for: seconds)
    }

    @objc private func pauseForToday() {
        AppStore.shared.pauseForRestOfToday()
    }

    @objc private func openMainWindow() {
        PinglyWindowCoordinator.shared.showMainWindow()
    }

    @objc private func quitPingly() {
        NSApp.terminate(nil)
    }
}

@MainActor
final class PinglyWindowCoordinator {
    static let shared = PinglyWindowCoordinator()

    private var windowController: NSWindowController?

    func showMainWindow() {
        if windowController == nil {
            let rootView = MainWindowView()
                .environmentObject(AppStore.shared)
                .frame(minWidth: 680, minHeight: 520)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 590),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Pingly"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.minSize = NSSize(width: 680, height: 520)
            window.contentViewController = NSHostingController(rootView: rootView)
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("PinglyMainWindow")
            windowController = NSWindowController(window: window)
        }

        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showReminders() {
        AppStore.shared.isShowingOnboarding = false
        AppStore.shared.selectedPage = .reminders
        showMainWindow()
    }
}
