import AppKit
import OpenTypelessCore

private final class RecordingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class RecordChrome {
    var isVisible: Bool { panel.isVisible }
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    private let panel = RecordingPanel(
        contentRect: NSRect(x: 0, y: 0, width: 168, height: 44),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let pill = PillView(frame: NSRect(x: 0, y: 0, width: 168, height: 36))
    private var waveTimer: Timer?
    private var phase = 0.0
    private var pendingWarning: String?

    init() {
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        pill.onCancel = { [weak self] in self?.onCancel?() }
        pill.onConfirm = { [weak self] in self?.onConfirm?() }
        panel.contentView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        panel.contentView?.addSubview(pill)
    }

    func showRecording() {
        pendingWarning = nil
        pill.mode = .recording
        panel.ignoresMouseEvents = false
        startWave()
        place(width: 168, height: 44)
        panel.orderFrontRegardless()
    }

    func showWorking() {
        pendingWarning = nil
        pill.mode = .working
        panel.ignoresMouseEvents = true
        startWave()
        place(width: 168, height: 44)
        panel.orderFrontRegardless()
    }

    func showPending(_ text: String, warning: String? = nil) {
        guard let text = try? OutputPolicy.traditional(text) else {
            showWarning(OutputConversionError.unavailable.errorDescription ?? "繁體中文轉換失敗。", title: "文字未輸出")
            return
        }
        stopWave()
        pendingWarning = warning
        pill.pendingHint = warning == nil ? "文字已備妥；若未出現，請按 ⌘V 貼上。" : "AI 校正未完成；文字仍可貼上，詳情將保留顯示。"
        pill.mode = .pending(text)
        panel.ignoresMouseEvents = false
        place(width: 420, height: 96)
        panel.orderFrontRegardless()
    }

    func showMessage(_ text: String) {
        pendingWarning = nil
        stopWave()
        pill.mode = .message(text)
        panel.ignoresMouseEvents = true
        let width = min(420, max(180, CGFloat(text.count) * 15 + 36))
        place(width: width, height: 44)
        panel.orderFrontRegardless()
    }

    func dismissPending() {
        if let warning = pendingWarning { showWarning(warning) }
        else { hide() }
    }

    func showWarning(_ text: String, title: String = "AI 校正未完成") {
        pendingWarning = nil
        stopWave()
        pill.mode = .warning(title, text)
        panel.ignoresMouseEvents = false
        place(width: 500, height: 140)
        panel.orderFrontRegardless()
    }

    func hide() {
        pendingWarning = nil
        stopWave()
        panel.orderOut(nil)
    }

    private func place(width: CGFloat, height: CGFloat) {
        pill.frame = NSRect(x: 0, y: 8, width: width, height: height - 8)
        panel.setContentSize(NSSize(width: width, height: height))
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
            return
        }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - width / 2, y: frame.minY + 6))
    }

    private func startWave() {
        if waveTimer != nil { return }
        waveTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.55
            self.pill.phase = self.phase
            self.pill.needsDisplay = true
        }
    }

    private func stopWave() {
        waveTimer?.invalidate()
        waveTimer = nil
    }
}

final class PillView: NSView {
    enum Mode {
        case recording
        case working
        case pending(String)
        case warning(String, String)
        case message(String)
    }

    var pendingHint = "文字已備妥；若未出現，請按 ⌘V 貼上。"
    var mode: Mode = .recording
    var phase = 0.0
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let pill = bounds.insetBy(dx: 0, dy: 0)
        let radius: CGFloat = isPending ? 14 : pill.height / 2
        let path = NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius)
        NSColor.black.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: pill.offsetBy(dx: 0, dy: -1), xRadius: radius, yRadius: radius).fill()
        NSColor(calibratedWhite: 0.07, alpha: 0.98).setFill()
        path.fill()

        switch mode {
        case .message(let text):
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
            (text as NSString).draw(at: point, withAttributes: attrs)
        case .pending(let text):
            drawPending(text)
        case .warning(let title, let text):
            let heading: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.systemOrange]
            (title as NSString).draw(at: NSPoint(x: 16, y: bounds.height - 32), withAttributes: heading)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            let detail: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white, .paragraphStyle: paragraph]
            (text as NSString).draw(in: NSRect(x: 16, y: 12, width: bounds.width - 44, height: bounds.height - 54), withAttributes: detail)
            drawX(in: pendingCloseRect.insetBy(dx: 5, dy: 5))
        case .recording, .working:
            drawControls()
        }
    }

    private var isPending: Bool {
        switch mode { case .pending, .warning: return true; default: return false }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isPending {
            if pendingCloseRect.contains(point) {
                onCancel?()
            }
            return
        }
        guard case .recording = mode else { return }
        if cancelRect.contains(point) {
            onCancel?()
        } else if confirmRect.contains(point) {
            onConfirm?()
        }
    }

    private var pendingCloseRect: NSRect {
        NSRect(x: bounds.width - 28, y: bounds.height - 26, width: 20, height: 20)
    }

    private func drawPending(_ text: String) {
        let shown = text.count > 42 ? String(text.prefix(42)) + "…" : text
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let hint: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.72, alpha: 1)
        ]
        (shown as NSString).draw(at: NSPoint(x: 16, y: 52), withAttributes: body)
        (pendingHint as NSString).draw(at: NSPoint(x: 16, y: 28), withAttributes: hint)
        drawX(in: pendingCloseRect.insetBy(dx: 5, dy: 5))
    }

    private var cancelRect: NSRect {
        NSRect(x: 5, y: (bounds.height - 26) / 2, width: 26, height: 26)
    }

    private var confirmRect: NSRect {
        NSRect(x: bounds.width - 31, y: (bounds.height - 26) / 2, width: 26, height: 26)
    }

    private func drawControls() {
        let cancel = NSBezierPath(ovalIn: cancelRect)
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        cancel.fill()
        drawX(in: cancelRect.insetBy(dx: 8, dy: 8))

        let confirm = NSBezierPath(ovalIn: confirmRect)
        NSColor.white.setFill()
        confirm.fill()
        drawCheck(in: confirmRect.insetBy(dx: 7, dy: 8))

        let bars = 17
        let barWidth: CGFloat = 1.6
        let gap: CGFloat = 1.7
        let total = CGFloat(bars) * barWidth + CGFloat(bars - 1) * gap
        var x = (bounds.width - total) / 2
        let midY = bounds.midY
        NSColor.white.setFill()
        for index in 0..<bars {
            let wave = abs(sin(phase + Double(index) * 0.7))
            let height = 3 + CGFloat(wave) * (modeIsWorking ? 5 : 12)
            let rect = NSRect(x: x, y: midY - height / 2, width: barWidth, height: height)
            NSBezierPath(roundedRect: rect, xRadius: 0.8, yRadius: 0.8).fill()
            x += barWidth + gap
        }
    }

    private var modeIsWorking: Bool {
        if case .working = mode { return true }
        return false
    }

    private func drawX(in rect: NSRect) {
        let path = NSBezierPath()
        path.lineWidth = 2
        path.lineCapStyle = .round
        NSColor.white.setStroke()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.stroke()
    }

    private func drawCheck(in rect: NSRect) {
        let path = NSBezierPath()
        path.lineWidth = 2.4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.black.setStroke()
        path.move(to: NSPoint(x: rect.minX, y: rect.midY))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + 1))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - 1))
        path.stroke()
    }
}
