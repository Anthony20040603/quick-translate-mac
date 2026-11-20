import AppKit
import SwiftUI
import TranslationCore

@MainActor
final class AppModel: ObservableObject {
    @Published var source = ""
    @Published var translation = ""
    @Published var status = "选中文字，按住 ⌘ 连按两次 C"
    @Published var error: String?
    @Published var isTranslating = false
    @Published var documentID = UUID()
    @Published var accessibilityGranted = AXIsProcessTrusted()
    @Published var paused = false
    @Published var settings = ServiceSettings.load()
    @Published var pinned = UserDefaults.standard.bool(forKey: "alwaysOnTop")
    var showTranslation: (() -> Void)?
    var showCapturedTranslation: ((CGPoint) -> Void)?
    var showSettings: (() -> Void)?
    var hideTranslation: (() -> Void)?
    var pinChanged: ((Bool) -> Void)?
    let hotkey = ClipboardHotkey()
    private var request: Task<Void, Never>?
    private var generation = UUID()

    var documentText: String {
        if !translation.isEmpty {
            return translation + (error.map { "\n\n" + $0 } ?? "")
        }
        if let error { return error }
        if isTranslating { return "正在翻译…" }
        if status.hasPrefix("已停止") { return "已停止翻译。" }
        if !accessibilityGranted { return "请在 Quick Translate → 设置中开启快捷键权限。" }
        return "选中文字，按住 ⌘ 连按两次 C。"
    }

    func start() {
        hotkey.onPermissionChange = { [weak self] trusted in self?.accessibilityGranted = trusted }
        hotkey.onCapture = { [weak self] text, message, mouse in
            guard let self else { return }
            self.cancel()
            self.source = text ?? ""
            self.documentID = UUID()
            self.translation = ""
            self.error = message
            self.status = text == nil ? "未取得文字" : "已取得选中文字"
            self.showCapturedTranslation?(mouse)
            if text != nil { self.translate() }
        }
        hotkey.start()
    }

    func togglePause() {
        paused.toggle()
        hotkey.setPaused(paused)
    }

    func togglePin() {
        pinned.toggle()
        UserDefaults.standard.set(pinned, forKey: "alwaysOnTop")
        pinChanged?(pinned)
    }

    func translateClipboard() {
        hotkey.cancelCapture()
        cancel()
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        source = text ?? ""
        translation = ""
        error = nil
        documentID = UUID()
        showTranslation?()
        guard let text, !text.isEmpty else { error = "剪贴板中没有可以翻译的文字。"; return }
        translate()
    }

    func cancel() {
        generation = UUID()
        request?.cancel()
        request = nil
        isTranslating = false
    }

    func stopTranslation() { cancel(); status = "已停止，保留当前译文" }

    func close() {
        cancel()
        hideTranslation?()
    }

    func translate() {
        cancel()
        documentID = UUID()
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        error = nil
        guard !text.isEmpty else { error = "请先选中文字按 ⌘CC，或使用顶部菜单中的“翻译剪贴板”。"; return }
        guard text.count <= 30_000 else { error = "单次最多翻译 30,000 个字符，请拆分后重试。"; return }
        let snapshot = settings
        let key: String
        do {
            let endpoint = try TranslationProtocol.endpoint(snapshot.endpoint).absoluteString
            guard let saved = try KeychainStore.read(endpoint: endpoint), !saved.isEmpty else {
                error = "尚未设置此接口的 API Key，请打开 Quick Translate → 设置。"
                status = "需要配置翻译服务"
                return
            }
            key = saved
        } catch { self.error = error.localizedDescription; return }
        let id = UUID()
        generation = id
        translation = ""
        isTranslating = true
        status = "正在翻译为\(snapshot.direction.target(for: text))…"
        request = Task { [weak self] in
            guard let self else { return }
            do {
                try await TranslationService.translate(text: text, settings: snapshot, key: key) { [weak self] output in
                    guard let self, self.generation == id else { return }
                    self.translation = output
                }
                guard self.generation == id else { return }
                self.status = "翻译完成 · \(snapshot.model) · \(text.count) 字符"
            } catch {
                guard self.generation == id, !Task.isCancelled else { return }
                if let urlError = error as? URLError {
                    self.error = urlError.code == .timedOut ? "请求超时，请检查网络后重试。" : "无法连接翻译服务，请检查网络和接口地址。"
                } else { self.error = error.localizedDescription }
                self.status = "翻译未完成"
            }
            guard self.generation == id else { return }
            self.isTranslating = false
            self.request = nil
        }
    }

    func copyTranslation() {
        guard !translation.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translation, forType: .string)
        status = "译文已复制"
    }

    func saveSettings(endpoint: String, model: String, key: String) throws {
        let normalized = try TranslationProtocol.endpoint(endpoint).absoluteString
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw TranslationFailure.message("请填写模型名称。") }
        if TranslationProtocol.isQwenMT(model), URL(string: normalized)?.host == "open.bigmodel.cn" {
            throw TranslationFailure.message("Qwen-MT 需要使用百炼接口地址，请先选择阿里云百炼预设。")
        }
        cancel()
        let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !secret.isEmpty { try KeychainStore.save(secret, endpoint: normalized) }
        var updated = settings
        updated.endpoint = normalized
        updated.model = model
        try updated.save()
        settings = updated
    }

    func setDirection(_ direction: TranslationDirection) {
        if isTranslating { stopTranslation() }
        settings.direction = direction
        try? settings.save()
    }
}
