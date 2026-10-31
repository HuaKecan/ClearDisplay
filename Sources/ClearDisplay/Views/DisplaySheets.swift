import DisplayCore
import SwiftUI

@MainActor
struct PendingChangeOverlay: View {
    let store: DisplayStore
    let secondsRemaining: Int
    let summary: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.12), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(20, max(0, secondsRemaining))) / 20)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.3), value: secondsRemaining)
                    Text("\(max(0, secondsRemaining))")
                        .font(.system(size: 31, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 84, height: 84)

                VStack(spacing: 10) {
                    Text("保留这个分辨率？")
                        .font(.system(size: 22, weight: .semibold))
                    Text(summary)
                        .font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.center)
                    Text("如果画面显示异常，请等待倒计时结束。\n系统会自动恢复切换前的显示配置。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                HStack(spacing: 12) {
                    Button("恢复原配置", action: store.revertChange)
                        .keyboardShortcut(.cancelAction)
                        .frame(maxWidth: .infinity)
                    Button("保留更改", action: store.confirmChange)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
            .padding(30)
            .frame(width: 405)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 35, y: 12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("显示配置确认。\(secondsRemaining) 秒后自动恢复。")
        }
    }
}

@MainActor
struct CreateVirtualDisplaySheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: DisplayStore
    @State private var widthText = "1920"
    @State private var heightText = "1080"
    @State private var refreshRate = 60.0

    private var width: Int { Int(widthText) ?? 0 }
    private var height: Int { Int(heightText) ?? 0 }
    private var isValid: Bool {
        (640...3840).contains(width) && (400...2160).contains(height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 30))
                    .foregroundStyle(.blue)
                    .frame(width: 52, height: 52)
                    .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    Text("创建 HiDPI 虚拟屏")
                        .font(.system(size: 21, weight: .semibold))
                    Text("一个清晰的 2× 桌面，按你的尺寸打造。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("桌面逻辑尺寸")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Menu("常用尺寸") {
                        preset("1280 × 720", width: 1280, height: 720)
                        preset("1440 × 900", width: 1440, height: 900)
                        preset("1920 × 1080", width: 1920, height: 1080)
                        preset("2560 × 1440", width: 2560, height: 1440)
                        preset("3008 × 1692", width: 3008, height: 1692)
                        preset("3440 × 1440", width: 3440, height: 1440)
                    }
                    .fixedSize()
                }
                HStack(spacing: 14) {
                    dimensionField("宽度", text: $widthText, suffix: "640–3840")
                    Text("×").foregroundStyle(.secondary).padding(.bottom, 17)
                    dimensionField("高度", text: $heightText, suffix: "400–2160")
                }

                HStack {
                    Text("刷新率")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker("刷新率", selection: $refreshRate) {
                        Text("30 Hz").tag(30.0)
                        Text("60 Hz").tag(60.0)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

                Divider()

                HStack {
                    Label("HiDPI 渲染尺寸", systemImage: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(isValid ? "\(width * 2) × \(height * 2)" : "—")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.blue)
                }
            }
            .padding(17)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

            Label {
                Text("虚拟屏会作为独立显示器出现，退出应用后移除。它不会给物理显示器添加新的原生分辨率。")
                    .lineSpacing(4)
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let message = store.errorMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("创建虚拟屏") {
                    store.errorMessage = nil
                    store.createVirtual(width: width, height: height, refreshRate: refreshRate)
                    if store.errorMessage == nil { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
                .accessibilityIdentifier("createVirtualDisplay")
            }
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 510)
    }

    private func dimensionField(_ title: String, text: Binding<String>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField(title, text: text)
                .font(.system(size: 20, weight: .medium, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(title)
            Text(suffix)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func preset(_ label: String, width: Int, height: Int) -> some View {
        Button(label) {
            widthText = String(width)
            heightText = String(height)
        }
    }
}
