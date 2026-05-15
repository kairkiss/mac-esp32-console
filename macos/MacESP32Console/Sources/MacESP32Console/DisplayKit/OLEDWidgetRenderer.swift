import AppKit
import Foundation

enum OLEDWidgetRenderer {
    static func renderMetricDashboard(cpu: Int, mem: Int, temp: Int?, fan: String, app: String) -> OLEDBitmap {
        OLEDRenderer.renderCustom(idPrefix: "dashboard") { ctx in
            drawHeader("MAC STATUS", in: ctx)
            drawBar(label: "CPU", value: cpu, y: 18, in: ctx)
            drawBar(label: "MEM", value: mem, y: 31, in: ctx)
            let tempText = temp.map { "\($0)C" } ?? "--"
            drawSmall("TEMP \(tempText)", x: 4, y: 48, in: ctx)
            drawSmall("FAN \(fan)", x: 72, y: 48, in: ctx)
            drawSmall(String(app.prefix(18)), x: 4, y: 58, in: ctx)
        }
    }

    static func renderNowPlaying(title: String, artist: String, progress: Double) -> OLEDBitmap {
        OLEDRenderer.renderCustom(idPrefix: "music") { ctx in
            drawHeader("NOW PLAYING", in: ctx)
            drawSmall(String(title.prefix(18)), x: 6, y: 22, in: ctx)
            drawSmall(String(artist.prefix(18)), x: 6, y: 35, in: ctx)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.stroke(CGRect(x: 8, y: 50, width: 112, height: 5))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 9, y: 51, width: max(2, min(110, 110 * progress)), height: 3))
        }
    }

    static func renderCalendarNext(title: String, time: String, minutesLeft: Int?) -> OLEDBitmap {
        OLEDRenderer.renderCustom(idPrefix: "calendar") { ctx in
            drawHeader("NEXT EVENT", in: ctx)
            drawSmall(String(title.prefix(18)), x: 6, y: 24, in: ctx)
            drawSmall(time, x: 6, y: 40, in: ctx)
            if let minutesLeft {
                drawSmall("\(minutesLeft) min", x: 74, y: 40, in: ctx)
            }
            drawCornerGlyph("CAL", in: ctx)
        }
    }

    static func renderNetworkError(reason: String, detail: String) -> OLEDBitmap {
        OLEDRenderer.renderCustom(idPrefix: "neterr") { ctx in
            drawHeader("NETWORK", in: ctx)
            drawSmall(reason.uppercased(), x: 6, y: 24, in: ctx)
            drawSmall(String(detail.prefix(20)), x: 6, y: 40, in: ctx)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.stroke(CGRect(x: 104, y: 16, width: 14, height: 10))
            ctx.move(to: CGPoint(x: 103, y: 31))
            ctx.addLine(to: CGPoint(x: 119, y: 47))
            ctx.strokePath()
        }
    }

    static func renderOTAProgress(percent: Int, phase: String) -> OLEDBitmap {
        OLEDRenderer.renderCustom(idPrefix: "ota") { ctx in
            drawHeader("OTA UPDATE", in: ctx)
            drawSmall(phase.uppercased(), x: 8, y: 24, in: ctx)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.stroke(CGRect(x: 8, y: 42, width: 112, height: 8))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 10, y: 44, width: max(1, min(108, CGFloat(percent) / 100 * 108)), height: 4))
            drawSmall("\(percent)%", x: 92, y: 58, in: ctx)
        }
    }

    static func renderDreamcoreText(_ lines: [String]) -> OLEDBitmap {
        OLEDRenderer.renderCustom(idPrefix: "dream") { ctx in
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            ctx.stroke(CGRect(x: 3, y: 3, width: 122, height: 58))
            drawSmall("23:30  silent room", x: 7, y: 15, in: ctx)
            for (index, line) in lines.prefix(3).enumerated() {
                drawSmall(String(line.prefix(18)), x: 7, y: 30 + CGFloat(index * 11), in: ctx)
            }
        }
    }

    private static func drawHeader(_ text: String, in ctx: CGContext) {
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 13))
        drawText(text, x: 4, y: 2, color: .black, size: 9, in: ctx)
    }

    private static func drawBar(label: String, value: Int, y: CGFloat, in ctx: CGContext) {
        drawSmall(label, x: 4, y: y + 1, in: ctx)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.stroke(CGRect(x: 34, y: y, width: 86, height: 7))
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 35, y: y + 1, width: max(1, min(84, CGFloat(value) / 100 * 84)), height: 5))
    }

    private static func drawCornerGlyph(_ text: String, in ctx: CGContext) {
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.stroke(CGRect(x: 96, y: 16, width: 24, height: 24))
        drawText(text, x: 100, y: 25, color: .white, size: 8, in: ctx)
    }

    private static func drawSmall(_ text: String, x: CGFloat, y: CGFloat, in ctx: CGContext) {
        drawText(text, x: x, y: y, color: .white, size: 9, in: ctx)
    }

    private static func drawText(_ text: String, x: CGFloat, y: CGFloat, color: NSColor, size: CGFloat, in ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        let graphicsContext = NSGraphicsContext(cgContext: ctx, flipped: true)
        graphicsContext.shouldAntialias = false
        NSGraphicsContext.current = graphicsContext
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)
        text.draw(at: CGPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
        NSGraphicsContext.restoreGraphicsState()
    }
}
