#if !KOPY_APP_STORE
import Foundation
import Observation

struct LicenseConfiguration: Equatable, Sendable {
    let productID: String
    let environment = "test"

    init(productID: String) throws {
        guard productID.hasPrefix("pdt_"), productID.count <= 100,
              productID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else {
            throw LicenseIssue.configuration
        }
        self.productID = productID
    }

    init(bundle: Bundle = .main) throws {
        guard bundle.object(forInfoDictionaryKey: "KopyLicenseEnvironment") as? String == "test",
              let product = bundle.object(forInfoDictionaryKey: "KopyLicenseProductID") as? String else {
            throw LicenseIssue.configuration
        }
        try self.init(productID: product)
    }
}

struct LicenseCredential: Codable, Equatable, Sendable {
    let key: String
    let instanceID: String
    let productID: String
    let environment: String
    var lastValidatedAt: Date
}

enum LicenseIssue: Error, Equatable, LocalizedError, Sendable {
    case configuration, invalidKey, activationLimit, wrongProduct, connection, provider, malformed, storage

    var errorDescription: String? {
        switch self {
        case .configuration: "Test licensing is not configured in this build. Please contact support."
        case .invalidKey: "This licence is invalid or no longer active. Check your purchase email or contact support."
        case .activationLimit: "This licence is already activated on another Mac. Deactivate that Mac first."
        case .wrongProduct: "This licence belongs to a different product. Please use your Kopy licence."
        case .connection: "Kopy couldn’t reach the licence service. Check your connection and try again."
        case .provider: "The licence service couldn’t complete the request. Please try again later."
        case .malformed: "The licence service returned an unexpected response. Please try again or contact support."
        case .storage: "Kopy couldn’t save its licence in Keychain. Allow Keychain access and try again."
        }
    }
}

enum LicenseStatus: Equatable {
    case locked
    case active
    case offline(until: Date)

    var permitsUse: Bool {
        switch self { case .active, .offline: true; case .locked: false }
    }
}

enum LicensePolicy {
    static let offlineInterval: TimeInterval = 30 * 24 * 60 * 60

    static func offlineStatus(_ credential: LicenseCredential, configuration: LicenseConfiguration,
                              now: Date, allowed: Bool) -> LicenseStatus {
        let deadline = credential.lastValidatedAt.addingTimeInterval(offlineInterval)
        guard allowed, credential.environment == configuration.environment,
              credential.productID == configuration.productID,
              now >= credential.lastValidatedAt, now < deadline else { return .locked }
        return .offline(until: deadline)
    }
}

protocol LicenseServing: Sendable {
    func activate(key: String) async throws -> String
    func validate(_ credential: LicenseCredential) async throws -> Bool
    func deactivate(_ credential: LicenseCredential) async throws
}

@MainActor
protocol LicenseCredentialStoring: AnyObject {
    var offlineAllowed: Bool { get set }
    func load() throws -> LicenseCredential?
    func save(_ credential: LicenseCredential) throws
    func remove() throws
}

@MainActor @Observable
final class LicenseController {
    private(set) var status: LicenseStatus = .locked
    private(set) var issue: LicenseIssue?
    private(set) var isBusy = false
    private(set) var hasCredential = false
    var permissionChanged: ((Bool) -> Void)?
    @ObservationIgnored private let configuration: LicenseConfiguration?
    @ObservationIgnored private let client: (any LicenseServing)?
    @ObservationIgnored private let store: any LicenseCredentialStoring
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var credential: LicenseCredential?
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var lastAttempt: Date?

    init(configuration: LicenseConfiguration?, client: (any LicenseServing)?,
         store: any LicenseCredentialStoring, now: @escaping () -> Date = Date.init) {
        self.configuration = configuration
        self.client = client
        self.store = store
        self.now = now
        if configuration == nil || client == nil { issue = .configuration }
    }

