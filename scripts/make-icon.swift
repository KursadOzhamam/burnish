// Renders Burnish's app icon into the asset catalog:
//
//   swift scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset [preview.png]
//
// A deep indigo-to-violet squircle in the app's own accent palette (DesignSystem `Theme`), with a
// scrub brush polishing a disk platter and soap bubbles rising off it: "burnish" means to polish.
// Everything is drawn in code, so the icon can be regenerated and reviewed like any other change.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Shadow colour shared by every element, so they sit on the same light.
let shadowInk = 0x120A2E

/// A glossy bubble: clear centre, lilac rim, specular highlight.
func drawBubble(_ ctx: CGContext, _ c: NSPoint, _ r: CGFloat) {
    let rect = NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    let circle = NSBezierPath(ovalIn: rect)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -r * 0.06), blur: r * 0.25, color: color(UInt32(shadowInk), 0.35).cgColor)
    NSGradient(colors: [color(0xFFFFFF, 0.04), color(0xD8F3FF, 0.16), color(0xF0D9FF, 0.6)],
               atLocations: [0, 0.7, 1], colorSpace: .sRGB)!
        .draw(in: circle, relativeCenterPosition: .zero)
    ctx.restoreGState()

    circle.lineWidth = max(r * 0.05, 3)
    color(0xFFFFFF, 0.92).setStroke()
    circle.stroke()

    // Specular highlights: a bright spot top-left and a faint reflection bottom-right.
    let spot = NSBezierPath(ovalIn: NSRect(x: c.x - r * 0.62, y: c.y + r * 0.22, width: r * 0.5, height: r * 0.32))
    var transform = AffineTransform(translationByX: c.x - r * 0.37, byY: c.y + r * 0.38)
    transform.rotate(byDegrees: 35)
    transform.translate(x: -(c.x - r * 0.37), y: -(c.y + r * 0.38))
    spot.transform(using: transform)
    color(0xFFFFFF, 0.95).setFill()
    spot.fill()
    let arc = NSBezierPath()
    arc.appendArc(withCenter: c, radius: r * 0.78, startAngle: -80, endAngle: -10)
    arc.lineWidth = max(r * 0.06, 2)
    arc.lineCapStyle = .round
    color(0xFFFFFF, 0.55).setStroke()
    arc.stroke()
}

/// A hand scrub brush drawn upright around `center` (bristles down), then rotated by `angle` degrees.
func drawBrush(_ ctx: CGContext, center: NSPoint, angle: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle * .pi / 180)
    ctx.setShadow(offset: CGSize(width: 6, height: -14), blur: 26, color: color(UInt32(shadowInk), 0.55).cgColor)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)

    // Handle: warm coral, the one warm colour against the violet, with a hanging hole.
    let handle = NSBezierPath(roundedRect: NSRect(x: -42, y: 20, width: 84, height: 230), xRadius: 42, yRadius: 42)
    NSGradient(colors: [color(0xFFA477), color(0xF2674A), color(0xC8432F)], atLocations: [0, 0.55, 1],
               colorSpace: .sRGB)!.draw(in: handle, angle: 0)
    let hole = NSBezierPath(ovalIn: NSRect(x: -14, y: 196, width: 28, height: 28))
    color(0x7E2618, 0.9).setFill()
    hole.fill()
    let shine = NSBezierPath(roundedRect: NSRect(x: -26, y: 40, width: 14, height: 140), xRadius: 7, yRadius: 7)
    color(0xFFFFFF, 0.35).setFill()
    shine.fill()

    // The block the bristles are set into.
    let block = NSBezierPath(roundedRect: NSRect(x: -100, y: -40, width: 200, height: 70), xRadius: 26, yRadius: 26)
    NSGradient(colors: [color(0xFFB892), color(0xE45B3D)])!.draw(in: block, angle: -90)

    // Bristles: cream tufts with a slightly ragged tip.
    let tufts = 9
    let width: CGFloat = 184
    for i in 0..<tufts {
        let x = -width / 2 + CGFloat(i) * width / CGFloat(tufts)
        let w = width / CGFloat(tufts) - 4
        let length: CGFloat = 112 + (i % 2 == 0 ? 0 : 10) - abs(CGFloat(i) - 4) * 3
        let tuft = NSBezierPath(roundedRect: NSRect(x: x + 2, y: -40 - length, width: w, height: length + 6),
                                xRadius: w / 2, yRadius: w / 2)
        NSGradient(colors: [color(0xFFF7E2), color(0xF1DDAE)])!.draw(in: tuft, angle: -90)
    }
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    // Drawn in a 1024-point design space whatever the output size.
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale)

    // macOS icon grid: an 824-point body inset 100 points, corner radius about 185.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    color(0x1B1240).setFill()
    squircle.fill()
    ctx.restoreGState()

    // Background: deep indigo, through the app's accent violet (#7044E8), to lilac.
    ctx.saveGState()
    squircle.addClip()
    NSGradient(colors: [color(0x1B1240), color(0x7044E8), color(0xB794FF)], atLocations: [0, 0.6, 1],
               colorSpace: .sRGB)!.draw(in: body, angle: 60)

    // Soft glow behind the motif.
    NSGradient(colors: [color(0xE4D6FF, 0.5), color(0xE4D6FF, 0)])!
        .draw(fromCenter: NSPoint(x: 512, y: 470), radius: 0, toCenter: NSPoint(x: 512, y: 470), radius: 380, options: [])

    // Disk platter: concentric rings for the drive being polished.
    let platter = NSPoint(x: 512, y: 440)
    for (i, radius) in [300.0, 240.0, 180.0].enumerated() {
        let ring = NSBezierPath(ovalIn: NSRect(x: platter.x - radius, y: platter.y - radius * 0.42,
                                               width: radius * 2, height: radius * 0.84))
        ring.lineWidth = 10 - CGFloat(i) * 2
        color(0xFFFFFF, 0.18 - CGFloat(i) * 0.04).setStroke()
        ring.stroke()
    }

    // Glossy top highlight.
    let highlight = NSBezierPath(roundedRect: NSRect(x: 100, y: 560, width: 824, height: 364), xRadius: 185, yRadius: 185)
    NSGradient(colors: [color(0xFFFFFF, 0.2), color(0xFFFFFF, 0)])!.draw(in: highlight, angle: -90)
    ctx.restoreGState()

    drawBrush(ctx, center: NSPoint(x: 690, y: 545), angle: -35)
    let bubbles: [(NSPoint, CGFloat)] = [
        (NSPoint(x: 385, y: 560), 150), (NSPoint(x: 545, y: 790), 66), (NSPoint(x: 255, y: 790), 38),
        (NSPoint(x: 470, y: 330), 34), (NSPoint(x: 710, y: 300), 26)
    ]
    for (center, radius) in bubbles { drawBubble(ctx, center, radius) }

    // A faint inner border keeps the edge defined on light backgrounds.
    let border = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
    border.lineWidth = 4
    color(0xFFFFFF, 0.14).setStroke()
    border.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// The ten images a macOS app icon set needs, and the Contents.json that names them.
var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = "icon_\(base)x\(base)\(factor == 2 ? "@2x" : "").png"
        try render(base * factor).write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(factor)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: out.appendingPathComponent("Contents.json"))

if CommandLine.arguments.count > 2 {
    try render(1024).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
