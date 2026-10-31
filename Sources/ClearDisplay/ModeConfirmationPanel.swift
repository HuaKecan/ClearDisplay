import AppKit

/// A short-lived AppKit confirmation. Menu actions need not create the larger
/// SwiftUI control window merely to ask whether a mode should be retained.
@MainActor final class ModeConfirmationPanel: NSObject {
    private let panel: NSPanel
    private let countdown = NSTextField(labelWithString: "")
    private let onKeep: () -> Void
    private let onRevert: () -> Void

    init(pending: PendingDisplayChange, keep: @escaping () -> Void, revert: @escaping () -> Void) {
        onKeep = keep
        onRevert = revert
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 390, height: 210),
                        styleMask: [.titled, .utilityWindow], backing: .buffered, defer: false)
        super.init()
        panel.title = "保留这个分辨率？"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        let summary = NSTextField(wrappingLabelWithString: pending.summary)
        summary.font = .systemFont(ofSize: 14, weight: .semibold)
        let description = NSTextField(wrappingLabelWithString: "画面显示异常时无需操作，倒计时结束会自动恢复。")
        description.textColor = .secondaryLabelColor
        description.font = .systemFont(ofSize: 12)
        countdown.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let back = NSButton(title: "恢复原配置", target: self, action: #selector(restore))
        back.keyEquivalent = "\u{1b}"
        let confirm = NSButton(title: "保留更改", target: self, action: #selector(confirm))
        confirm.keyEquivalent = "\r"
        confirm.bezelStyle = .rounded
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [back, spacer, confirm])
        actions.orientation = .horizontal
        actions.spacing = 12
        let stack = NSStackView(views: [summary, description, countdown, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = panel.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        panel.center()
        update(pending)
    }

    func update(_ pending: PendingDisplayChange) {
        countdown.stringValue = "\(pending.secondsRemaining) 秒后自动恢复"
    }
    func show() { panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func close() { panel.orderOut(nil); panel.close() }
    @objc private func confirm() { onKeep() }
    @objc private func restore() { onRevert() }
}
