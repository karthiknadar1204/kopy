import AppKit

@main
struct GenerateIcon {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            try render(pixels: size, to: folder.appending(path: "icon_\(size)x\(size).png"))
            try render(pixels: 2 * size, to: folder.appending(path: "icon_\(size)x\(size)@2x.png"))
        }
    }

    private static func render(pixels: Int, to url: URL) throws {
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let tile = CGRect(x: 88, y: 88, width: 848, height: 848)
        let contour = CGPath(roundedRect: tile, cornerWidth: 202, cornerHeight: 202, transform: nil)
        context.setFillColor(CGColor(srgbRed: 0.16, green: 0.11, blue: 0.10, alpha: 1))
        context.addPath(contour)
        context.fillPath()
        context.setLineWidth(8)
        context.setStrokeColor(CGColor(srgbRed: 0.37, green: 0.25, blue: 0.21, alpha: 1))
        context.addPath(contour)
        context.strokePath()
        KopyMark.draw(in: context, bounds: CGRect(x: 230, y: 230, width: 564, height: 564),
                      front: CGColor(srgbRed: 1, green: 0.94, blue: 0.89, alpha: 1),
                      back: CGColor(srgbRed: 0.94, green: 0.52, blue: 0.37, alpha: 1))
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
    }
}
