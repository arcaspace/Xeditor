#!/usr/bin/env swift
//
// Generates Xeditor's app icon. Run with no arguments to render 1024px
// previews plus a contact sheet into /tmp/xeditor-icon/.
//
//   swift scripts/generate-app-icon.swift            # previews
//   swift scripts/generate-app-icon.swift --export   # iconset + .icns
//
// Only CoreGraphics/AppKit are used, so the artwork is reproducible and has
// no external dependencies.
import AppKit
import CoreText

// MARK: - Colour helpers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

let ice = rgb(0x9FE3FF)
let deepIce = rgb(0x5FB9E8)

// MARK: - Canvas helpers

func makeRep(_ width: Int, _ height: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil,
                     pixelsWide: width, pixelsHigh: height,
                     bitsPerSample: 8, samplesPerPixel: 4,
                     hasAlpha: true, isPlanar: false,
                     colorSpaceName: .deviceRGB,
                     bytesPerRow: 0, bitsPerPixel: 0)!
}

func image(from rep: NSBitmapImageRep) -> NSImage {
    let image = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
    image.addRepresentation(rep)
    return image
}

func savePNG(_ rep: NSBitmapImageRep, to path: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode \(path)")
    }
    try! data.write(to: URL(fileURLWithPath: path))
}

/// Superellipse |x|^n + |y|^n = 1, sampled into a closed path.
func squircle(center: CGPoint, half: CGFloat, n: CGFloat = 5) -> NSBezierPath {
    let path = NSBezierPath()
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = center.x + half * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = center.y + half * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        let point = CGPoint(x: x, y: y)
        if i == 0 { path.move(to: point) } else { path.line(to: point) }
    }
    path.close()
    return path
}

func glowShadow(blur: CGFloat, color: NSColor) -> NSShadow {
    let shadow = NSShadow()
    shadow.shadowBlurRadius = blur
    shadow.shadowColor = color
    shadow.shadowOffset = .zero
    return shadow
}

