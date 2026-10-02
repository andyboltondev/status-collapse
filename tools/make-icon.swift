// Renders Resources/AppIcon.icns. Run: swift tools/make-icon.swift
import AppKit

let top = NSColor(srgbRed: 0.18, green: 0.83, blue: 0.75, alpha: 1)    // teal
let bottom = NSColor(srgbRed: 0.05, green: 0.45, blue: 0.56, alpha: 1) // deep cyan

func render(_ px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // macOS icon grid: artwork fills ~80% of the canvas, corner radius ~22.5% of the artwork.
    let art = NSRect(x: size * 0.1, y: size * 0.1, width: size * 0.8, height: size * 0.8)
    let path = NSBezierPath(roundedRect: art, xRadius: art.width * 0.225, yRadius: art.width * 0.225)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = size * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.set()
    NSColor.black.setFill(); path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(starting: top, ending: bottom)!.draw(in: path, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: art.width * 0.5, weight: .bold)
        .applying(.init(paletteColors: [.white]))
    if let glyph = NSImage(systemSymbolName: "chevron.left.2", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let g = glyph.size
        glyph.draw(in: NSRect(x: art.midX - g.width / 2, y: art.midY - g.height / 2, width: g.width, height: g.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = "build/AppIcon.iconset"
try? fm.removeItem(atPath: set)
try! fm.createDirectory(atPath: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base)@2x.png"))
}
