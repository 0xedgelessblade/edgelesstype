import XCTest
@testable import EdgelessTypeCore

final class CloudModelIdentityTests: XCTestCase {
    func testModelLabelsFollowRequestConfiguration() throws {
        XCTAssertEqual(CloudProvider.openai.model(for: .correction), "gpt-6-luna")
        XCTAssertEqual(CloudProvider.openai.model(for: .translation), "gpt-6-luna")
        for provider in CloudProvider.allCases {
            for purpose in [CloudPurpose.correction, .translation] {
                let request = try CloudWire.request(ChatDraft.polish(text: "fixture"), provider: provider, purpose: purpose, key: "fixture")
                let payload = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                XCTAssertTrue(provider.modelsDescription.contains(provider.model(for: purpose)))
                if provider == .google { XCTAssertTrue(request.url!.path.contains(provider.model(for: purpose))) }
                else { XCTAssertEqual(payload["model"] as? String, provider.model(for: purpose)) }
            }
        }
    }
    func testGoogleCorrectionModelIsTheUsersChoiceAndDefaultsToTheFasterOne() throws {
        XCTAssertEqual(CloudProvider.google.correctionModels, ["gemini-3.6-flash", "gemini-3.8-flash"])
        XCTAssertEqual(CloudProvider.google.model(for: .correction), "gemini-3.6-flash")
        XCTAssertEqual(CloudProvider.google.model(for: .translation), "gemini-3.8-flash")
        XCTAssertEqual(CloudPreferences(provider: .google).correctionModel(for: .google), "gemini-3.6-flash")
        let chosen = CloudPreferences(provider: .google, correctionModels: ["google": "gemini-3.8-flash"])
        XCTAssertEqual(chosen.correctionModel(for: .google), "gemini-3.8-flash")
        let draft = try ContextCorrection.draft(text: "fixture", entries: [], model: chosen.correctionModel(for: .google))
        XCTAssertTrue(try CloudWire.request(draft, provider: .google, purpose: .correction, key: "fixture").url!.path.contains("gemini-3.8-flash:generateContent"))
        let fallback = try ContextCorrection.draft(text: "fixture", entries: [], model: "gemini-3.6-flash")
        XCTAssertTrue(try CloudWire.request(fallback, provider: .google, purpose: .correction, key: "fixture").url!.path.contains("gemini-3.6-flash:generateContent"))
        // The choice is for correction only: the same draft sent as a translation keeps the fixed model.
        XCTAssertTrue(try CloudWire.request(fallback, provider: .google, purpose: .translation, key: "fixture").url!.path.contains("gemini-3.8-flash:generateContent"))
    }
    func testUnknownOrForeignModelChoiceNeverReachesTheRequest() throws {
        let stale = CloudPreferences(provider: .google, correctionModels: ["google": "retired-model", "openai": "gemini-3.8-flash"])
        XCTAssertEqual(stale.correctionModel(for: .google), "gemini-3.6-flash")
        XCTAssertEqual(stale.correctionModel(for: .openai), "gpt-6-luna")
        let draft = try ContextCorrection.draft(text: "fixture", entries: [], model: "retired-model")
        XCTAssertTrue(try CloudWire.request(draft, provider: .google, purpose: .correction, key: "fixture").url!.path.contains("gemini-3.6-flash:generateContent"))
        for provider in CloudProvider.allCases where provider != .google {
            XCTAssertEqual(provider.correctionModels, [provider.model(for: .correction)])
            XCTAssertNil(provider.correctionModelHint(provider.model(for: .correction)))
        }
        XCTAssertEqual(CloudProvider.google.correctionModelHint("gemini-3.6-flash"), "較快")
        XCTAssertEqual(CloudProvider.google.correctionModelHint("gemini-3.8-flash"), "較準")
    }
    func testSettingsSavedBeforeTheModelChoiceStillLoadAndRoundTrip() throws {
        let legacy = try JSONDecoder().decode(CloudPreferences.self, from: Data(#"{"provider":"google"}"#.utf8))
        XCTAssertEqual(legacy, CloudPreferences(provider: .google))
        let chosen = CloudPreferences(provider: .google, correctionModels: ["google": "gemini-3.8-flash"])
        XCTAssertEqual(try JSONDecoder().decode(CloudPreferences.self, from: JSONEncoder().encode(chosen)), chosen)
    }
    func testReportedModelNeverFallsBackToRequestedName() throws {
        for provider in CloudProvider.allCases {
            let field = provider == .google ? "modelVersion" : "model"
            let data = try JSONSerialization.data(withJSONObject: [field:"served-model-snapshot"])
            XCTAssertEqual(CloudWire.reportedModel(data, provider: provider), "served-model-snapshot")
            XCTAssertNil(CloudWire.reportedModel(Data("{}".utf8), provider: provider))
        }
    }
    func testMalformedModelMetadataIsNotDisplayed() throws {
        for value: Any in ["model\nextra text", String(repeating:"x",count:121), 123, NSNull()] {
            let data = try JSONSerialization.data(withJSONObject: ["model":value])
            XCTAssertNil(CloudWire.reportedModel(data, provider: .openai))
        }
    }
    func testOnlySuccessfulParsedRepliesPublishModelIdentity() throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ModelIdentityFixture.self]
        let client = CloudClient(configuration: config)
        ModelIdentityFixture.status = 200
        var seen: String?
        let text = try client.complete(ChatDraft.polish(text:"fixture"), provider:.openai, purpose:.correction, key:"fixture", onModel:{seen=$0})
        XCTAssertEqual(text,"OK")
        XCTAssertEqual(seen,"gpt-6-luna-test-snapshot")
        ModelIdentityFixture.status = 403
        var called = false
        XCTAssertThrowsError(try client.complete(ChatDraft.polish(text:"fixture"),provider:.openai,purpose:.correction,key:"fixture",onModel:{_ in called=true}))
        XCTAssertFalse(called)
    }
}
private final class ModelIdentityFixture: URLProtocol {
    static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response=HTTPURLResponse(url:request.url!,statusCode:Self.status,httpVersion:"HTTP/1.1",headerFields:[:])!
        let data=Data(#"{"model":"gpt-6-luna-test-snapshot","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"OK"}]}]}"#.utf8)
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