    func restore() async {
        guard let configuration, client != nil, !isBusy else { return }
        do {
            credential = try store.load()
            hasCredential = credential != nil
            if let credential {
                guard credential.environment == configuration.environment,
                      credential.productID == configuration.productID else {
                    store.offlineAllowed = false
                    issue = .wrongProduct
                    publish(.locked)
                    return
                }
                await refresh(force: true)
            }
        } catch { issue = .storage; publish(.locked) }
    }

    func activate(_ input: String) async {
        guard let configuration, let client, !isBusy else { return }
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.count <= 512, !key.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            issue = .invalidKey
            return
        }
        isBusy = true
        epoch += 1
        let operation = epoch
        issue = nil
        defer { if epoch == operation { isBusy = false } }
        do {
            let next: LicenseCredential
            if let existing = credential, existing.key == key {
                next = existing
            } else {
                let instance = try await client.activate(key: key)
                next = LicenseCredential(key: key, instanceID: instance, productID: configuration.productID,
                                         environment: configuration.environment, lastValidatedAt: now())
            }
            guard epoch == operation, !Task.isCancelled else { return }
            store.offlineAllowed = false
            credential = next
            hasCredential = true
            guard try await client.validate(next) else { throw LicenseIssue.invalidKey }
            guard epoch == operation, !Task.isCancelled else { return }
            var verified = next
            verified.lastValidatedAt = now()
            do { try store.save(verified) } catch {
                store.offlineAllowed = false
                throw LicenseIssue.storage
            }
            store.offlineAllowed = true
            credential = verified
            lastAttempt = now()
            publish(.active)
        } catch is CancellationError { }
        catch {
            guard epoch == operation else { return }
            issue = error as? LicenseIssue ?? .provider
            if issue == .invalidKey || issue == .wrongProduct { store.offlineAllowed = false }
            publish(.locked)
        }
    }

    func refresh(force: Bool = false) async {
        guard let configuration, let client, let credential, !isBusy else { return }
        if !force, let lastAttempt, now().timeIntervalSince(lastAttempt) < 5 * 60 {
            if case .offline = status {
                publish(LicensePolicy.offlineStatus(credential, configuration: configuration, now: now(),
                                                    allowed: store.offlineAllowed))
            }
            return
        }
        isBusy = true
        epoch += 1
        let operation = epoch
        lastAttempt = now()
        defer { if epoch == operation { isBusy = false } }
        do {
            guard try await client.validate(credential) else { throw LicenseIssue.invalidKey }
            guard epoch == operation, !Task.isCancelled else { return }
            var verified = credential
            verified.lastValidatedAt = now()
            do { try store.save(verified) } catch { throw LicenseIssue.storage }
            self.credential = verified
            store.offlineAllowed = true
            issue = nil
            publish(.active)
        } catch is CancellationError { }
        catch {
            guard epoch == operation else { return }
            let failure = error as? LicenseIssue ?? .provider
            issue = failure
            if failure == .connection {
                publish(LicensePolicy.offlineStatus(credential, configuration: configuration, now: now(),
                                                    allowed: store.offlineAllowed))
            } else {
                store.offlineAllowed = false
                publish(.locked)
            }
        }
    }

    func deactivate() async {
        guard let client, let credential, !isBusy else { return }
        isBusy = true
        epoch += 1
        let operation = epoch
        issue = nil
        defer { if epoch == operation { isBusy = false } }
        do {
            try await client.deactivate(credential)
            guard epoch == operation, !Task.isCancelled else { return }
            store.offlineAllowed = false
            publish(.locked)
            do { try store.remove() } catch { throw LicenseIssue.storage }
            self.credential = nil
            hasCredential = false
        } catch is CancellationError { }
        catch {
            if epoch == operation {
                issue = error as? LicenseIssue ?? .provider
                if issue == .invalidKey { store.offlineAllowed = false; publish(.locked) }
            }
        }
    }

    func stop() { epoch += 1; isBusy = false }

    private func publish(_ next: LicenseStatus) {
        let previous = status.permitsUse
        status = next
        if previous != next.permitsUse { permissionChanged?(next.permitsUse) }
    }
}
#endif
