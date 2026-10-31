import AppKit
import DisplayCore
import DisplayRuntime

extension AppDelegate {
    /// Native menus build on demand from cached data. No hosting view or helper
    /// process is created merely by opening the status item.
    func buildStatusMenu(_ menu: NSMenu, store: DisplayStore) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        menu.addItem(.sectionHeader(title: "ClearDisplay · 分辨率与 HiDPI"))
        if let pending = store.pending {
            menu.addItem(item("保留更改（\(pending.secondsRemaining) 秒）", action: #selector(keepMenuChange), symbol: "checkmark.circle"))
            menu.addItem(item("恢复原分辨率", action: #selector(restoreMenuChange), symbol: "arrow.uturn.backward"))
            menu.addItem(.separator())
        }
        if store.displays.isEmpty {
            let empty = NSMenuItem(title: "尚未发现显示器", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for display in store.displays {
            let label = display.currentMode.map { "\(display.name) · \($0.resolutionLabel)" } ?? display.name
            let row = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            row.image = image(display.isVirtual ? "rectangle.on.rectangle" : display.isBuiltIn ? "laptopcomputer" : "display")
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            submenu.addItem(.sectionHeader(title: display.isMain ? "\(display.name) · 主显示器" : display.name))
            if let mode = display.currentMode {
                let active = NSMenuItem(title: "当前：\(mode.resolutionLabel) · \(mode.refreshLabel)\(mode.isHiDPI ? " · HiDPI" : "")",
                                        action: nil, keyEquivalent: "")
                active.isEnabled = false
                submenu.addItem(active)
                let pixels = NSMenuItem(title: "渲染像素：\(mode.pixelLabel)", action: nil, keyEquivalent: "")
                pixels.isEnabled = false
                submenu.addItem(pixels)
            }
            submenu.addItem(.separator())
            for highDensity in [true, false] {
                let modes = display.modes.filter { $0.isHiDPI == highDensity }
                guard !modes.isEmpty else { continue }
                let category = NSMenuItem(title: highDensity ? "HiDPI 分辨率" : "标准分辨率", action: nil, keyEquivalent: "")
                category.image = image(highDensity ? "textformat.size" : "rectangle")
                category.submenu = resolutionMenu(modes, display: display, store: store)
                submenu.addItem(category)
            }
            let favorites = store.favorites.filter { $0.displayUUID == display.uuid }
            if !favorites.isEmpty {
                submenu.addItem(.separator())
                submenu.addItem(.sectionHeader(title: "收藏"))
                for saved in favorites { submenu.addItem(favoriteItem(saved, enabled: store.pending == nil)) }
            }
            submenu.addItem(.separator())
            let settings = item("所有分辨率与设置…", action: #selector(chooseDisplay(_:)), symbol: "slider.horizontal.3")
            settings.representedObject = display.id
            submenu.addItem(settings)
            if display.isVirtual {
                let remove = item("移除虚拟屏", action: #selector(removeMenuVirtualDisplay(_:)), symbol: "minus.rectangle")
                remove.representedObject = display.id
                remove.isEnabled = store.pending == nil
                submenu.addItem(remove)
            }
            row.submenu = submenu
            menu.addItem(row)
        }
        if !store.favorites.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "常用模式"))
            for saved in store.favorites.prefix(6) {
                let available = store.displays.contains { $0.uuid == saved.displayUUID && $0.modes.contains { $0.matches(saved.mode) } }
                menu.addItem(favoriteItem(saved, enabled: available && store.pending == nil))
            }
        }
        menu.addItem(.separator())
        menu.addItem(item("打开控制面板…", action: #selector(showWindow), symbol: "slider.horizontal.3"))
        let create = item("创建 HiDPI 虚拟屏…", action: #selector(createMenuVirtualDisplay), symbol: "plus.rectangle.on.rectangle")
        create.isEnabled = store.virtualAvailable && store.pending == nil
        menu.addItem(create)
        menu.addItem(item("刷新显示器", action: #selector(refreshMenuDisplays), symbol: "arrow.clockwise"))
        menu.addItem(item("系统显示设置…", action: #selector(openDisplaySettings), symbol: "gearshape"))
        menu.addItem(.separator())
        let quit = item("退出 ClearDisplay", action: #selector(NSApplication.terminate(_:)), symbol: "power")
        quit.target = NSApp
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func resolutionMenu(_ modes: [DisplayModeSpec], display: ConnectedDisplay, store: DisplayStore) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let grouped = Dictionary(grouping: modes) { "\($0.width)x\($0.height)" }
        let groups = grouped.values.sorted { a, b in
            (a[0].width * a[0].height, a[0].width) < (b[0].width * b[0].height, b[0].width)
        }
        let commonWidths: Set<Int> = [1024, 1280, 1440, 1600, 1680, 1920, 2048, 2304, 2560, 2880, 3008, 3200, 3360, 3440, 3840]
        var primary: [[DisplayModeSpec]] = [], extra: [[DisplayModeSpec]] = []
        for group in groups {
            let isCurrent = group.contains { display.currentMode?.matches($0) == true }
            if commonWidths.contains(group[0].width) || isCurrent { primary.append(group) }
            else { extra.append(group) }
        }
        if primary.isEmpty { primary = Array(extra.prefix(10)); extra = Array(extra.dropFirst(10)) }
        for group in primary { menu.addItem(resolutionItem(group, display: display, enabled: store.pending == nil)) }
        if !extra.isEmpty {
            menu.addItem(.separator())
            let more = NSMenuItem(title: "更多尺寸（\(extra.count)）", action: nil, keyEquivalent: "")
            let overflow = NSMenu()
            overflow.autoenablesItems = false
            for group in extra { overflow.addItem(resolutionItem(group, display: display, enabled: store.pending == nil)) }
            more.submenu = overflow
            menu.addItem(more)
        }
        return menu
    }

    private func resolutionItem(_ modes: [DisplayModeSpec], display: ConnectedDisplay, enabled: Bool) -> NSMenuItem {
        let sorted = modes.sorted { $0.refreshRate > $1.refreshRate }
        if sorted.count == 1 { return modeItem(sorted[0], display: display, enabled: enabled) }
        let item = NSMenuItem(title: sorted[0].resolutionLabel, action: nil, keyEquivalent: "")
        item.state = sorted.contains { display.currentMode?.matches($0) == true } ? .on : .off
        let rates = NSMenu()
        rates.autoenablesItems = false
        for mode in sorted { rates.addItem(modeItem(mode, display: display, enabled: enabled)) }
        item.submenu = rates
        return item
    }

    private func modeItem(_ mode: DisplayModeSpec, display: ConnectedDisplay, enabled: Bool) -> NSMenuItem {
        let row = item("\(mode.resolutionLabel) · \(mode.refreshLabel)", action: #selector(selectMode(_:)))
        row.representedObject = ["display": display.id, "mode": mode.id] as [String: Any]
        row.state = display.currentMode?.matches(mode) == true ? .on : .off
        row.isEnabled = enabled
        row.toolTip = "\(mode.isHiDPI ? "HiDPI" : "标准") · 渲染 \(mode.pixelLabel)"
        return row
    }

    private func favoriteItem(_ saved: SavedMode, enabled: Bool) -> NSMenuItem {
        let row = item("\(saved.mode.resolutionLabel) · \(saved.mode.refreshLabel)\(saved.mode.isHiDPI ? " · HiDPI" : "")",
                       action: #selector(chooseFavorite(_:)), symbol: "star")
        row.representedObject = saved.id
        row.isEnabled = enabled
        row.toolTip = saved.displayName
        return row
    }

    private func item(_ title: String, action: Selector, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbol { item.image = image(symbol) }
        return item
    }

    private func image(_ symbol: String) -> NSImage? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }
}
