import XCTest
@testable import OpenTypelessCore

final class CloudProviderTests: XCTestCase {
    func testCorrectionWaitsPastFormerEightSecondDeadline() throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        FixtureProtocol.status = 200
        FixtureProtocol.body = Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"long correction completed"}]}]}"#.utf8)
        FixtureProtocol.delay = 9
        defer { FixtureProtocol.delay = 0 }
        let body = try ContextCorrection.draft(text: "long fixture", entries: [], model: "fixture", timeout: CloudProvider.openai.correctionTimeoutSeconds)
        let result = try CloudClient(configuration: config).complete(body, provider: .openai, purpose: .correction, key: "fixture")
        XCTAssertEqual(result, "long correction completed")
    }

    func testAllCorrectionProvidersHaveNoShortDeadlineButTranslationKeepsItsTimeout() throws {
        for provider in CloudProvider.allCases {
            XCTAssertFalse(provider.correctionTimeoutSeconds.isFinite)
            let body = try ContextCorrection.draft(text: "測試", entries: [], model: "fixture", timeout: provider.correctionTimeoutSeconds)
            XCTAssertFalse(body.timeoutSeconds.isFinite)
            let request = try CloudWire.request(body, provider: provider, purpose: .correction, key: "fixture")
            XCTAssertEqual(request.timeoutInterval, TimeInterval(Int32.max))
            let translation = try CloudWire.request(ChatDraft.translate(text: "測試", timeout: 25), provider: provider, purpose: .translation, key: "fixture")
            XCTAssertEqual(translation.timeoutInterval, 25)
        }
    }

    func testEachProviderUsesItsOwnHostAndHeaderWithoutAudioOrKeyInURL() throws {
        for provider in CloudProvider.allCases {
            let body = try ContextCorrection.draft(text: "check 麥克風全線", entries: [], model: "ignored")
            let request = try CloudWire.request(body, provider: provider, purpose: .correction, key: "unit-test-key")
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertNil(request.url?.query)
            XCTAssertFalse(request.url!.absoluteString.contains("unit-test-key"))
            let data = String(decoding: request.httpBody!, as: UTF8.self)
            XCTAssertFalse(data.contains("unit-test-key"))
            XCTAssertFalse(data.contains("input_audio")); XCTAssertFalse(data.contains("inlineData"))
            switch provider {
            case .xai, .openai: XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-key")
            case .google: XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "unit-test-key")
            case .anthropic:
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "unit-test-key")
                XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            }
        }
    }

    func testPlainCorrectionAndTranslationPayloads() throws {
        for provider in CloudProvider.allCases {
            let correction = try ContextCorrection.draft(text: "人定聖天", entries: [], model: "ignored", timeout: provider.correctionTimeoutSeconds)
            let c = try CloudWire.request(correction, provider: provider, purpose: .correction, key: "fixture")
            let t = try CloudWire.request(ChatDraft.translate(text: "你好"), provider: provider, purpose: .translation, key: "fixture")
            let cj = try JSONSerialization.jsonObject(with: c.httpBody!) as! [String: Any]
            let tj = try JSONSerialization.jsonObject(with: t.httpBody!) as! [String: Any]
            if provider == .xai {
                XCTAssertEqual(cj["model"] as? String, "grok-4.3")
                XCTAssertEqual(tj["model"] as? String, "grok-4.7")
                XCTAssertEqual(cj["reasoning_effort"] as? String, "none")
                XCTAssertEqual(tj["reasoning_effort"] as? String, "high")
                XCTAssertNil(cj["response_format"]); XCTAssertNil(tj["response_format"])
            } else if provider == .openai {
                XCTAssertEqual(cj["model"] as? String, "gpt-6-luna")
                XCTAssertEqual(tj["model"] as? String, "gpt-6-luna")
                XCTAssertEqual((cj["reasoning"] as? [String: Any])?["effort"] as? String, "low")
                XCTAssertEqual((tj["reasoning"] as? [String: Any])?["effort"] as? String, "none")
                XCTAssertEqual(c.timeoutInterval, TimeInterval(Int32.max))
                XCTAssertEqual(cj["store"] as? Bool, false)
                XCTAssertNil(cj["text"]); XCTAssertNil(tj["text"])
                XCTAssertNil(cj["temperature"])
            } else if provider == .anthropic {
                // Both tasks must disable thinking, including translation drafts
                // that carry a high reasoning hint for other providers.
                for request in [cj, tj] {
                    XCTAssertEqual(request["model"] as? String, "claude-haiku-5-5")
                    XCTAssertEqual((request["thinking"] as? [String: Any])?["type"] as? String, "disabled")
                    XCTAssertEqual((request["output_config"] as? [String: Any])?["effort"] as? String, "low")
                    XCTAssertNil(request["reasoning_effort"])
                    XCTAssertNil(request["temperature"])
                }
                XCTAssertNil((cj["output_config"] as? [String: Any])?["format"])
                XCTAssertNil((tj["output_config"] as? [String: Any])?["format"])
                XCTAssertNil(cj["temperature"])
            } else {
                XCTAssertNil((cj["generationConfig"] as? [String: Any])?["responseMimeType"])
                XCTAssertNil((tj["generationConfig"] as? [String: Any])?["responseMimeType"])
            }
        }
    }

    func testAllStructuredProvidersAllowNullablePunctuation() throws {
        for provider in [CloudProvider.openai, .anthropic, .google] {
            var draft = try ContextCorrection.draft(text: "你好", entries: [], model: "fixture")
            draft.jsonOutput = true // Explicit legacy adapter fixture; normal correction is plain text.
            let request = try CloudWire.request(draft, provider: provider, purpose: .correction, key: "fixture")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let schema: [String: Any]
            switch provider {
            case .openai:
                let format = (body["text"] as! [String: Any])["format"] as! [String: Any]
                schema = format["schema"] as! [String: Any]
            case .anthropic:
                let format = (body["output_config"] as! [String: Any])["format"] as! [String: Any]
                schema = format["schema"] as! [String: Any]
            default:
                schema = (body["generationConfig"] as! [String: Any])["responseJsonSchema"] as! [String: Any]
            }
            XCTAssertEqual(schema["required"] as? [String], ["corrections", "punctuated"])
            let properties = schema["properties"] as! [String: Any]
            XCTAssertEqual((properties["punctuated"] as! [String: Any])["type"] as? [String], ["string", "null"])
        }
        XCTAssertEqual(ContextCorrection.validatedApply(response: #"{"corrections":[],"punctuated":null}"#, to: "Hermes", entries: []), "Hermes")
    }

    func testProviderResponsesFeedSameConservativeCorrection() throws {
        let result = #"{"corrections":[{"from":"人定聖天","to":"人定勝天","occurrence":1}],"punctuated":"人定勝天， check the settings。"}"#
        for provider in CloudProvider.allCases {
            let fixture: [String: Any]
            switch provider {
            case .xai: fixture = ["choices": [["finish_reason": "stop", "message": ["content": result]]]]
            case .openai: fixture = ["status": "completed", "output": [["type": "reasoning"], ["type": "message", "content": [["type": "output_text", "text": result]]]]]
            case .anthropic: fixture = ["stop_reason": "end_turn", "content": [["type": "thinking", "thinking": "ignored"], ["type": "text", "text": result]]]
            case .google: fixture = ["candidates": [["finishReason": "STOP", "content": ["parts": [["thought": true, "text": "ignored"], ["text": result]]]]]]
            }
            let text = try CloudWire.parse(JSONSerialization.data(withJSONObject: fixture), status: 200, provider: provider)
            XCTAssertEqual(text, result)
            XCTAssertEqual(ContextCorrection.apply(response: text, to: "人定聖天 check the settings", entries: []), "人定勝天， check the settings。")
        }
    }

    func testTruncatedRefusedAndEmptyResponsesNeverPaste() throws {
        let cases: [(CloudProvider, [String: Any])] = [
            (.xai, ["choices": [["finish_reason": "length", "message": ["content": "partial"]]]]),
            (.openai, ["status": "incomplete", "output": []]),
            (.openai, ["status": "completed", "output": [["type": "message", "content": [["type": "refusal", "refusal": "no"]]]]]),
            (.anthropic, ["stop_reason": "max_tokens", "content": [["type": "text", "text": "partial"]]]),
            (.google, ["candidates": [["finishReason": "SAFETY", "content": ["parts": [["text": "partial"]]]]]])
        ]
        for (provider, value) in cases {
            XCTAssertThrowsError(try CloudWire.parse(JSONSerialization.data(withJSONObject: value), status: 200, provider: provider))
        }
        for provider in CloudProvider.allCases {
            XCTAssertThrowsError(try CloudWire.parse(Data("{}".utf8), status: 200, provider: provider))
            XCTAssertThrowsError(try CloudWire.parse(Data("not-json".utf8), status: 200, provider: provider))
        }
    }

    func testErrorsNeverEchoProviderResponseOrSecret() {
        for provider in CloudProvider.allCases {
            for status in [400, 401, 403, 429, 500] {
                XCTAssertThrowsError(try CloudWire.parse(Data("unit-test-sensitive-response".utf8), status: status, provider: provider)) { error in
                    XCTAssertFalse(error.localizedDescription.contains("unit-test-sensitive-response"))
                }
            }
            XCTAssertThrowsError(try CloudWire.request(ChatDraft.polish(text: "test"), provider: provider, purpose: .correction, key: "\nInjected: value"))
        }
    }

    func testRealClientTransportUsesAdapterAndSanitizesErrors() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        let client = CloudClient(configuration: configuration)
        FixtureProtocol.status = 200
        for provider in CloudProvider.allCases {
            let fixture: [String: Any]
            switch provider {
            case .xai: fixture = ["choices": [["finish_reason": "stop", "message": ["content": "OK"]]]]
            case .openai: fixture = ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": "OK"]]]]]
            case .anthropic: fixture = ["stop_reason": "end_turn", "content": [["type": "text", "text": "OK"]]]
            case .google: fixture = ["candidates": [["finishReason": "STOP", "content": ["parts": [["text": "OK"]]]]]]
            }
            FixtureProtocol.body = try JSONSerialization.data(withJSONObject: fixture)
            XCTAssertEqual(try client.complete(ChatDraft.polish(text: "Connection test."), provider: provider, purpose: .correction, key: "fixture"), "OK")
        }
        FixtureProtocol.status = 401
        FixtureProtocol.body = Data("never-show-this-body".utf8)
        XCTAssertThrowsError(try client.complete(ChatDraft.polish(text: "test"), provider: .openai, purpose: .correction, key: "fixture")) { error in
            XCTAssertEqual(error as? CloudError, .authentication)
            XCTAssertFalse(error.localizedDescription.contains("never-show-this-body"))
        }
    }

    func testFourKeysSurviveSwitchingAndDeletingOne() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = SecretLocations(keyringDirectory: root.appendingPathComponent("keys"), keyringFile: root.appendingPathComponent("keys/ring.json"), storeFile: root.appendingPathComponent("private/store.encrypted.json"))
        for provider in CloudProvider.allCases {
            try SecretStore(locations: locations, recordName: provider.rawValue).save(secret: Data("fixture-\(provider.rawValue)".utf8))
        }
        for provider in CloudProvider.allCases {
            XCTAssertEqual(try SecretStore(locations: locations, recordName: provider.rawValue).readSecret(), Data("fixture-\(provider.rawValue)".utf8))
        }
        let cipher = try String(contentsOf: locations.storeFile, encoding: .utf8)
        XCTAssertFalse(cipher.contains("fixture-")); XCTAssertFalse(cipher.contains("openai"))
        try SecretStore(locations: locations, recordName: "google").delete()
        XCTAssertThrowsError(try SecretStore(locations: locations, recordName: "google").readSecret())
        XCTAssertEqual(try SecretStore(locations: locations).readSecret(), Data("fixture-xai".utf8))
        XCTAssertTrue(try SecretStore(locations: locations, recordName: "openai").verify())
        XCTAssertTrue(try SecretStore(locations: locations, recordName: "anthropic").verify())
        let settings = CloudPreferencesStore(url: root.appendingPathComponent("cloud.json"))
        for provider in CloudProvider.allCases {
            try settings.save(CloudPreferences(provider: provider))
            XCTAssertEqual(try settings.load().provider, provider)
        }
        XCTAssertFalse(try String(contentsOf: settings.url, encoding: .utf8).contains("fixture-"))
    }

    func testMissingKeyTableDoesNotPretendDeletionSucceeded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = SecretLocations(keyringDirectory: root.appendingPathComponent("keys"), keyringFile: root.appendingPathComponent("keys/ring.json"), storeFile: root.appendingPathComponent("private/store.encrypted.json"))
        let store = SecretStore(locations: locations)
        try store.save(secret: Data("fixture".utf8))
        let before = try Data(contentsOf: locations.storeFile)
        try FileManager.default.removeItem(at: locations.keyringFile)
        XCTAssertThrowsError(try store.delete())
        XCTAssertEqual(try Data(contentsOf: locations.storeFile), before)
    }

    func testCorruptEncryptedStoreIsNotOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = SecretLocations(keyringDirectory: root.appendingPathComponent("keys"), keyringFile: root.appendingPathComponent("keys/ring.json"), storeFile: root.appendingPathComponent("private/store.encrypted.json"))
        let store = SecretStore(locations: locations)
        try store.save(secret: Data("fixture".utf8))
        let corrupt = Data("damaged encrypted file".utf8)
        try corrupt.write(to: locations.storeFile)
        XCTAssertThrowsError(try SecretStore(locations: locations, recordName: "openai").save(secret: Data("another-fixture".utf8)))
        XCTAssertEqual(try Data(contentsOf: locations.storeFile), corrupt)
    }
}

private final class FixtureProtocol: URLProtocol {
    static var delay: TimeInterval = 0
    private var delayed: DispatchWorkItem?
    static var status = 200
    static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: [:])!
        let data = Self.body
        let deliver = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        delayed = deliver
        if Self.delay > 0 { DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay, execute: deliver) }
        else { deliver.perform() }
    }
    override func stopLoading() { delayed?.cancel() }
}
