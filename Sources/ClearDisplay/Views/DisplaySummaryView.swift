import DisplayCore
import DisplayRuntime
import SwiftUI

struct DisplaySummaryView: View {
    let display: ConnectedDisplay

    var body: some View {
        HStack(spacing: 28) {
            MonitorIllustration(mode: display.currentMode, isBuiltIn: display.isBuiltIn)
                .frame(width: 218, height: 145)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 7) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("当前显示模式")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let mode = display.currentMode {
                        SmallBadge(text: mode.isHiDPI ? "HiDPI 已启用" : "标准分辨率", color: mode.isHiDPI ? .blue : .secondary)
                    }
                }

                if let mode = display.currentMode {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(mode.resolutionLabel)
                            .font(.system(size: 30, weight: .medium, design: .rounded))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Text("逻辑尺寸")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 0) {
                        SummaryMetric(title: "渲染像素", value: mode.pixelLabel)
                        metricDivider
                        SummaryMetric(title: "刷新率", value: mode.refreshLabel)
                        metricDivider
                        SummaryMetric(title: "像素缩放", value: String(format: "%.1f×", mode.scale))
                    }
                } else {
                    Text("正在读取…")
                        .font(.system(size: 26, weight: .medium))
                    Text("macOS 尚未返回当前显示模式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(.primary.opacity(0.1))
            .frame(width: 1, height: 29)
            .padding(.horizontal, 16)
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct MonitorIllustration: View {
    let mode: DisplayModeSpec?
    let isBuiltIn: Bool

    private var aspectRatio: CGFloat {
        guard let mode, mode.width > 0, mode.height > 0 else { return 16.0 / 10.0 }
        return min(2.5, max(1, CGFloat(mode.width) / CGFloat(mode.height)))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .labelColor).opacity(0.88))
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.12, green: 0.31, blue: 0.75), Color(red: 0.27, green: 0.52, blue: 0.88), Color(red: 0.49, green: 0.78, blue: 0.91)],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 140, height: 140)
                        .blur(radius: 5)
                        .offset(x: 80, y: -35)
                    Circle()
                        .fill(Color(red: 0.16, green: 0.84, blue: 0.89).opacity(0.46))
                        .frame(width: 130, height: 130)
                        .blur(radius: 20)
                        .offset(x: -70, y: 55)
                    VStack(spacing: 6) {
                        Text("Aa")
                            .font(.system(size: 35, weight: .medium, design: .serif))
                        Text("清晰，刚刚好")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.white)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(5)
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: 210, maxHeight: 115)
            .shadow(color: .black.opacity(0.12), radius: 7, y: 4)

            if isBuiltIn {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 218, height: 6)
                    .padding(.top, 2)
            } else {
                Rectangle()
                    .fill(LinearGradient(colors: [Color(nsColor: .tertiaryLabelColor), Color(nsColor: .quaternaryLabelColor)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 26, height: 13)
                Capsule()
                    .fill(Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 66, height: 4)
            }

            Text("桌面比例示意")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(.top, 9)
        }
    }
}
