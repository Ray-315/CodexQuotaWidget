import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 2 else {
    fputs("Usage: generate_app_icon.swift <output-iconset-dir>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: args[1], isDirectory: true)
let fileManager = FileManager.default

try? fileManager.removeItem(at: outputURL)
try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

let iconOutputs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for output in iconOutputs {
    let image = drawIcon(size: output.pixels)
    try writePNG(image: image, to: outputURL.appendingPathComponent(output.name))
}

func drawIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        fatalError("Failed to create drawing context")
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let rect = CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))
    let scale = CGFloat(size)

    drawBackground(in: rect)
    drawBlob(in: rect, scale: scale)
    drawSparkles(in: rect, scale: scale)
    drawCodeGlyph(in: rect, scale: scale)

    image.unlockFocus()
    return image
}

func drawBackground(in rect: CGRect) {
    NSColor.white.setFill()
    rect.fill()
}

func drawBlob(in rect: CGRect, scale: CGFloat) {
    let blobRect = CGRect(
        x: rect.midX - scale * 0.355,
        y: rect.midY - scale * 0.355,
        width: scale * 0.71,
        height: scale * 0.71
    )

    let centers = [
        CGPoint(x: blobRect.midX, y: blobRect.maxY - scale * 0.085),
        CGPoint(x: blobRect.maxX - scale * 0.13, y: blobRect.midY + scale * 0.145),
        CGPoint(x: blobRect.maxX - scale * 0.13, y: blobRect.midY - scale * 0.145),
        CGPoint(x: blobRect.midX, y: blobRect.minY + scale * 0.085),
        CGPoint(x: blobRect.minX + scale * 0.13, y: blobRect.midY - scale * 0.145),
        CGPoint(x: blobRect.minX + scale * 0.13, y: blobRect.midY + scale * 0.145),
        CGPoint(x: blobRect.midX, y: blobRect.midY)
    ]

    let radii = [
        scale * 0.182,
        scale * 0.176,
        scale * 0.176,
        scale * 0.182,
        scale * 0.176,
        scale * 0.176,
        scale * 0.205
    ]

    let blobMaskImage = NSImage(size: NSSize(width: scale, height: scale))
    blobMaskImage.lockFocus()
    NSColor.white.setFill()
    for (center, radius) in zip(centers, radii) {
        let circleRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        NSBezierPath(ovalIn: circleRect).fill()
    }
    blobMaskImage.unlockFocus()

    guard let mask = blobMaskImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return
    }

    let context = NSGraphicsContext.current!.cgContext
    context.saveGState()

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedRed: 0.37, green: 0.45, blue: 0.96, alpha: 0.26)
    shadow.shadowBlurRadius = scale * 0.06
    shadow.shadowOffset = NSSize(width: 0, height: -(scale * 0.012))
    shadow.set()

    context.clip(to: rect, mask: mask)

    let mainGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(calibratedRed: 0.78, green: 0.69, blue: 0.97, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.60, green: 0.63, blue: 0.99, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.31, green: 0.42, blue: 0.99, alpha: 1).cgColor
        ] as CFArray,
        locations: [0, 0.55, 1]
    )!

    context.drawLinearGradient(
        mainGradient,
        start: CGPoint(x: rect.midX, y: rect.maxY - scale * 0.18),
        end: CGPoint(x: rect.midX, y: rect.minY + scale * 0.12),
        options: []
    )

    let topGlow = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor.white.withAlphaComponent(0.62).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor
        ] as CFArray,
        locations: [0, 1]
    )!

    context.drawRadialGradient(
        topGlow,
        startCenter: CGPoint(x: rect.midX, y: rect.maxY - scale * 0.28),
        startRadius: 0,
        endCenter: CGPoint(x: rect.midX, y: rect.maxY - scale * 0.28),
        endRadius: scale * 0.38,
        options: [.drawsAfterEndLocation]
    )

    context.restoreGState()
}

func drawSparkles(in rect: CGRect, scale: CGFloat) {
    let sparkles: [(center: CGPoint, outer: CGFloat)] = [
        (CGPoint(x: rect.midX - scale * 0.195, y: rect.midY + scale * 0.172), scale * 0.027),
        (CGPoint(x: rect.midX + scale * 0.13, y: rect.midY + scale * 0.238), scale * 0.03),
        (CGPoint(x: rect.midX + scale * 0.208, y: rect.midY + scale * 0.17), scale * 0.058)
    ]

    NSColor.white.withAlphaComponent(0.96).setFill()
    for sparkle in sparkles {
        let path = sparklePath(center: sparkle.center, outerRadius: sparkle.outer, innerRadius: sparkle.outer * 0.34)
        path.fill()
    }
}

func sparklePath(center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let points = 4

    for index in 0 ..< points * 2 {
        let angle = (CGFloat(index) * .pi / CGFloat(points)) - (.pi / 2)
        let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
        let point = CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )

        if index == 0 {
            path.move(to: point)
        } else {
            path.line(to: point)
        }
    }

    path.close()
    return path
}

func drawCodeGlyph(in rect: CGRect, scale: CGFloat) {
    NSColor.white.withAlphaComponent(0.97).setStroke()

    let left = NSBezierPath()
    left.lineWidth = scale * 0.045
    left.lineCapStyle = .round
    left.lineJoinStyle = .round
    left.move(to: CGPoint(x: rect.midX - scale * 0.105, y: rect.midY + scale * 0.085))
    left.line(to: CGPoint(x: rect.midX - scale * 0.195, y: rect.midY))
    left.line(to: CGPoint(x: rect.midX - scale * 0.105, y: rect.midY - scale * 0.085))

    let slash = NSBezierPath()
    slash.lineWidth = scale * 0.052
    slash.lineCapStyle = .round
    slash.move(to: CGPoint(x: rect.midX + scale * 0.026, y: rect.midY + scale * 0.135))
    slash.line(to: CGPoint(x: rect.midX - scale * 0.02, y: rect.midY - scale * 0.16))

    let right = NSBezierPath()
    right.lineWidth = scale * 0.045
    right.lineCapStyle = .round
    right.lineJoinStyle = .round
    right.move(to: CGPoint(x: rect.midX + scale * 0.13, y: rect.midY + scale * 0.085))
    right.line(to: CGPoint(x: rect.midX + scale * 0.22, y: rect.midY))
    right.line(to: CGPoint(x: rect.midX + scale * 0.13, y: rect.midY - scale * 0.085))

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.white.withAlphaComponent(0.24)
    shadow.shadowBlurRadius = scale * 0.018
    shadow.shadowOffset = .zero
    shadow.set()

    left.stroke()
    slash.stroke()
    right.stroke()
    NSGraphicsContext.current?.restoreGraphicsState()
}

func writePNG(image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "CodexQuotaWidgetIcon", code: 1)
    }

    try png.write(to: url)
}
