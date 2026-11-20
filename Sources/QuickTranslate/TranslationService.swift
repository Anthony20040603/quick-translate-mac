import Foundation
import TranslationCore

// Never forward the authorization header through a server redirect.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum TranslationService {
    @MainActor
    static func translate(text: String, settings: ServiceSettings, key: String,
                          configuration: URLSessionConfiguration = .ephemeral,
                          onUpdate: @escaping (String) -> Void) async throws {
        let url = try TranslationProtocol.endpoint(settings.endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try TranslationProtocol.request(text: text,
            target: settings.direction.target(for: text), model: settings.model)

        configuration.timeoutIntervalForResource = 180
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw TranslationFailure.message("翻译服务未返回有效的 HTTP 响应。")
        }
        guard response.statusCode == 200 else {
            var errorData = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                errorData.append(byte)
                if errorData.count >= 32_768 { break }
            }
            throw TranslationProtocol.httpError(statusCode: response.statusCode, body: errorData)
        }
        var decoder = SSEDecoder()
        var receivedText = false
        var finished = false
        var finishReason: String?
        var output = ""
        let cumulative = TranslationProtocol.usesCumulativeOutput(settings.model)
        func receive(_ payload: String) throws {
            let event = try TranslationProtocol.parseEvent(payload)
            if !event.text.isEmpty {
                receivedText = true
                output = cumulative ? event.text : output + event.text
                onUpdate(output)
            }
            if let reason = event.finishReason { finishReason = reason }
            if event.done { finished = true }
        }
        // AsyncBytes.lines omits blank lines on some Foundation versions. SSE needs
        // those separators, so frame lines from bytes before decoding UTF-8.
        var lineBytes = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            if byte == 10 {
                if lineBytes.last == 13 { lineBytes.removeLast() }
                let line = String(decoding: lineBytes, as: UTF8.self)
                lineBytes.removeAll(keepingCapacity: true)
                if let payload = decoder.feed(line) { try receive(payload) }
            } else {
                lineBytes.append(byte)
                guard lineBytes.count <= 1_048_576 else {
                    throw TranslationFailure.message("翻译服务返回的数据过大，请重试。")
                }
            }
            if finished { break }
        }
        if !lineBytes.isEmpty, let payload = decoder.feed(String(decoding: lineBytes, as: UTF8.self)) {
            try receive(payload)
        }
        if let payload = decoder.finish() { try receive(payload) }
        try Task.checkCancellation()
        guard receivedText else {
            throw TranslationFailure.message("服务未返回译文，请检查模型是否支持此接口，或重试。")
        }
        if finishReason == "length" {
            throw TranslationFailure.message("译文达到模型长度限制，当前显示的是部分结果。请拆分原文后重试。")
        }
        if let reason = finishReason, reason != "stop" {
            throw TranslationFailure.message("服务提前结束了翻译，当前结果可能不完整。")
        }
        guard finished || finishReason == "stop" else {
            throw TranslationFailure.message("连接提前结束，当前译文可能不完整，请重试。")
        }
    }
}
