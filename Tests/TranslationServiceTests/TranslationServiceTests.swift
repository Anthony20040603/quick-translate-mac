import XCTest
import TranslationCore
@testable import QuickTranslate

private final class StubProtocol: URLProtocol {
    static var status = 200
    static var body = ""
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // Deliberately split UTF-8 across data deliveries.
        for byte in Self.body.utf8 { client?.urlProtocol(self, didLoad: Data([byte])) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class TranslationServiceTests: XCTestCase {
    private func run(body: String, status: Int = 200, model: String = "glm-4.7-flash") async throws -> String {
        StubProtocol.body = body
        StubProtocol.status = status
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        var output = ""
        var settings = ServiceSettings()
        settings.model = model
        if TranslationProtocol.isQwenMT(model) {
            settings.endpoint = "https://dashscope.aliyuncs.com/compatible-mode/v1"
        }
        try await TranslationService.translate(text: "Hello", settings: settings,
            key: "test-only-not-a-real-key", configuration: configuration) { output = $0 }
        return output
    }

    func testStreamSurvivesSplitUnicodeAndPreservesChunks() async throws {
        let stream = "data: {\"choices\":[{\"delta\":{\"content\":\"你好\"}}]}\n\n"
            + "data: {\"choices\":[{\"delta\":{\"content\":\"世界\"},\"finish_reason\":\"stop\"}]}\n\n"
            + "data: [DONE]\n\n"
        let result = try await run(body: stream)
        XCTAssertEqual(result, "你好世界")
    }

    func testHTTPErrorNeverDisplaysResponseSecrets() async {
        do {
            _ = try await run(body: "secret-echo-from-server", status: 401)
            XCTFail("Expected authentication failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("401"))
            XCTAssertFalse(error.localizedDescription.contains("secret-echo"))
        }
    }

    func testTruncatedStreamIsNotReportedAsSuccess() async {
        do {
            _ = try await run(body: "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n")
            XCTFail("Expected truncation failure")
        } catch { XCTAssertTrue(error.localizedDescription.contains("不完整")) }
    }

    func testEmptyStreamFails() async {
        do {
            _ = try await run(body: "data: [DONE]\n\n")
            XCTFail("Expected empty output failure")
        } catch { XCTAssertTrue(error.localizedDescription.contains("未返回译文")) }
    }

    func testLengthLimitFailsEvenWithDoneMarker() async {
        do {
            _ = try await run(body: "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"},\"finish_reason\":\"length\"}]}\n\ndata: [DONE]\n\n")
            XCTFail("Expected length limit failure")
        } catch { XCTAssertTrue(error.localizedDescription.contains("长度限制")) }
    }

    func testQwenPlusCumulativeStreamReplacesPreviousOutput() async throws {
        let fragments = ["I", "I didn't", "I didn't laugh", "I did not laugh."]
        let stream = try fragments.map { text in
            let data = try JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": text]]]])
            return "data: " + String(decoding: data, as: UTF8.self) + "\r\n\r\n"
        }.joined() + "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\r\n\r\ndata: [DONE]\r\n\r\n"
        let result = try await run(body: stream, model: "qwen-mt-plus")
        XCTAssertEqual(result, "I did not laugh.")
    }

    func testQwenFlashStillAppendsIncrementalStream() async throws {
        let stream = "data: {\"choices\":[{\"delta\":{\"content\":\"你好\"}}]}\n\n"
            + "data: {\"choices\":[{\"delta\":{\"content\":\"世界\"},\"finish_reason\":\"stop\"}]}\n\n"
            + "data: [DONE]\n\n"
        let result = try await run(body: stream, model: "qwen-mt-flash")
        XCTAssertEqual(result, "你好世界")
    }

    func testFreeTierStopGetsSpecificError() async {
        do {
            _ = try await run(body: #"{"error":{"code":"AllocationQuota.FreeTierOnly","message":"private-server-echo"}}"#,
                              status: 403, model: "qwen-mt-plus")
            XCTFail("Expected free tier exhaustion error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("免费额度"))
            XCTAssertFalse(error.localizedDescription.contains("private-server-echo"))
        }
    }
}
