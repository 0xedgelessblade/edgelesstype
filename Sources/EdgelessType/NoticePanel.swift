import AppKit
import EdgelessTypeCore

private final class NoticeWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class NoticeBody: NSView {
    var onHover: ((Bool) -> Void)?
    var onBackgroundClick: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { onBackgroundClick?() }
}

/// Result notices sit at the top of the screen and do not take keyboard focus.
final class NoticePanel {
    var onRetry: (() -> Void)?
    var onCopy: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onDismissed: (() -> Void)?

    private let panel = NoticeWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 32),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let effect = NSVisualEffectView()
    private let body = NoticeBody()
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let action = NSButton()
    private let copyButton = NSButton()
    private let close = NSButton()
    private let progress = NSView()
    private var dismissTimer: Timer?
    private var remaining: TimeInterval = 0
    private var duration: TimeInterval = 0
    private var expanded = false
    private var hovered = false
    private var current: CorrectionNotice?
    private var escapeMonitor: Any?
    private var failureRetry: (() -> Bool)?

    init() {
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.masksToBounds = true
        panel.contentView = effect
        effect.addSubview(body)
        for item in [icon, title, detail, action, copyButton, close, progress] as [NSView] {
            body.addSubview(item)
        }
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 3
        style(action)
        style(copyButton)
        close.isBordered = false
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "關閉")
        close.contentTintColor = .secondaryLabelColor
        close.target = self
        close.action = #selector(closeNotice)
        close.setAccessibilityLabel("關閉")
        progress.wantsLayer = true
        progress.layer?.backgroundColor = NSColor.secondaryLabelColor.cgColor
        body.onHover = { [weak self] inside in self?.setHovered(inside) }
        body.onBackgroundClick = { [weak self] in self?.expand() }
    }

    func showDegraded(_ notice: CorrectionNotice) {
        current = notice
        expanded = false
        present(symbol: "exclamationmark.circle.fill", tint: .systemOrange, heading: notice.label,
                message: "已貼上原文，未加標點", actionTitle: notice.opensSettings ? "開啟設定" : "重試",
                showsCopy: false, lifetime: 4, capsule: true)
    }

    /// `retry` returns false when it cannot start now; the card then stays open with the kept recording.
    func showFailure(title heading: String, detail message: String, retry: (() -> Bool)? = nil) {
        current = nil
        expanded = true
        present(symbol: "xmark.circle.fill", tint: .systemRed, heading: heading, message: message,
                actionTitle: retry == nil ? nil : "重試", showsCopy: false, lifetime: 8, capsule: false)
        failureRetry = retry
    }

    func showCopied() {
        current = nil
        expanded = false
        present(symbol: "checkmark.circle.fill", tint: .systemGreen, heading: "已複製校正版",
                message: "⌘V 取代", actionTitle: nil, showsCopy: false, lifetime: 3, capsule: true)
    }

    func hide() {
        failureRetry = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
        panel.orderOut(nil)
        onDismissed?()
    }

    private func present(symbol: String, tint: NSColor, heading: String, message: String,
                         actionTitle: String?, showsCopy: Bool, lifetime: TimeInterval, capsule: Bool) {
        failureRetry = nil
        dismissTimer?.invalidate()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: heading)
        icon.contentTintColor = tint
        title.stringValue = heading
        detail.stringValue = message
        action.isHidden = actionTitle == nil
        action.title = actionTitle ?? ""
        action.target = self
        action.action = #selector(performAction)
        copyButton.isHidden = !showsCopy
        copyButton.title = "複製原文"
        copyButton.target = self
        copyButton.action = #selector(copyOriginal)
        close.isHidden = capsule
        let width: CGFloat = capsule ? min(360, 196 + CGFloat((heading + message).count) * 7) : 340
        let height: CGFloat = capsule ? 32 : 108
        layout(width: width, height: height, capsule: capsule)
        place(width: width, height: height)
        announce("\(heading)。\(message)")
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        let origin = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y + 6))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(origin)
        }
        duration = lifetime
        remaining = lifetime
        startTimer()
        if escapeMonitor == nil {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.panel.isVisible, self.expanded, event.keyCode == 53 else { return event }
                self.closeNotice()
                return nil
            }
        }
    }

    private func layout(width: CGFloat, height: CGFloat, capsule: Bool) {
        effect.layer?.cornerRadius = capsule ? height / 2 : 14
        body.frame = NSRect(x: 0, y: 0, width: width, height: height)
        icon.frame = NSRect(x: 10, y: capsule ? 8 : height - 28, width: 16, height: 16)
        if capsule {
            title.frame = NSRect(x: 32, y: 7, width: min(72, width * 0.28), height: 18)
            detail.frame = NSRect(x: title.frame.maxX + 8, y: 7, width: width - title.frame.maxX - 78, height: 18)
            detail.maximumNumberOfLines = 1
            action.frame = NSRect(x: width - 62, y: 4, width: 54, height: 24)
            close.frame = NSRect(x: width - 28, y: 4, width: 24, height: 24)
        } else {
            title.frame = NSRect(x: 32, y: height - 30, width: width - 64, height: 18)
            detail.frame = NSRect(x: 32, y: 36, width: width - 48, height: 40)
            detail.maximumNumberOfLines = 3
            copyButton.frame = NSRect(x: width - 148, y: 10, width: 72, height: 24)
            action.frame = NSRect(x: width - 72, y: 10, width: 60, height: 24)
            close.frame = NSRect(x: width - 28, y: height - 28, width: 24, height: 24)
        }
        progress.frame = NSRect(x: 14, y: 1, width: width - 28, height: 2)
    }

    private func place(width: CGFloat, height: CGFloat) {
        panel.setContentSize(NSSize(width: width, height: height))
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - width / 2, y: frame.maxY - height - 8))
    }

    private func expand() {
        guard let notice = current, !expanded else { return }
        expanded = true
        dismissTimer?.invalidate()
        copyButton.isHidden = false
        close.isHidden = false
        detail.stringValue = notice.detail
        title.stringValue = "已貼上原文"
        layout(width: 340, height: 118, capsule: false)
        place(width: 340, height: 118)
        progress.isHidden = true
    }

    private func setHovered(_ inside: Bool) {
        hovered = inside
        if inside { dismissTimer?.invalidate(); dismissTimer = nil }
        else if !expanded { startTimer() }
    }

    private func startTimer() {
        guard !expanded, remaining > 0 else { return }
        let started = Date()
        let slice = remaining
        progress.isHidden = false
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let left = slice - Date().timeIntervalSince(started)
            self.remaining = left
            let width = max(0, (self.body.bounds.width - 28) * CGFloat(left / max(self.duration, 0.1)))
            self.progress.frame.size.width = width
            if left <= 0 { timer.invalidate(); self.fadeOut() }
        }
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.hide() })
    }

    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue
        ])
    }

    private func style(_ button: NSButton) {
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.contentTintColor = .labelColor
    }

    @objc private func performAction() {
        if let retry = failureRetry {
            if retry() { hide() }
            return
        }
        if current?.opensSettings == true { onOpenSettings?() }
        else { onRetry?() }
    }

    @objc private func copyOriginal() { onCopy?() }
    @objc private func closeNotice() { fadeOut() }
}
