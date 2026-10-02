// Renders the DMG window background. Run: swift tools/make-dmg-background.swift <out.tiff>
// Window is 660x400 pt; app icon sits at (180, 190), Applications at (480, 190) from the top-left.
import AppKit

let W = 660.0, H = 400.0
let teal = NSColor(srgbRed: 0.05, green: 0.55, blue: 0.62, alpha: 1)

func render(scale: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W) * scale, pixelsHigh: Int(H) * scale,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)  // 144 dpi for @2x
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGradient(starting: NSColor(srgbRed: 0.96, green: 0.99, blue: 0.99, alpha: 1),
               ending: NSColor(srgbRed: 0.84, green: 0.94, blue: 0.95, alpha: 1))!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        (s as NSString).draw(in: NSRect(x: 0, y: y, width: W, height: size * 1.4), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
    }
    text("Drag StatusCollapse to Applications", size: 24, weight: .bold,
         color: NSColor(srgbRed: 0.04, green: 0.24, blue: 0.30, alpha: 1), y: H - 70)
    text("Then open it from Applications. It lives in your menu bar.", size: 13, weight: .regular,
         color: NSColor(srgbRed: 0.04, green: 0.24, blue: 0.30, alpha: 0.65), y: H - 98)

    // Arrow between the two icons (AppKit y is bottom-up; icon centres are 190 from the top).
    let y = H - 190
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 270, y: y)); arrow.line(to: NSPoint(x: 385, y: y))
    arrow.lineWidth = 6; arrow.lineCapStyle = .round
    let dash: [CGFloat] = [0.1, 13]; arrow.setLineDash(dash, count: 2, phase: 0)
    teal.withAlphaComponent(0.8).setStroke(); arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 376, y: y + 16)); head.line(to: NSPoint(x: 396, y: y)); head.line(to: NSPoint(x: 376, y: y - 16))
    head.lineWidth = 6; head.lineCapStyle = .round; head.lineJoinStyle = .round
    teal.setStroke(); head.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: W, height: H))
image.addRepresentation(render(scale: 1))
image.addRepresentation(render(scale: 2))
try! image.tiffRepresentation!.write(to: URL(fileURLWithPath: out))
