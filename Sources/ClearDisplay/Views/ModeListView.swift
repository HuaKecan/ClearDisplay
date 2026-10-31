import DisplayCore
import DisplayRuntime
import SwiftUI

@MainActor
struct ModeListView: View {
    @Bindable var store: DisplayStore
    let display: ConnectedDisplay

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("逻辑分辨率")
                    .frame(width: 153, alignment: .leading)
                Text("渲染像素")
                    .frame(minWidth: 126, alignment: .leading)
                Spacer(minLength: 0)
                Text("刷新率")
                    .frame(width: 74, alignment: .trailing)
                Text("缩放")
                    .frame(width: 72, alignment: .center)
                Color.clear.frame(width: 65, height: 1)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)

            Divider()

            if store.visibleModes.isEmpty {
                ContentUnavailableView {
                    Label("没有匹配的显示模式", systemImage: "magnifyingglass")
                } description: {
                    Text(emptyDescription)
                } actions: {
                    Button("查看全部分辨率") {
                        store.query = ""
                        store.filter = .all
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(store.visibleModes, id: \.id) { mode in
                            ModeRow(
                                mode: mode,
                                isSelected: store.selectedModeID == mode.id,
                                isCurrent: display.currentMode?.signature == mode.signature,
                                isFavorite: store.isFavorite(mode),
                                select: { store.selectedModeID = mode.id },
                                toggleFavorite: { store.toggleFavorite(mode) }
                            )
                        }
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 3)
                }
                .scrollIndicators(.automatic)
            }

            HStack(spacing: 6) {
                Text("\(store.visibleModes.count) 种模式")
                Text("·")
                Text("HiDPI 以更多像素绘制同样大小的桌面")
                Spacer(minLength: 0)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.vertical, 12)
        }
    }

    private var emptyDescription: String {
        if store.filter == .hiDPI {
            return "macOS 没有为此显示器提供匹配的 HiDPI 模式。可查看全部模式，或创建独立的 HiDPI 虚拟屏。"
        }
        return "试试其他尺寸或刷新率，或切换到“全部”查看 macOS 提供的模式。"
    }
}

private struct ModeRow: View {
    let mode: DisplayModeSpec
    let isSelected: Bool
    let isCurrent: Bool
    let isFavorite: Bool
    let select: () -> Void
    let toggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: select) {
                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.45))
                        Text(mode.resolutionLabel)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                    .frame(width: 153, alignment: .leading)

                    Text(mode.pixelLabel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 126, alignment: .leading)

                    Spacer(minLength: 0)

                    Text(mode.refreshLabel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 74, alignment: .trailing)

                    Group {
                        if mode.isHiDPI {
                            SmallBadge(text: "HiDPI", color: .blue)
                        } else {
                            Text("1×")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 72)

                    Group {
                        if isCurrent {
                            Text("当前")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Color.clear.frame(height: 1)
                        }
                    }
                    .frame(width: 32)
                }
                .contentShape(Rectangle())
                .padding(.leading, 12)
                .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(mode.resolutionLabel)，渲染 \(mode.pixelLabel)，\(mode.refreshLabel)，\(mode.isHiDPI ? "HiDPI" : "标准")\(isCurrent ? "，当前模式" : "")")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(isFavorite ? Color.orange : Color.secondary.opacity(0.55))
                    .frame(width: 32, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "取消收藏" : "收藏此模式")
            .accessibilityLabel(isFavorite ? "取消收藏 \(mode.resolutionLabel)" : "收藏 \(mode.resolutionLabel)")
            .padding(.trailing, 3)
        }
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.2) : Color.clear, lineWidth: 1)
        }
    }
}
