import AppKit

/// Renders a minimal wallpaper from album art: a large, crisp cover
/// centered over a smooth color gradient derived from the art itself.
/// Ported in-process from the original `compose-wallpaper` CLI tool.
enum WallpaperCompositor {
    /// `targetSize` is one display's size in backing-store pixels — each
    /// display gets a wallpaper in its own aspect ratio, so an ultrawide
    /// next to a laptop doesn't get a cropped copy of the laptop's.
    static func render(cover: NSImage, targetSize: CGSize) -> NSImage? {
        let canvasSize = canvasSize(for: targetSize)
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)

        let hour = Calendar.current.component(.hour, from: Date())
        let isNight = hour < 7 || hour >= 19

        let accent = vividAccent(of: cover)
        let topColor = accent.blended(withFraction: 0.24, of: .white) ?? accent
        let bottomColor = accent.blended(withFraction: isNight ? 0.58 : 0.38, of: .black) ?? accent

        guard let cgContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let context = NSGraphicsContext(cgContext: cgContext, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // Cover art arrives smaller than the size it's drawn at (Spotify
        // tops out around 1429px against a ~1900px draw), so the upscale is
        // the quality bottleneck. The default interpolation is tuned for
        // speed; this is one image per track, so pay for the better filter.
        context.imageInterpolation = .high

        // The rest of the screen is a smooth vertical gradient built from
        // the cover's own dominant color — no muddy blurred backdrop.
        NSGradient(starting: bottomColor, ending: topColor)?.draw(in: canvasRect, angle: 90)

        // The cover art itself is the hero: sized to fill almost the full
        // screen height, centered.
        let artSide = min(canvasRect.height * 0.86, canvasRect.width * 0.9)
        let artRect = CGRect(
            x: canvasRect.midX - artSide / 2,
            y: canvasRect.midY - artSide / 2,
            width: artSide,
            height: artSide
        )
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 60
        shadow.shadowOffset = CGSize(width: 0, height: -18)
        shadow.set()
        NSGraphicsContext.current?.cgContext.saveGState()
        NSBezierPath(roundedRect: artRect, xRadius: artSide * 0.03, yRadius: artSide * 0.03).addClip()
        drawAspectFill(cover, in: artRect)
        NSGraphicsContext.current?.cgContext.restoreGState()

        NSGraphicsContext.restoreGraphicsState()

        guard let finalImage = cgContext.makeImage() else { return nil }
        return NSImage(cgImage: finalImage, size: canvasSize)
    }

    static func jpegData(for image: NSImage, compressionFactor: CGFloat = 0.88) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor])
    }

    /// Small displays are rendered a little larger than life so the cover
    /// stays crisp if the wallpaper is later shown on a bigger screen —
    /// scaled uniformly, never stretched to a different aspect ratio.
    private static func canvasSize(for targetSize: CGSize) -> CGSize {
        guard targetSize.width > 0, targetSize.height > 0 else {
            return CGSize(width: 2880, height: 1800)
        }
        let scale = max(1, 1920 / targetSize.width, 1200 / targetSize.height)
        return CGSize(width: (targetSize.width * scale).rounded(), height: (targetSize.height * scale).rounded())
    }

    private static func drawAspectFill(_ image: NSImage, in rect: CGRect) {
        let source = image.size
        let scale = max(rect.width / source.width, rect.height / source.height)
        let scaledSize = CGSize(width: source.width * scale, height: source.height * scale)
        let destination = CGRect(
            x: rect.midX - scaledSize.width / 2,
            y: rect.midY - scaledSize.height / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
        image.draw(in: destination, from: CGRect(origin: .zero, size: source), operation: .sourceOver, fraction: 1)
    }

    /// The raw pixel-average of most album art lands in a muddy brown/gray
    /// (mixing complementary colors flattens saturation). Boosting
    /// saturation and brightness keeps the derived gradient actually
    /// colorful instead of drab.
    private static func vividAccent(of image: NSImage) -> NSColor {
        let raw = averageColor(of: image)
        guard let converted = raw.usingColorSpace(.deviceRGB) else { return raw }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        converted.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return NSColor(
            hue: hue,
            saturation: min(1, max(saturation, 0.45)),
            brightness: min(1, max(brightness, 0.55)),
            alpha: 1
        )
    }

    private static func averageColor(of image: NSImage) -> NSColor {
        guard let data = image.tiffRepresentation, let rep = NSBitmapImageRep(data: data) else {
            return .systemIndigo
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var samples: CGFloat = 0
        let step = max(1, min(rep.pixelsWide, rep.pixelsHigh) / 18)

        for x in stride(from: 0, to: rep.pixelsWide, by: step) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: step) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                red += color.redComponent
                green += color.greenComponent
                blue += color.blueComponent
                samples += 1
            }
        }

        guard samples > 0 else { return .systemIndigo }
        return NSColor(red: red / samples, green: green / samples, blue: blue / samples, alpha: 1)
    }
}
