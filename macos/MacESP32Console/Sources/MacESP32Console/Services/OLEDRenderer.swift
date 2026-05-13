import AppKit
import Foundation

enum OLEDRenderer {
    static let width = 128
    static let height = 64
    private static let bytesPerBitmapRow = width / 8

    static func render(text: String, style: ConsoleStyle) -> OLEDBitmap {
        let id = "console-\(Int(Date().timeIntervalSince1970))"
        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()

        pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }

            ctx.setShouldAntialias(false)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            drawChrome(style: style, in: ctx)
            drawText(text, style: style, in: ctx)
        }

        let oledPixels = flipVertical(pixels)
        let bytes = pack1bppLSB(from: oledPixels)
        let image = previewImage(from: oledPixels)
        return OLEDBitmap(id: id, bytes: bytes, previewImage: image)
    }

    static func renderPages(text: String, style: ConsoleStyle, pageId: String = "pages-\(Int(Date().timeIntervalSince1970))") -> [OLEDBitmap] {
        let lines = wrappedLines(for: text, maxChars: style == .bubble ? 8 : 9)
        let linesPerPage = style == .caption ? 3 : 4
        let chunks = stride(from: 0, to: max(lines.count, 1), by: linesPerPage).map {
            Array(lines[$0..<min($0 + linesPerPage, lines.count)]).joined(separator: "\n")
        }
        return chunks.enumerated().map { index, pageText in
            let page = render(text: pageText, style: style)
            return OLEDBitmap(id: "\(pageId)-\(index)", bytes: page.bytes, previewImage: page.previewImage)
        }
    }

    private static func drawChrome(style: ConsoleStyle, in ctx: CGContext) {
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1)
        switch style {
        case .bubble:
            ctx.stroke(CGRect(x: 2.5, y: 3.5, width: 123, height: 57))
        case .caption:
            ctx.move(to: CGPoint(x: 0, y: 48.5))
            ctx.addLine(to: CGPoint(x: 128, y: 48.5))
            ctx.strokePath()
        case .full:
            break
        }
    }

    private static func drawText(_ value: String, style: ConsoleStyle, in ctx: CGContext) {
        let fontSize: CGFloat
        let rect: CGRect
        switch style {
        case .full:
            fontSize = 13
            rect = CGRect(x: 2, y: 3, width: 124, height: 58)
        case .bubble:
            fontSize = 12
            rect = CGRect(x: 8, y: 8, width: 112, height: 48)
        case .caption:
            fontSize = 12
            rect = CGRect(x: 2, y: 5, width: 124, height: 40)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .center

        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let attributed = NSAttributedString(
            string: value,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ]
        )

        NSGraphicsContext.saveGraphicsState()
        let graphicsContext = NSGraphicsContext(cgContext: ctx, flipped: true)
        graphicsContext.shouldAntialias = false
        NSGraphicsContext.current = graphicsContext
        attributed.draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
            context: nil
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func wrappedLines(for value: String, maxChars: Int) -> [String] {
        var lines: [String] = []
        for raw in value.replacingOccurrences(of: "\r", with: "").split(separator: "\n", omittingEmptySubsequences: false) {
            var current = ""
            for char in raw {
                current.append(char)
                if current.count >= maxChars {
                    lines.append(current)
                    current = ""
                }
            }
            if !current.isEmpty || raw.isEmpty { lines.append(current) }
        }
        return lines.isEmpty ? [""] : lines
    }

    private static func pack1bppLSB(from pixels: [UInt8]) -> [UInt8] {
        var packed = [UInt8](repeating: 0, count: bytesPerBitmapRow * height)
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] > 127 {
                packed[y * bytesPerBitmapRow + (x >> 3)] |= UInt8(1 << (x & 7))
            }
        }
        return packed
    }

    private static func flipVertical(_ pixels: [UInt8]) -> [UInt8] {
        var flipped = [UInt8](repeating: 0, count: pixels.count)
        for y in 0..<height {
            let src = y * width
            let dst = (height - 1 - y) * width
            flipped[dst..<(dst + width)] = pixels[src..<(src + width)]
        }
        return flipped
    }

    private static func previewImage(from pixels: [UInt8]) -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }
}
