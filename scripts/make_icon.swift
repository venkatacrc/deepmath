// Draws the ∇ app icon and writes an .iconset folder for iconutil.
// Usage: swift scripts/make_icon.swift OUT.iconset
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // macOS icon grid: the tile is inset ~10% with a ~22% corner radius.
    let tile = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [
        NSColor(red: 0.42, green: 0.45, blue: 0.98, alpha: 1),
        NSColor(red: 0.23, green: 0.16, blue: 0.72, alpha: 1),
    ])!.draw(in: path, angle: -90)

    let size = tile.width * 0.66
    let font = NSFont(name: "Times New Roman", size: size) ?? NSFont.systemFont(ofSize: size, weight: .semibold)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.shadowBlurRadius = s * 0.02
    let text = NSAttributedString(string: "∇", attributes: [
        .font: font,
        .foregroundColor: NSColor(red: 0.96, green: 0.96, blue: 1.0, alpha: 1),
        .shadow: shadow,
    ])
    let line = CTLineCreateWithAttributedString(text)
    let glyph = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.textPosition = CGPoint(x: tile.midX - glyph.midX, y: tile.midY - glyph.midY)
    CTLineDraw(line, ctx)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