func withShadow(_ shadow: NSShadow, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Base tile

let canvas: CGFloat = 1024
let tileCenter = CGPoint(x: 512, y: 512)
let tileHalf: CGFloat = 412
let tilePath = squircle(center: tileCenter, half: tileHalf)

func drawTile() {
    let background = NSGradient(colors: [rgb(0x24282E), rgb(0x0A0B0D)])!
    background.draw(in: tilePath, angle: -90)

    // Corner falloff keeps the glass from reading as a flat fill.
    let vignette = NSGradient(colors: [rgb(0x000000, 0), rgb(0x000000, 0.55)])!
    vignette.draw(fromCenter: CGPoint(x: 512, y: 610), radius: 60,
                  toCenter: tileCenter, radius: 640, options: [])

    // Cool sheen across the upper third.
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    let sheen = NSGradient(colors: [rgb(0xBFE9FF, 0.10), rgb(0xBFE9FF, 0)])!
    sheen.draw(in: NSRect(x: 100, y: 700, width: 824, height: 224), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
}

func drawTileEdges() {
    // Inner rim light: stroke the squircle and clip to its inside half.
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    rgb(0xFFFFFF, 0.10).setStroke()
    tilePath.lineWidth = 3
    tilePath.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

/// Bright paper tile for the serif monogram concepts.
func drawLightTile(top: NSColor, bottom: NSColor, edge: NSColor) {
    NSGradient(colors: [top, bottom])!.draw(in: tilePath, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    let shade = NSGradient(colors: [rgb(0x000000, 0), rgb(0x000000, 0.06)])!
    shade.draw(in: NSRect(x: 100, y: 100, width: 824, height: 200), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    edge.setStroke()
    tilePath.lineWidth = 2.5
    tilePath.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

/// Centres a glyph by its ink bounds rather than by line metrics, so the X
/// sits optically in the middle of the tile.
func drawSerifLetter(_ letter: String, fontName: String, size: CGFloat,
                     color: NSColor, baselineShift: CGFloat = 0,
                     shadow: NSShadow? = nil) {
    guard let font = NSFont(name: fontName, size: size) else {
        print("Missing font \(fontName)")
        return
    }
    let attributed = NSAttributedString(string: letter, attributes: [
        .font: font,
        .foregroundColor: color,
    ])
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    let x = 512 - bounds.midX
    let baseline = 512 - bounds.midY + baselineShift

    NSGraphicsContext.saveGraphicsState()
    shadow?.set()
    let context = NSGraphicsContext.current!.cgContext
    context.textPosition = CGPoint(x: x, y: baseline)
    CTLineDraw(line, context)
    NSGraphicsContext.restoreGraphicsState()
}

func drawGrain(intensity: CGFloat = 0.018) {
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    var generator = SystemRandomNumberGenerator()
    for _ in 0..<5200 {
        let x = CGFloat.random(in: 100...924, using: &generator)
        let y = CGFloat.random(in: 100...924, using: &generator)
        let white = Bool.random(using: &generator)
        (white ? NSColor.white : NSColor.black).withAlphaComponent(intensity).setFill()
        NSRect(x: x, y: y, width: 1.2, height: 1.2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - A: light blade

func bladePath() -> NSBezierPath {
    let p0 = CGPoint(x: 246, y: 288)
    let p1 = CGPoint(x: 470, y: 610)
    let p2 = CGPoint(x: 792, y: 742)
    let steps = 160
    var left: [CGPoint] = []
    var right: [CGPoint] = []
    left.reserveCapacity(steps + 1)
    right.reserveCapacity(steps + 1)

    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let mt = 1 - t
        let point = CGPoint(x: mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x,
                            y: mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y)
        let dx = 2 * mt * (p1.x - p0.x) + 2 * t * (p2.x - p1.x)
        let dy = 2 * mt * (p1.y - p0.y) + 2 * t * (p2.y - p1.y)
        let length = max(0.0001, sqrt(dx * dx + dy * dy))
        let nx = -dy / length
        let ny = dx / length
        let halfWidth = 34 * pow(sin(.pi * t), 0.55) * (1 - 0.42 * t) + 0.7
        left.append(CGPoint(x: point.x + nx * halfWidth, y: point.y + ny * halfWidth))
        right.append(CGPoint(x: point.x - nx * halfWidth, y: point.y - ny * halfWidth))
    }

    let path = NSBezierPath()
    path.move(to: left[0])
    for point in left.dropFirst() { path.line(to: point) }
    for point in right.reversed() { path.line(to: point) }
    path.close()
    return path
}

func drawBlade() {
    let path = bladePath()

    // Wide, soft halo; then a tighter hot halo; then the crisp body.
    withShadow(glowShadow(blur: 96, color: deepIce.withAlphaComponent(0.38))) {
        rgb(0xFFFFFF, 0.55).setFill()
        path.fill()
    }
    withShadow(glowShadow(blur: 26, color: NSColor.white.withAlphaComponent(0.85))) {
        rgb(0xFFFFFF, 0.95).setFill()
        path.fill()
    }

    path.addClip()
    let body = NSGradient(colors: [
        rgb(0x8FD8F5, 0.95), rgb(0xFFFFFF, 1.0), rgb(0xFFFFFF, 1.0), rgb(0x8FD8F5, 0.85),
    ])!
    body.draw(in: path.bounds.insetBy(dx: -2, dy: -2), angle: 55)
}

// MARK: - B: folded ribbon

func drawFoldedRibbon() {
    let foldY: CGFloat = 548

    // Back plane leans away from the viewer.
    let back = NSBezierPath()
    back.move(to: CGPoint(x: 462, y: foldY))
    back.line(to: CGPoint(x: 556, y: foldY))
    back.line(to: CGPoint(x: 600, y: 756))
    back.line(to: CGPoint(x: 506, y: 768))
    back.close()

    // Front plane stands upright, its cut ends angled rather than squared off.
    let front = NSBezierPath()
    front.move(to: CGPoint(x: 462, y: foldY))
    front.line(to: CGPoint(x: 556, y: foldY))
    front.line(to: CGPoint(x: 542, y: 252))
    front.line(to: CGPoint(x: 448, y: 262))
    front.close()

    withShadow(glowShadow(blur: 80, color: ice.withAlphaComponent(0.5))) {
        rgb(0xD8F2FF, 0.9).setFill()
        back.fill()
        front.fill()
    }

    back.addClip()
    NSGradient(colors: [rgb(0x9FD9F2, 0.95), rgb(0xEAF8FF, 1.0)])!.draw(in: back.bounds, angle: 0)

    front.addClip()
    NSGradient(colors: [rgb(0xFFFFFF, 1.0), rgb(0xBFE6FA, 0.95)])!.draw(in: front.bounds, angle: -90)

    // The fold itself is the brightest edge.
    let crease = NSBezierPath()
    crease.move(to: CGPoint(x: 458, y: foldY))
    crease.line(to: CGPoint(x: 560, y: foldY))
    withShadow(glowShadow(blur: 18, color: .white)) {
        NSColor.white.setStroke()
        crease.lineWidth = 3
        crease.stroke()
    }
}

// MARK: - C: slit of light

func drawSlit() {
    // A slender lens of light, pointed at both ends.
    let lens = NSBezierPath()
    lens.move(to: CGPoint(x: 512, y: 238))
    lens.curve(to: CGPoint(x: 512, y: 786),
               controlPoint1: CGPoint(x: 580, y: 420),
               controlPoint2: CGPoint(x: 580, y: 604))
    lens.curve(to: CGPoint(x: 512, y: 238),
               controlPoint1: CGPoint(x: 444, y: 604),
               controlPoint2: CGPoint(x: 444, y: 420))
    lens.close()

    withShadow(glowShadow(blur: 120, color: deepIce.withAlphaComponent(0.45))) {
        rgb(0xEAF9FF, 0.85).setFill()
        lens.fill()
    }
    withShadow(glowShadow(blur: 34, color: ice.withAlphaComponent(0.75))) {
        rgb(0xEAF9FF, 0.9).setFill()
        lens.fill()
    }

    lens.addClip()
    NSGradient(colors: [rgb(0xFFFFFF), rgb(0xD9F4FF)])!
        .draw(in: lens.bounds, angle: -90)

    // Hot core runs the length of the lens.
    let core = NSBezierPath()
    core.move(to: CGPoint(x: 512, y: 300))
    core.line(to: CGPoint(x: 512, y: 724))
    withShadow(glowShadow(blur: 16, color: .white)) {
        NSColor.white.setStroke()
        core.lineWidth = 3
        core.lineCapStyle = .round
        core.stroke()
    }
}

// MARK: - Render

enum Variant: String, CaseIterable {
    case blade, ribbon, slit
    case didot, bodoni, baskerville

    var isDark: Bool {
        switch self {
        case .blade, .ribbon, .slit: return true
        case .didot, .bodoni, .baskerville: return false
        }
    }
}

func render(_ variant: Variant) -> NSBitmapImageRep {
    let rep = makeRep(1024, 1024)
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true

    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    switch variant {
    case .blade:
        drawTile()
        drawGrain()
        drawBlade()
        drawTileEdges()
    case .ribbon:
        drawTile()
        drawGrain()
        drawFoldedRibbon()
        drawTileEdges()
    case .slit:
        drawTile()
        drawGrain()
        drawSlit()
        drawTileEdges()
    case .didot:
        drawLightTile(top: rgb(0xFFFFFF), bottom: rgb(0xF3EFE7), edge: rgb(0x000000, 0.07))
        drawSerifLetter("X", fontName: "Didot", size: 620, color: rgb(0x141414))
    case .bodoni:
        drawLightTile(top: rgb(0xFFFFFF), bottom: rgb(0xFDFCFA), edge: rgb(0x000000, 0.06))
        drawSerifLetter("X", fontName: "Bodoni 72", size: 650, color: rgb(0x0F0F10))
    case .baskerville:
        drawLightTile(top: rgb(0xFBF9F4), bottom: rgb(0xF1EDE4), edge: rgb(0x000000, 0.07))
        drawSerifLetter("X", fontName: "Baskerville", size: 640, color: rgb(0x1A1815))
    }
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Preview sheet

func contactSheet(_ images: [NSImage]) -> NSBitmapImageRep {
    let iconSize: CGFloat = 512
    let gap: CGFloat = 44
    let margin: CGFloat = 56
    let width = margin * 2 + iconSize * CGFloat(images.count) + gap * CGFloat(images.count - 1)
    let height = margin * 2 + iconSize
    let rep = makeRep(Int(width), Int(height))
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    rgb(0xE9E9EB).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    for (index, image) in images.enumerated() {
        let x = margin + CGFloat(index) * (iconSize + gap)
        image.draw(in: NSRect(x: x, y: margin, width: iconSize, height: iconSize))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Export

func downscale(_ rep: NSBitmapImageRep, to size: Int) -> NSBitmapImageRep {
    let target = makeRep(size, size)
    let context = NSGraphicsContext(bitmapImageRep: target)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true
    image(from: rep).draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return target
}

/// Writes the chosen design as a full .iconset and converts it with iconutil.
func exportIcon() {
    let iconsetDir = "\(outputDir)/AppIcon.iconset"
    try? FileManager.default.removeItem(atPath: iconsetDir)
    try! FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

    let master = render(.bodoni)
    savePNG(master, to: "\(outputDir)/bodoni.png")

    let entries: [(name: String, size: Int)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]
    for entry in entries {
        savePNG(downscale(master, to: entry.size), to: "\(iconsetDir)/\(entry.name)")
    }

    let resources = "Xeditor/Resources"
    try! FileManager.default.createDirectory(atPath: resources, withIntermediateDirectories: true)
    let icnsPath = "\(resources)/AppIcon.icns"

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
    try! iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else {
        fatalError("iconutil failed with status \(iconutil.terminationStatus)")
    }
    print("Wrote \(icnsPath)")
}

// MARK: - Main

let outputDir = "/tmp/xeditor-icon"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

if CommandLine.arguments.contains("--export") {
    exportIcon()
} else {
    let groups: [(String, [Variant])] = [
        ("abstract", [.blade, .ribbon, .slit]),
        ("serif", [.didot, .bodoni, .baskerville]),
    ]

    for (sheetName, variants) in groups {
        var rendered: [NSImage] = []
        for variant in variants {
            let rep = render(variant)
            savePNG(rep, to: "\(outputDir)/\(variant.rawValue).png")
            rendered.append(image(from: rep))
        }
        savePNG(contactSheet(rendered), to: "\(outputDir)/\(sheetName).png")
    }

    print("Wrote previews to \(outputDir)")
}
