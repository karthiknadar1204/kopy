import Foundation
import KopyCore

enum TransferRemoteImage {
    private enum ImportError: Error { case response, size, image }

    static func embeddedImage(_ address: String) -> ClipboardImage? {
        guard address.lowercased().hasPrefix("data:image/"), let comma = address.firstIndex(of: ",") else { return nil }
        let content = address[address.index(after: comma)...]
        guard content.utf8.count <= ClipboardPayloadCodec.imageByteLimit * 3 else { return nil }
        let data: Data?
        if address[..<comma].lowercased().hasSuffix(";base64") {
            data = Data(base64Encoded: String(content))
        } else {
            data = decodePercentBytes(content)
        }
        return data.flatMap { ClipboardPayloadCodec.image($0) }
    }

    private static func decodePercentBytes(_ input: Substring) -> Data? {
        var encoded = input.utf8.makeIterator()
        var data = Data()
        while let byte = encoded.next() {
            guard data.count < ClipboardPayloadCodec.imageByteLimit else { return nil }
            if byte == 37 {
                guard let first = encoded.next().flatMap(hex), let second = encoded.next().flatMap(hex) else { return nil }
                data.append(first * 16 + second)
            } else {
                data.append(byte)
            }
        }
        return data
    }

    private static func hex(_ value: UInt8) -> UInt8? {
        switch value {
        case 48...57: value - 48
        case 65...70: value - 55
        case 97...102: value - 87
        default: nil
        }
    }

    static func load(_ url: URL) async throws -> ClipboardImage {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        let session = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              response.mimeType?.hasPrefix("image/") == true else { throw ImportError.response }

        let limit = ClipboardPayloadCodec.imageByteLimit
        guard response.expectedContentLength <= limit else { throw ImportError.size }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw ImportError.size }
            data.append(byte)
        }
        guard let image = ClipboardPayloadCodec.image(data, name: url.lastPathComponent) else { throw ImportError.image }
        return image
    }

    private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
