import AppKit
import SwiftUI
import TranslationCore

@MainActor
private final class TranslationWindow: NSWindow {
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private var window: TranslationWindow?
    private var settingsWindow: NSWindow?
    private var sourceApp: NSRunningApplication?
    private var sizingDocumentID: UUID?
    private var lastContentHeight: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate()
            NSApp.terminate(nil)
            return
        }
        buildStatusMenu()
        buildApplicationMenu()
        model.showTranslation = { [weak self] in self?.openTranslation() }
        model.showCapturedTranslation = { [weak self] mouse in self?.presentTranslation(near: mouse) }
        model.showSettings = { [weak self] in self?.openSettings() }
        model.hideTranslation = { [weak self] in self?.hideTranslation() }
        model.pinChanged = { [weak self] pinned in self?.window?.level = pinned ? .floating : .normal }
        model.start()
        openTranslation()
    }

    private func buildStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            image.accessibilityDescription = "Quick Translate"
            item.button?.image = image
        } else {
            item.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Quick Translate")
        }
        item.button?.toolTip = "Quick Translate · ⌘CC"
        let menu = NSMenu()
        addItem("打开 Quick Translate", action: #selector(openTranslation), to: menu)
        addItem("翻译剪贴板", action: #selector(translateClipboard), to: menu)
        addItem("复制全部译文", action: #selector(copyTranslation), to: menu)
        menu.addItem(.separator())
        addItem("始终置顶", action: #selector(togglePin), to: menu)
        addDirections(to: menu)
        addItem("暂停 ⌘CC", action: #selector(togglePause), to: menu)
        addItem("设置…", action: #selector(openSettings), to: menu)
        menu.addItem(.separator())
        addItem("退出 Quick Translate", action: #selector(quit), to: menu)
        item.menu = menu
        statusItem = item
    }

    private func buildApplicationMenu() {
        let main = NSMenu()
        let application = appendMenu("Quick Translate", to: main)
        addItem("关于 Quick Translate", action: #selector(showAbout), to: application)
        application.addItem(.separator())
        addItem("设置…", action: #selector(openSettings), key: ",", to: application)
        application.addItem(.separator())
        application.addItem(withTitle: "隐藏 Quick Translate", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        application.addItem(.separator())
        addItem("退出 Quick Translate", action: #selector(quit), key: "q", to: application)

        let file = appendMenu("文件", to: main)
        addItem("打开翻译窗口", action: #selector(openTranslation), key: "0", to: file)
        file.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let edit = appendMenu("编辑", to: main)
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let copyAll = addItem("复制全部译文", action: #selector(copyTranslation), key: "c", to: edit)
        copyAll.keyEquivalentModifierMask = [.command, .shift]

        let translation = appendMenu("翻译", to: main)
        let paste = addItem("翻译剪贴板", action: #selector(translateClipboard), key: "v", to: translation)
        paste.keyEquivalentModifierMask = [.command, .shift]
        addItem("重新翻译", action: #selector(translateAgain), key: "r", to: translation)
        addItem("停止翻译", action: #selector(stopTranslation), key: ".", to: translation)
        translation.addItem(.separator())
        addDirections(to: translation)
        translation.addItem(.separator())
        addItem("暂停 ⌘CC", action: #selector(togglePause), to: translation)

        let windows = appendMenu("窗口", to: main)
        addItem("始终置顶", action: #selector(togglePin), to: windows)
        windows.addItem(.separator())
        windows.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windows
        NSApp.mainMenu = main
    }

    private func appendMenu(_ title: String, to parent: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        parent.addItem(item)
        return menu
    }

    private func addDirections(to menu: NSMenu) {
        let directions = appendMenu("翻译方向", to: menu)
        for direction in TranslationDirection.allCases {
            let item = addItem(direction.rawValue, action: #selector(changeDirection(_:)), to: directions)
            item.representedObject = direction.rawValue
        }
    }

    @discardableResult
    private func addItem(_ title: String, action: Selector, key: String = "", to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(togglePin): item.state = model.pinned ? .on : .off
        case #selector(togglePause): item.state = model.paused ? .on : .off
        case #selector(changeDirection(_:)):
            item.state = (item.representedObject as? String) == model.settings.direction.rawValue ? .on : .off
        case #selector(copyTranslation): return !model.translation.isEmpty
        case #selector(translateAgain): return !model.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isTranslating
        case #selector(stopTranslation): return model.isTranslating
        default: break
        }
        return true
    }

    @objc func openTranslation() {
        presentTranslation(near: nil)
    }

    private func presentTranslation(near triggerMouse: CGPoint?) {
        settingsWindow?.orderOut(nil)
        settingsWindow = nil
        let current = NSWorkspace.shared.frontmostApplication
        if current?.processIdentifier != ProcessInfo.processInfo.processIdentifier { sourceApp = current }
        if window == nil {
            let document = TranslationWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 152),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            document.title = "Quick Translate"
            document.titlebarAppearsTransparent = true
            document.titlebarSeparatorStyle = .line
            document.backgroundColor = .textBackgroundColor
            document.contentView = NSHostingView(rootView: TranslationView(model: model) { [weak self] height, id in
                self?.fitTranslationWindow(contentHeight: height, documentID: id)
            })
            document.minSize = NSSize(width: 320, height: 120)
            document.isReleasedWhenClosed = false
            document.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]
            document.delegate = self
            document.onEscape = { [weak model] in model?.close() }
            window = document
        }
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        if !window.styleMask.contains(.fullScreen) {
            if let triggerMouse {
                sizingDocumentID = nil
                lastContentHeight = 0
                position(window, near: triggerMouse, compact: true)
            } else if !window.isVisible {
                position(window, near: NSEvent.mouseLocation)
            }
        }
        window.level = model.pinned ? .floating : .normal
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if let text = findTextView(in: window.contentView) { window.makeFirstResponder(text) }
    }

    private func findTextView(in view: NSView?) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        for child in view?.subviews ?? [] {
            if let text = findTextView(in: child) { return text }
        }
        return nil
    }

    private func fitTranslationWindow(contentHeight: CGFloat, documentID: UUID) {
        lastContentHeight = contentHeight
        guard let window, !window.isMiniaturized, !window.inLiveResize,
              !window.styleMask.contains(.fullScreen),
              let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let titlebar = window.frame.height - window.contentRect(forFrameRect: window.frame).height
        let next = WindowLayout.frame(current: window.frame, visible: visible,
            contentHeight: contentHeight, titlebarHeight: titlebar, newDocument: sizingDocumentID != documentID)
        sizingDocumentID = documentID
        guard abs(next.height - window.frame.height) > 0.5 || abs(next.minY - window.frame.minY) > 0.5 else { return }
        window.setFrame(next, display: true, animate: false)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        fitTranslationWindow(contentHeight: lastContentHeight, documentID: model.documentID)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        sizingDocumentID = nil
        fitTranslationWindow(contentHeight: lastContentHeight, documentID: model.documentID)
    }

    private func position(_ window: NSWindow, near mouse: CGPoint, compact: Bool = false) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { window.center(); return }
        let size = NSSize(width: window.frame.width,
            height: compact ? min(WindowLayout.compactHeight, floor(frame.height * 0.4)) : window.frame.height)
        let positioned = WindowLayout.positionedFrame(near: mouse, size: size, visible: frame)
        window.setFrame(positioned, display: true)
    }

    private func hideTranslation() {
        let shouldReturnFocus = NSApp.isActive && settingsWindow?.isVisible != true
        window?.orderOut(nil)
        if shouldReturnFocus { sourceApp?.activate() }
    }

    @objc func openSettings() {
        model.hotkey.cancelCapture()
        window?.orderOut(nil)
        if settingsWindow == nil {
            let settings = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            settings.title = "Quick Translate 设置"
            let host = NSHostingView(rootView: SettingsView(model: model))
            settings.contentView = host
            settings.setContentSize(host.fittingSize)
            settings.isReleasedWhenClosed = false
            settings.delegate = self
            settingsWindow = settings
            settings.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === window { model.close(); return false }
        if sender === settingsWindow { settingsWindow = nil }
        return true
    }

    @objc private func togglePin() { model.togglePin() }
    @objc private func togglePause() {
        model.togglePause()
        statusItem?.button?.appearsDisabled = model.paused
    }
    @objc private func translateClipboard() { model.translateClipboard() }
    @objc private func translateAgain() { model.translate() }
    @objc private func stopTranslation() { model.stopTranslation() }
    @objc private func copyTranslation() { model.copyTranslation() }
    @objc private func changeDirection(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let direction = TranslationDirection(rawValue: raw) else { return }
        model.setDirection(direction)
    }
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Quick Translate",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        ])
    }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openTranslation(); return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model.cancel(); model.hotkey.stop() }
}

@main
struct QuickTranslateApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
