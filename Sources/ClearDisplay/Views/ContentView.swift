import AppKit
import DisplayCore
import DisplayRuntime
import SwiftUI

@MainActor
struct ContentView: View {
    @Bindable var store: DisplayStore

    var body: some View {
        ZStack {
            NavigationSplitView {
                DisplaySidebar(store: store)
                    .navigationSplitViewColumnWidth(min: 224, ideal: 248, max: 290)
            } detail: {
                if let display = store.selectedDisplay {
                    DisplayDetailView(store: store, display: display)
                } else {
                    ContentUnavailableView {
                        Label("未发现显示器", systemImage: "display.trianglebadge.exclamationmark")
                    } description: {
                        Text("连接显示器后刷新。显示模式由 macOS 提供。")
                    } actions: {
                        Button("重新检测", action: store.refresh)
                    }
                }
            }
            .disabled(store.pending != nil)

            if let pending = store.pending {
                PendingChangeOverlay(
                    store: store,
                    secondsRemaining: pending.secondsRemaining,
                    summary: pending.summary
                )
                .zIndex(20)
            }
        }
        .frame(minWidth: 1030, minHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.blue)
        .sheet(isPresented: $store.showVirtualSheet) {
            CreateVirtualDisplaySheet(store: store)
        }
    }
}

@MainActor
private struct DisplaySidebar: View {
    @Bindable var store: DisplayStore

    private var physicalDisplays: [ConnectedDisplay] {
        store.displays.filter { !$0.isVirtual }
    }

    private var virtualDisplays: [ConnectedDisplay] {
        store.displays.filter(\.isVirtual)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "display")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("ClearDisplay").font(.system(size: 18, weight: .semibold))
                    Text("每个像素，恰到好处")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 22)

            List(selection: $store.selectedDisplayID) {
                Section("已连接 · \(physicalDisplays.count)") {
                    ForEach(physicalDisplays, id: \.id) { display in
                        SidebarDisplayRow(display: display)
                            .tag(display.id)
                    }
                }

                if !virtualDisplays.isEmpty {
                    Section("虚拟显示器") {
                        ForEach(virtualDisplays, id: \.id) { display in
                            SidebarDisplayRow(display: display)
                                .tag(display.id)
                                .contextMenu {
                                    Button("移除虚拟显示器", role: .destructive) {
                                        store.removeVirtual(display.id)
                                    }
                                }
                        }
                    }
                }

                if !store.favorites.isEmpty {
                    Section("常用分辨率") {
                        ForEach(store.favorites, id: \.id) { favorite in
                            Button {
                                store.applyFavorite(favorite)
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(favorite.mode.resolutionLabel)
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        Text(favorite.displayName)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                            .buttonStyle(.plain)
                            .help("切换到 \(favorite.mode.resolutionLabel) · \(favorite.mode.refreshLabel)")
                            .contextMenu {
                                Button("取消收藏", systemImage: "star.slash") {
                                    store.removeFavorite(favorite.id)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            VStack(spacing: 10) {
                Button {
                    store.showVirtualSheet = true
                } label: {
                    Label("创建 HiDPI 虚拟屏", systemImage: "plus.rectangle.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(!store.virtualAvailable)
                .help(store.virtualAvailable ? "添加自定义尺寸的 2× HiDPI 桌面" : "当前 macOS 无法使用虚拟显示器接口")

                HStack {
                    Label("\(store.displays.count) 台显示器", systemImage: "circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Button("重新检测", systemImage: "arrow.clockwise", action: store.refresh)
                        Button("打开系统显示设置", systemImage: "gearshape", action: store.openSystemSettings)
                        Button("导出显示诊断", systemImage: "square.and.arrow.up", action: store.exportDiagnostics)
                        Divider()
                        Button("退出 ClearDisplay", role: .destructive) {
                            NSApplication.shared.terminate(nil)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("更多操作")
                }
            }
            .padding(16)
            .background(.bar)
        }
        .navigationTitle("")
    }
}

private struct SidebarDisplayRow: View {
    let display: ConnectedDisplay

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: display.isVirtual ? "rectangle.on.rectangle" : (display.isBuiltIn ? "laptopcomputer" : "display"))
                .font(.system(size: 21, weight: .regular))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 5) {
                Text(display.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let mode = display.currentMode {
                    HStack(spacing: 5) {
                        Text(mode.resolutionLabel)
                            .font(.system(size: 10, design: .monospaced))
                        if mode.isHiDPI {
                            Text("HiDPI")
                                .font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Text("读取模式中…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if display.isMain {
                Circle().fill(.green).frame(width: 5, height: 5)
                    .help("主显示器")
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private struct DisplayDetailView: View {
    @Bindable var store: DisplayStore
    let display: ConnectedDisplay

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let message = store.errorMessage {
                    InlineMessage(message: message, isError: true) {
                        store.errorMessage = nil
                    }
                } else if let message = store.statusMessage {
                    InlineMessage(message: message, isError: false) {
                        store.statusMessage = nil
                    }
                }
                DisplaySummaryView(display: display)
                modeControls
            }
            .padding(.horizontal, 26)
            .padding(.top, 23)
            .padding(.bottom, 14)

            ModeListView(store: store, display: display)
                .padding(.horizontal, 26)

            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("分辨率与 HiDPI")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(display.name)
                        .font(.system(size: 26, weight: .semibold))
                        .lineLimit(1)
                    if display.isMain { SmallBadge(text: "主显示器", color: .secondary) }
                    if display.isVirtual { SmallBadge(text: "虚拟屏", color: .purple) }
                }
                Text("选择舒适的桌面尺寸，让文字和图像保持清晰。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(action: store.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("重新读取显示模式")
            .accessibilityLabel("刷新显示模式")
        }
    }

    private var modeControls: some View {
        HStack(spacing: 14) {
            Picker("模式筛选", selection: $store.filter) {
                ForEach(ModeFilter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 250)

            Spacer(minLength: 10)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索分辨率或刷新率", text: $store.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .accessibilityIdentifier("modeSearch")
                if !store.query.isEmpty {
                    Button {
                        store.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 240)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                if let selected = store.selectedMode {
                    HStack(spacing: 6) {
                        Text(selected.resolutionLabel)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        if selected.isHiDPI { SmallBadge(text: "HiDPI", color: .blue) }
                        Text("· \(selected.refreshLabel)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("选择一种显示模式")
                        .font(.system(size: 13, weight: .medium))
                }
                Text("切换后需确认保留，超时将自动恢复。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if display.isVirtual {
                Button("移除虚拟屏", role: .destructive) {
                    store.removeVirtual(display.id)
                }
                .controlSize(.large)
            }
            Button {
                store.applySelected()
            } label: {
                Label("应用分辨率", systemImage: "checkmark")
                    .frame(minWidth: 106)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!store.canApply)
            .accessibilityIdentifier("applyResolution")
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 17)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct InlineMessage: View {
    let message: String
    let isError: Bool
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .orange : .green)
            Text(message).font(.system(size: 12)).textSelection(.enabled)
            Spacer(minLength: 4)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("关闭提示")
        }
        .padding(11)
        .background((isError ? Color.orange : Color.green).opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct SmallBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.1), in: Capsule())
            .fixedSize()
    }
}
