import AppKit
import Foundation
import Testing
@testable import KopyApp

@MainActor
@Suite("Direct test licensing", .serialized)
struct LicenseTests {
    private let now = Date(timeIntervalSince1970: 1_795_000_000)

    private func configuration() throws -> LicenseConfiguration { try LicenseConfiguration(productID: "pdt_fixture") }

    private func credential(validatedAt: Date? = nil) -> LicenseCredential {
        LicenseCredential(key: "fixture-license", instanceID: "lki_fixture", productID: "pdt_fixture",
                          environment: "test", lastValidatedAt: validatedAt ?? now)
    }

    @Test("Offline grace ends at 30 days and rejects clock reversal or product mismatch")
    func boundedOfflinePolicy() throws {
        let config = try configuration()
        let record = credential()
        #expect(LicensePolicy.offlineStatus(record, configuration: config, now: now, allowed: true).permitsUse)
        #expect(!LicensePolicy.offlineStatus(record, configuration: config, now: now - 1, allowed: true).permitsUse)
        #expect(!LicensePolicy.offlineStatus(record, configuration: config,
                                            now: now + LicensePolicy.offlineInterval, allowed: true).permitsUse)
        #expect(!LicensePolicy.offlineStatus(record, configuration: config, now: now, allowed: false).permitsUse)
        let other = try LicenseConfiguration(productID: "pdt_other")
        #expect(!LicensePolicy.offlineStatus(record, configuration: other,
                                            now: now, allowed: true).permitsUse)
    }

    @Test("Activation is bound to Kopy, validates its instance, and writes no merchant authorization header")
    func activationWireAndPersistence() async throws {
        let (service, store) = try fixtures([
            .init(body: #"{"id":"lki_fixture","product":{"product_id":"pdt_fixture"}}"#),
            .init(body: #"{"valid":true}"#)
        ])
        let controller = LicenseController(configuration: try configuration(), client: service, store: store, now: { now })
        await controller.activate("  fixture-license  ")
        #expect(controller.status == .active)
        #expect(store.value?.instanceID == "lki_fixture")
        #expect(store.value?.lastValidatedAt == now)
        let requests = LicenseURLProtocol.responses.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        #expect(requests.allSatisfy { $0.url?.host == "test.dodopayments.com" })
        let validation = try #require(requests.last?.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: validation) as? [String: String])
        #expect(body["license_key_instance_id"] == "lki_fixture")
    }

    @Test("Another product cannot activate Kopy and the mistaken remote activation is released")
    func wrongProduct() async throws {
        let (service, store) = try fixtures([
            .init(body: #"{"id":"lki_other","product":{"product_id":"pdt_other"}}"#),
            .init(status: 204)
        ])
        let controller = LicenseController(configuration: try configuration(), client: service, store: store)
        await controller.activate("fixture-license")
        #expect(controller.issue == .wrongProduct)
        #expect(!controller.status.permitsUse)
        #expect(store.value == nil)
        #expect(LicenseURLProtocol.responses.requests.last?.url?.path == "/licenses/deactivate")
    }

    @Test("A relaunch validates the stored activation without consuming a second activation")
    func restoration() async throws {
        let (service, store) = try fixtures([.init(body: #"{"valid":true}"#)])
        store.value = credential(validatedAt: now - 100)
        let controller = LicenseController(configuration: try configuration(), client: service, store: store, now: { now })
        await controller.restore()
        #expect(controller.status == .active)
        #expect(LicenseURLProtocol.responses.requests.map { $0.url?.path } == ["/licenses/validate"])
    }

    @Test("Only connection failures earn offline grace", arguments: [LicenseIssue.connection, .provider, .invalidKey, .malformed])
    func errorPolicy(_ failure: LicenseIssue) async throws {
        let response: LicenseURLProtocol.Response
        switch failure {
        case .connection: response = .init(error: .notConnectedToInternet)
        case .provider: response = .init(status: 500)
        case .invalidKey: response = .init(body: #"{"valid":false}"#)
        default: response = .init(body: #"{"unexpected":true}"#)
        }
        let (service, store) = try fixtures([response])
        store.value = credential(validatedAt: now - 100)
        let controller = LicenseController(configuration: try configuration(), client: service, store: store, now: { now })
        await controller.restore()
        #expect(controller.status.permitsUse == (failure == .connection))
        #expect(controller.issue == failure)
        #expect(store.offlineAllowed == (failure == .connection))
    }

    @Test("An expired or previously rejected cache never allows offline use")
    func rejectedCache() async throws {
        let (service, store) = try fixtures([.init(error: .notConnectedToInternet)])
        store.value = credential(validatedAt: now - LicensePolicy.offlineInterval - 1)
        let controller = LicenseController(configuration: try configuration(), client: service, store: store, now: { now })
        await controller.restore()
        #expect(!controller.status.permitsUse)
        LicenseURLProtocol.responses.reset([.init(error: .notConnectedToInternet)])
        store.value = credential()
        store.offlineAllowed = false
        let rejected = LicenseController(configuration: try configuration(), client: service, store: store, now: { now })
        await rejected.restore()
        #expect(!rejected.status.permitsUse)
    }

    @Test("Failed deactivation keeps the current licence, and a successful one removes it")
    func deactivation() async throws {
        let (service, store) = try fixtures([.init(body: #"{"valid":true}"#), .init(error: .notConnectedToInternet), .init(status: 204)])
        store.value = credential()
        let controller = LicenseController(configuration: try configuration(), client: service, store: store, now: { now })
        await controller.restore()
        await controller.deactivate()
        #expect(controller.status.permitsUse)
        #expect(store.value != nil)
        await controller.deactivate()
        #expect(controller.status == .locked)
        #expect(store.value == nil)
        #expect(!store.offlineAllowed)
    }

    @Test("A failed Keychain save cannot unlock the app or allocate another activation on retry")
    func persistenceFailure() async throws {
        let (service, store) = try fixtures([
            .init(body: #"{"id":"lki_fixture","product":{"product_id":"pdt_fixture"}}"#),
            .init(body: #"{"valid":true}"#), .init(body: #"{"valid":true}"#)
        ])
        store.failSave = true
        let controller = LicenseController(configuration: try configuration(), client: service, store: store, now: { now })
        await controller.activate("fixture-license")
        #expect(!controller.status.permitsUse)
        #expect(controller.issue == .storage)
        store.failSave = false
        await controller.activate("fixture-license")
        #expect(controller.status == .active)
        #expect(LicenseURLProtocol.responses.requests.filter { $0.url?.path == "/licenses/activate" }.count == 1)
    }

    @Test("An activation without successful validation cannot obtain offline grace by retrying")
    func unverifiedActivation() async throws {
        let (service, store) = try fixtures([
            .init(body: #"{"id":"lki_fixture","product":{"product_id":"pdt_fixture"}}"#),
            .init(error: .notConnectedToInternet), .init(error: .notConnectedToInternet)
        ])
        let controller = LicenseController(configuration: try configuration(), client: service, store: store, now: { now })
        await controller.activate("fixture-license")
        #expect(!controller.status.permitsUse)
        await controller.refresh(force: true)
        #expect(!controller.status.permitsUse)
        #expect(!store.offlineAllowed)
    }

    @Test("Stopping the controller prevents an old validation from restoring access")
    func staleResponse() async throws {
        let service = SuspendedLicenseService()
        let store = MemoryLicenseStore()
        store.value = credential()
        let controller = LicenseController(configuration: try configuration(), client: service, store: store)
        let task = Task { await controller.restore() }
        await service.waitUntilRequested()
        controller.stop()
        await service.complete()
        await task.value
        #expect(controller.status == .locked)
    }

    @Test("The model stays paused and rejects imports after licensing is disabled, including after wake/preferences")
    func modelGate() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = KopyModel(isolatedProfile: folder, clipboard: ClipboardController(pasteboard: board))
        model.setLicenseAccess(false)
        model.updatePreferences { $0.incognito = false }
        model.suspend(false)
        model.start()
        model.importPayloads([.text(.init("must not import"))])
        model.copyText("must not copy")
        #expect(model.clipboard.isPaused)
        #expect(!model.isLoadingHistory)
        #expect(model.items.isEmpty)
        #expect(board.string(forType: .string) == nil)
        model.stop()
    }

    @Test("Licence credentials persist in a separate Keychain item")
    func keychainPersistence() throws {
        let identifier = "com.kopy.fixture.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: identifier))
        defer { defaults.removePersistentDomain(forName: identifier) }
        let store = KeychainLicenseStore(service: identifier, defaults: defaults)
        defer { try? store.remove() }
        try store.save(credential())
        let restored = KeychainLicenseStore(service: identifier, defaults: defaults)
        #expect(try restored.load() == credential())
        restored.offlineAllowed = false
        #expect(!store.offlineAllowed)
    }

    @Test("A licence lock preserves saved history and recoverable deletion records")
    func historySurvivesLock() async throws {
        let board = NSPasteboard.withUniqueName()
        let profile = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let model = KopyModel(isolatedProfile: profile, clipboard: ClipboardController(pasteboard: board))
        defer {
            model.stop()
            board.releaseGlobally()
            model.defaults.removePersistentDomain(forName: "Kopy.Test.\(profile.lastPathComponent)")
            try? FileManager.default.removeItem(at: profile)
        }
        model.updatePreferences { $0.incognito = true }
        model.start()
        model.importPayloads([.text(.init("Preserve active licence fixture")), .text(.init("Preserve recovery fixture"))])
        try await wait { model.importRevision == 1 }
        let before = model.items
        model.delete(before[0])
        try await wait { model.items.count == 1 && model.undoAction != nil }
        let undo = model.undoState
        model.setLicenseAccess(false)
        model.prune()
        model.clear(model.items)
        model.importPayloads([.text(.init("Blocked import"))])
        #expect(model.items == [before[1]])
        #expect(model.undoState == undo)
        model.setLicenseAccess(true)
        model.undoDeletion()
        try await wait { model.importRevision == 2 }
        #expect(model.items == before)
    }

    @Test("Missing configuration fails closed without contacting the service")
    func missingConfiguration() async {
        let controller = LicenseController(configuration: nil, client: nil, store: MemoryLicenseStore())
        await controller.restore()
        await controller.activate("fixture-license")
        #expect(controller.status == .locked)
        #expect(controller.issue == .configuration)
    }

    private func wait(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition())
    }

    private func fixtures(_ responses: [LicenseURLProtocol.Response]) throws -> (DodoLicenseClient, MemoryLicenseStore) {
        LicenseURLProtocol.responses.reset(responses)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LicenseURLProtocol.self]
        return (DodoLicenseClient(configuration: try configuration(), session: URLSession(configuration: config)), MemoryLicenseStore())
    }
}

@MainActor
private final class MemoryLicenseStore: LicenseCredentialStoring {
    var value: LicenseCredential?
    var offlineAllowed = true
    var failSave = false
    func load() throws -> LicenseCredential? { value }
    func save(_ credential: LicenseCredential) throws {
        if failSave { throw LicenseIssue.storage }
        value = credential
    }
    func remove() throws { value = nil }
}

private actor SuspendedLicenseService: LicenseServing {
    private var continuation: CheckedContinuation<Bool, any Error>?
    private var waiter: CheckedContinuation<Void, Never>?
    func activate(key: String) async throws -> String { "lki_fixture" }
    func deactivate(_ credential: LicenseCredential) async throws { }
    func validate(_ credential: LicenseCredential) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            waiter?.resume()
            waiter = nil
        }
    }
    func waitUntilRequested() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func complete() { continuation?.resume(returning: true); continuation = nil }
}

private final class LicenseURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        var status = 200
        var body = ""
        var error: URLError.Code?
    }
    final class Responses: @unchecked Sendable {
        private let lock = NSLock()
        private var pending: [Response] = []
        private var captured: [URLRequest] = []
        var requests: [URLRequest] { lock.withLock { captured } }
        func reset(_ responses: [Response]) { lock.withLock { pending = responses; captured = [] } }
        func next(_ request: URLRequest) -> Response {
            lock.withLock {
                var capturedRequest = request
                if capturedRequest.httpBody == nil, let stream = request.httpBodyStream {
                    stream.open()
                    defer { stream.close() }
                    var body = Data()
                    var buffer = [UInt8](repeating: 0, count: 1024)
                    while stream.hasBytesAvailable, body.count < 16_384 {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        guard count > 0 else { break }
                        body.append(contentsOf: buffer.prefix(count))
                    }
                    capturedRequest.httpBody = body
                }
                captured.append(capturedRequest)
                return pending.isEmpty ? Response(status: 500) : pending.removeFirst()
            }
        }
    }
    static let responses = Responses()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let next = Self.responses.next(request)
        if let error = next.error {
            client?.urlProtocol(self, didFailWithError: URLError(error))
        } else if let url = request.url, let response = HTTPURLResponse(url: url, statusCode: next.status, httpVersion: nil, headerFields: nil) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(next.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { }
}
