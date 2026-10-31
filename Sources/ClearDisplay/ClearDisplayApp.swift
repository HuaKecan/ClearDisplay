import AppKit
import DisplayCore
import DisplayRuntime
import SwiftUI

@main @MainActor struct ClearDisplayApp {
    static func main() {
        if DiagnosticCommands.handleArguments() { return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var store: DisplayStore!
    private var window: NSWindow?
    private var statusItem: NSStatusItem!
    private var confirmation: ModeConfirmationPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store = DisplayStore()
        store.onPendingChange = { [weak self] pending in self?.pendingChanged(pending) }
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 ClearDisplay", action: #selector(showAbout), keyEquivalent: "")
        let statusShortcut = NSMenuItem(title: "打开状态栏菜单", action: #selector(showStatusMenu), keyEquivalent: "d")
        statusShortcut.keyEquivalentModifierMask = [.command, .shift]
        statusShortcut.target = self
        appMenu.addItem(statusShortcut)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 ClearDisplay", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 ClearDisplay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = edit; menu.addItem(editItem)
        NSApp.mainMenu = menu

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "ClearDisplay")
        statusItem.button?.toolTip = "ClearDisplay · 分辨率与 HiDPI"
        statusItem.button?.setAccessibilityLabel("ClearDisplay 显示器菜单")
        let statusMenu = NSMenu()
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        buildStatusMenu(statusMenu, store: store)

        // The menu bar is the primary interface. No SwiftUI tree, display timer
        // or background worker remains alive until an action needs one.
        if store.pending != nil || CommandLine.arguments.contains("--window") { showWindow() }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 780),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "ClearDisplay"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = NSToolbar(identifier: "ClearDisplayToolbar")
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 960, height: 700)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: ContentView(store: store))
        window.setFrameAutosaveName("ClearDisplayMainWindow")
        window.center()
        return window
    }

    @objc func showWindow() {
        confirmation?.close(); confirmation = nil
        if window == nil { window = makeWindow() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { store.pending == nil }

    func windowWillClose(_ notification: Notification) {
        // Release the hosting view instead of keeping a hidden SwiftUI window.
        window?.contentViewController = nil
        window = nil
    }

    @objc func showStatusMenu() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let button = self.statusItem.button, let menu = self.statusItem.menu else { return }
            menu.update()
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "ClearDisplay 0.1.0"
        alert.informativeText = "分辨率与 HiDPI 控制\n原创原生 macOS 项目，MIT 许可。\n支持系统现有模式、自定义虚拟 HiDPI 屏和独立超时恢复。"
        alert.runModal()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        buildStatusMenu(menu, store: store)
    }

    @objc private func refresh() { store.refresh() }
    @objc private func revert() { store.revertChange(); showWindow() }
    @objc func keepMenuChange() { store.confirmChange() }
    @objc func restoreMenuChange() { store.revertChange() }
    @objc func refreshMenuDisplays() { store.refresh() }
    @objc func openDisplaySettings() { store.openSystemSettings() }
    @objc func createMenuVirtualDisplay() { showWindow(); store.showVirtualSheet = true }
    @objc func chooseFavorite(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID,
              let favorite = store.favorites.first(where: { $0.id == id }) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.store.applyFavorite(favorite)
            self?.showMenuErrorIfNeeded()
        }
    }
    @objc func chooseDisplay(_ item: NSMenuItem) {
        if let id = item.representedObject as? UInt32 { store.selectedDisplayID = id }
        showWindow()
    }
    @objc func removeMenuVirtualDisplay(_ item: NSMenuItem) {
        if let id = item.representedObject as? UInt32 { store.removeVirtual(id) }
    }
    @objc func selectMode(_ item: NSMenuItem) {
        guard let data = item.representedObject as? [String: Any],
              let id = data["display"] as? UInt32, let mode = data["mode"] as? String else { return }
        store.selectedDisplayID = id
        store.selectedModeID = mode
        // Leave menu tracking before Quartz changes the screen configuration.
        DispatchQueue.main.async { [weak self] in
            self?.store.applySelected()
            self?.showMenuErrorIfNeeded()
        }
    }

    private func pendingChanged(_ pending: PendingDisplayChange?) {
        guard let pending else { confirmation?.close(); confirmation = nil; return }
        guard window == nil else { return }
        if let confirmation { confirmation.update(pending); return }
        confirmation = ModeConfirmationPanel(pending: pending,
            keep: { [weak self] in self?.store.confirmChange() },
            revert: { [weak self] in self?.store.revertChange() })
        confirmation?.show()
    }

    private func showMenuErrorIfNeeded() {
        guard window == nil, store.pending == nil, let error = store.errorMessage else { return }
        let alert = NSAlert()
        alert.messageText = "无法切换显示模式"
        alert.informativeText = error
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store.shutdown() else {
            let alert = NSAlert()
            alert.messageText = "显示配置尚未恢复"
            alert.informativeText = store.errorMessage ?? "请重试恢复后退出。"
            alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); return true
    }
}
