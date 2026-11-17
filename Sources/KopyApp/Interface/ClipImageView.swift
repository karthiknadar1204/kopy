import CoreGraphics
import ImageIO
import KopyCore
import SwiftUI

struct ClipImageView: View {
    private enum Source: Sendable {
        case data(Data)
        case file(ClipboardFile)
    }

    private struct Request: Hashable, Sendable {
        let identity: UUID
        let maxPixels: Int
    }

    private let request: Request
    private let source: Source
    private let contentMode: ContentMode

    init(image: ClipboardImage, maxPixels: Int, contentMode: ContentMode = .fit) {
        request = Request(identity: image.id, maxPixels: maxPixels)
        source = .data(image.data)
        self.contentMode = contentMode
    }

    init(file: ClipboardFile, maxPixels: Int, contentMode: ContentMode = .fit) {
        request = Request(identity: file.id, maxPixels: maxPixels)
        source = file.attachment.map(Source.data) ?? .file(file)
        self.contentMode = contentMode
    }

    @State private var loaded: (request: Request, bitmap: CGImage)?

    var body: some View {
        Group {
            if let loaded, loaded.request.identity == request.identity {
                Image(decorative: loaded.bitmap, scale: 1, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(ShelfTheme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: request, priority: .utility) {
            let bitmap = await ThumbnailLoader.shared.load(source, request: request)
            guard !Task.isCancelled else { return }
            loaded = bitmap.map { (request, $0) }
        }
    }

    private actor ThumbnailLoader {
        static let shared = ThumbnailLoader()

        private let cache: NSCache<NSString, CGImage> = {
            let cache = NSCache<NSString, CGImage>()
            cache.countLimit = 64
            cache.totalCostLimit = 12 * 1024 * 1024
            return cache
        }()

        func load(_ source: Source, request: Request) -> CGImage? {
            guard !Task.isCancelled else { return nil }
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            switch source {
            case .data(let data):
                let key = "\(request.identity.uuidString)-\(request.maxPixels)" as NSString
                if let bitmap = cache.object(forKey: key) { return bitmap }
                let source = CGImageSourceCreateWithData(data as CFData, sourceOptions)
                let bitmap = thumbnail(from: source, maxPixels: request.maxPixels)
                if let bitmap { cache.setObject(bitmap, forKey: key, cost: bitmap.bytesPerRow * bitmap.height) }
                return bitmap
            case .file(let file):
                guard let access = file.openFileAccess() else { return nil }
                return withExtendedLifetime(access) {
                    let source = CGImageSourceCreateWithURL(access.url as CFURL, sourceOptions)
                    return thumbnail(from: source, maxPixels: request.maxPixels)
                }
            }
        }

        private func thumbnail(from source: CGImageSource?, maxPixels: Int) -> CGImage? {
            guard !Task.isCancelled, let source else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(maxPixels, 1)
            ] as CFDictionary)
        }
    }
}
