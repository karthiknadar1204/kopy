#if !KOPY_APP_STORE
import Foundation

struct DodoLicenseClient: LicenseServing {
    private let configuration: LicenseConfiguration
    private let session: URLSession
    private let baseURL = URL(string: "https://test.dodopayments.com/licenses/")!

    init(configuration: LicenseConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        let settings = URLSessionConfiguration.ephemeral
        settings.httpCookieStorage = nil
        settings.urlCredentialStorage = nil
        settings.requestCachePolicy = .reloadIgnoringLocalCacheData
        settings.timeoutIntervalForRequest = 15
        self.session = session ?? URLSession(configuration: settings, delegate: LicenseRedirectPolicy(), delegateQueue: nil)
    }

    func activate(key: String) async throws -> String {
        let data = try await request("activate", body: ["license_key": key, "name": "Kopy on Mac"])
        guard let reply = try? JSONDecoder().decode(Activation.self, from: data),
              !reply.id.isEmpty, reply.id.count <= 200 else { throw LicenseIssue.malformed }
        guard reply.product.product_id == configuration.productID else {
            _ = try? await request("deactivate", body: ["license_key": key, "license_key_instance_id": reply.id])
            throw LicenseIssue.wrongProduct
        }
        return reply.id
    }

    func validate(_ credential: LicenseCredential) async throws -> Bool {
        guard credential.environment == configuration.environment,
              credential.productID == configuration.productID else { throw LicenseIssue.wrongProduct }
        let data = try await request("validate", body: ["license_key": credential.key,
                                                       "license_key_instance_id": credential.instanceID])
        guard let reply = try? JSONDecoder().decode(Validation.self, from: data) else { throw LicenseIssue.malformed }
        return reply.valid
    }

    func deactivate(_ credential: LicenseCredential) async throws {
        _ = try await request("deactivate", body: ["license_key": credential.key,
                                                  "license_key_instance_id": credential.instanceID])
    }

    private func request(_ path: String, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            switch error.code {
            case .notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed: throw LicenseIssue.connection
            default: throw LicenseIssue.provider
            }
        }
        guard let http = response as? HTTPURLResponse, http.url?.host == baseURL.host,
              data.count <= 128 * 1024 else { throw LicenseIssue.malformed }
        switch http.statusCode {
        case 200..<300: return data
        case 403, 404: throw LicenseIssue.invalidKey
        case 422: throw path == "activate" ? LicenseIssue.activationLimit : LicenseIssue.invalidKey
        default: throw LicenseIssue.provider
        }
    }

    private struct Activation: Decodable { let id: String; let product: Product }
    private struct Product: Decodable { let product_id: String }
    private struct Validation: Decodable { let valid: Bool }
}

private final class LicenseRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
#endif
