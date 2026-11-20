import AppKit
import ApplicationServices
import TranslationCore

@MainActor
final class ClipboardHotkey {
    var onCapture: ((String?, String?, CGPoint) -> Void)?
    var onPermissionChange: ((Bool) -> Void)?
    private var monitor: Any?
    private var timer: Timer?
    private var detector = HotkeyDetector()
    private var baseline = 0
    private var sourcePID: pid_t?
    private var lastTrigger: TimeInterval = -.infinity
    private var capture: Task<Void, Never>?
    private var permission = false
    private(set) var paused = false

    func start() {
        refreshPermission()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermission() }
        }
    }

    func refreshPermission() {
        let trusted = AXIsProcessTrusted()
        if trusted != permission {
            permission = trusted
            onPermissionChange?(trusted)
        }
        if trusted, monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
            }
        } else if !trusted, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            cancelCapture()
        }
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshPermission()
    }

    func setPaused(_ value: Bool) { paused = value; cancelCapture() }

    func cancelCapture() {
        capture?.cancel()
        capture = nil
        detector.reset()
    }

    private func handle(_ event: NSEvent) {
        guard !paused else { return }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.type == .flagsChanged {
            if flags != [.command] { detector.reset() }
            return
        }
        let isC = event.keyCode == 8
        if event.type == .keyUp { detector.keyUp(isC: isC); return }
        guard event.timestamp - lastTrigger > 0.6 else { return }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if sourcePID != frontPID { detector.reset() }
        switch detector.keyDown(isC: isC, commandOnly: flags == [.command],
                                isRepeat: event.isARepeat, time: event.timestamp) {
        case .none: break
        case .armed:
            capture?.cancel()
            sourcePID = frontPID
            baseline = NSPasteboard.general.changeCount
        case .triggered:
            let triggerMouse = NSEvent.mouseLocation
            lastTrigger = event.timestamp
            detector.reset()
            capture?.cancel()
            let initial = baseline
            let expectedPID = sourcePID
            capture = Task { [weak self] in
                // Both Command-C events pass through. Wait for the source app to copy before showing UI.
                for attempt in 0..<18 {
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                    guard let self, !Task.isCancelled else { return }
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else { return }
                    let pasteboard = NSPasteboard.general
                    guard attempt >= 1, pasteboard.changeCount != initial else { continue }
                    if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny {
                        self.onCapture?(nil, "剪贴板访问已被拒绝。请在系统设置中允许 Quick Translate 访问剪贴板。", triggerMouse)
                        return
                    }
                    let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !Task.isCancelled else { return }
                    if let text, !text.isEmpty {
                        self.onCapture?(text, nil, triggerMouse)
                    } else {
                        self.onCapture?(nil, "本次复制没有可翻译的文字。请重新选择可以复制的文本后按 ⌘CC。", triggerMouse)
                    }
                    return
                }
                guard let self, !Task.isCancelled else { return }
                self.onCapture?(nil, "未检测到本次复制的新文本。请确认文字可以复制，或使用顶部菜单中的“翻译剪贴板”。", triggerMouse)
            }
        }
    }

    func stop() {
        cancelCapture()
        timer?.invalidate()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
