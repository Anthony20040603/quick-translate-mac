import SwiftUI
import TranslationCore

private let accent = Color(red: 0.02, green: 0.48, blue: 0.51)

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var endpoint = ""
    @State private var modelName = ""
    @State private var secret = ""
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "slider.horizontal.3").font(.title2).foregroundStyle(accent)
                Text("设置").font(.title2.bold())
                Spacer()
                Button("返回翻译") { model.showTranslation?() }
                Text("⌘ C C").font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label(model.accessibilityGranted ? "快捷键权限已开启" : "快捷键需要辅助功能权限",
                          systemImage: model.accessibilityGranted ? "checkmark.circle.fill" : "keyboard")
                        .foregroundStyle(model.accessibilityGranted ? .green : .primary)
                    Text("在系统设置 → 隐私与安全性 → 辅助功能中，允许 Quick Translate。按住 Command 连按两次 C 即可翻译，普通复制保持原样。")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("打开授权设置") { model.hotkey.requestPermission(); openAccessibilitySettings() }
                        Button("重新检查") { model.hotkey.refreshPermission() }
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            } label: { Text("快捷键") }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(TranslationProtocol.isQwenMT(modelName) ? "阿里云百炼 · Qwen-MT" : "智谱 GLM")
                            .font(.headline)
                        Spacer()
                        Menu("切换服务") {
                            Button("阿里云百炼 · Qwen-MT Plus") {
                                endpoint = "https://dashscope.aliyuncs.com/compatible-mode/v1"
                                modelName = "qwen-mt-plus"
                                secret = ""
                                message = nil
                            }
                            Button("智谱 · GLM-4.7-Flash") { resetGLM() }
                        }.fixedSize()
                    }
                    field("接口地址") { TextField("HTTPS 接口地址", text: $endpoint).textFieldStyle(.roundedBorder) }
                    field("模型") { TextField("glm-4.7-flash", text: $modelName).textFieldStyle(.roundedBorder) }
                    field("API Key") { SecureField("首次填写；留空保留此接口已保存的密钥", text: $secret).textFieldStyle(.roundedBorder) }
                    Text("密钥仅保存在本机钥匙串，并与接口地址绑定。所选原文会发送到此翻译服务；应用不保存翻译历史。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if TranslationProtocol.isQwenMT(modelName) {
                        Text("请填写此业务空间、此地域的百炼 API Key。百炼按量计费，免费额度和有效期以控制台为准；可在控制台开启“免费额度用完即停”。")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button("恢复 GLM 默认地址") { resetGLM() }
                        Spacer()
                        Button("保存设置") {
                            do {
                                try model.saveSettings(endpoint: endpoint, model: modelName, key: secret)
                                endpoint = model.settings.endpoint
                                secret = ""
                                failed = false
                                message = "设置已保存。返回翻译窗口即可使用。"
                            } catch { failed = true; message = error.localizedDescription }
                        }.buttonStyle(.borderedProminent).tint(accent)
                    }
                    if let message {
                        Text(message).font(.callout).foregroundStyle(failed ? .red : .green)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(8)
            } label: { Text("翻译服务") }
            Text("Quick Translate · 0.3.3").font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 590).fixedSize(horizontal: true, vertical: true)
        .onAppear { endpoint = model.settings.endpoint; modelName = model.settings.model }
        .onDisappear { secret = "" }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); content() }
    }

    private func resetGLM() {
        endpoint = ServiceSettings().endpoint
        modelName = ServiceSettings().model
        secret = ""
        message = nil
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
