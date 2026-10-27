// Draws the launcher's icon (a 1024 px PNG): a game controller on a red-to-magenta glass squircle.
// Usage: swift scripts/make_icon.swift <out.png>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "icon.png")
let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let inset = rect.insetBy(dx: 100, dy: 100)
    let shape = NSBezierPath(roundedRect: inset, xRadius: 185, yRadius: 185)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35); shadow.set()
    NSGradient(colors: [NSColor(red: 0.95, green: 0.20, blue: 0.22, alpha: 1), NSColor(red: 0.62, green: 0.10, blue: 0.55, alpha: 1)])!
        .draw(in: shape, angle: -60)
    NSGraphicsContext.current?.restoreGraphicsState()
    // The glass sheen: a soft white wash over the top half.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.35), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSBezierPath(roundedRect: NSRect(x: inset.minX, y: inset.midY, width: inset.width, height: inset.height / 2), xRadius: 185, yRadius: 185), angle: -90)
    NSColor.white.withAlphaComponent(0.4).setStroke(); shape.lineWidth = 6; shape.stroke()
    let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold).applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2 - 10, width: s.width, height: s.height))
    }
    return true
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
